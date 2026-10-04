package services

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"os"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// GrantMaxAgeEnv sets the cache hint, in seconds, this server attaches to the
// grants it serves to other servers: how long a reader may keep a value
// before asking again. 0 asks readers to keep nothing.
const GrantMaxAgeEnv = "GRANT_MAX_AGE"

// defaultGrantMaxAge is short on purpose: a revocation that a reader does not
// hear about as an event still takes effect within this window.
const defaultGrantMaxAge = 60

// MaxGrantReadBatch caps one bulk read, so a single request stays a bounded
// amount of work for the server answering it.
const MaxGrantReadBatch = 100

// GrantStatusNotFound answers a read for a grant that does not exist, or whose
// token does not match. The two are deliberately indistinguishable.
const GrantStatusNotFound = "not_found"

// GrantMaxAge returns the configured cache hint in seconds.
func GrantMaxAge() int {
	raw := strings.TrimSpace(os.Getenv(GrantMaxAgeEnv))
	if raw == "" {
		return defaultGrantMaxAge
	}
	v, err := strconv.Atoi(raw)
	if err != nil || v < 0 {
		return defaultGrantMaxAge
	}
	return v
}

// IsRequestGrant reports whether a link answers a request, here or on another
// server. Only these are grants in the sense of the event protocol: a plain
// share has nobody to tell.
func IsRequestGrant(link *core.Record) bool {
	return link.GetString(util.Fields.Link.Request) != "" ||
		link.GetString(util.Fields.Link.RemoteDomain) != ""
}

// LinkGrantMap decodes a link's key → record id map.
func LinkGrantMap(link *core.Record) map[string]string {
	grants := map[string]string{}
	if s := link.GetString(util.Fields.Link.Grants); s != "" {
		_ = json.Unmarshal([]byte(s), &grants)
	}
	return grants
}

// GrantResolution is what a grant reads as right now.
type GrantResolution struct {
	Status string
	Values map[string]string
	ETag   string
}

// ResolveGrant reads a request-born link's granted keys from the vault.
//
// Only an active link yields values. A key whose entry was deleted drops out
// rather than falling back to anything stored on the link. An alias is read
// through to the entry it points at, as everywhere else.
func ResolveGrant(app core.App, link *core.Record) GrantResolution {
	res := GrantResolution{Values: map[string]string{}}
	if appErr := RefreshLinkStatus(app, link); appErr != nil {
		res.Status = link.GetString(util.Fields.Link.Status)
		if res.Status == util.StatusActive {
			// RefreshLinkStatus refused without a stored transition (a view cap
			// whose save failed); report it as what it means.
			res.Status = util.StatusRevoked
		}
		res.ETag = GrantETag(res.Status, nil)
		return res
	}
	res.Status = util.StatusActive
	for key, recID := range LinkGrantMap(link) {
		rec, err := app.FindRecordById(util.Coll.Records, recID)
		if err != nil || rec == nil {
			continue
		}
		if parentID := rec.GetString(util.Fields.Record.AliasOf); parentID != "" {
			parent, err := app.FindRecordById(util.Coll.Records, parentID)
			if err != nil || parent == nil {
				continue
			}
			rec = parent
		}
		res.Values[key] = rec.GetString(util.Fields.Record.Value)
	}
	res.ETag = GrantETag(res.Status, res.Values)
	return res
}

// GrantETag is a strong validator over everything a read returns, so a reader
// that sends it back learns "unchanged" without receiving the values again.
func GrantETag(status string, values map[string]string) string {
	keys := make([]string, 0, len(values))
	for k := range values {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	h := sha256.New()
	h.Write([]byte(status))
	for _, k := range keys {
		h.Write([]byte{0})
		h.Write([]byte(k))
		h.Write([]byte{0})
		h.Write([]byte(values[k]))
	}
	return `"` + hex.EncodeToString(h.Sum(nil))[:32] + `"`
}

// GrantReadItem is one grant asked for in a bulk read.
type GrantReadItem struct {
	ID    string `json:"id"`
	Token string `json:"token"`
	ETag  string `json:"etag,omitempty"`
}

// GrantReadResult is one grant's answer in a bulk read. Values are omitted
// when NotModified is set or the grant does not resolve.
type GrantReadResult struct {
	ID          string            `json:"id"`
	Status      string            `json:"status"`
	Values      map[string]string `json:"values,omitempty"`
	ETag        string            `json:"etag,omitempty"`
	MaxAge      int               `json:"maxAge"`
	NotModified bool              `json:"notModified,omitempty"`
}

// ReadGrants answers a bulk read from another server, or from a service the
// owner signed in to. Each grant is reached by its own token; only links
// handed out with one — an answer to another server's request, or entries
// shared at sign-in — can be read here at all. A grant that is unknown, has
// no token, or is presented with the wrong one answers not_found, so the
// endpoint reveals nothing about which ids exist.
func ReadGrants(app core.App, items []GrantReadItem) []GrantReadResult {
	maxAge := GrantMaxAge()
	out := make([]GrantReadResult, 0, len(items))
	for _, item := range items {
		result := GrantReadResult{ID: item.ID, Status: GrantStatusNotFound, MaxAge: maxAge}
		link, err := app.FindRecordById(util.Coll.Links, item.ID)
		if err != nil || link == nil || !grantTokenMatches(link, item.Token) {
			out = append(out, result)
			continue
		}
		res := ResolveGrant(app, link)
		result.Status = res.Status
		result.ETag = res.ETag
		if item.ETag != "" && item.ETag == res.ETag {
			result.NotModified = true
		} else if res.Status == util.StatusActive {
			result.Values = res.Values
		}
		out = append(out, result)
	}
	return out
}

func grantTokenMatches(link *core.Record, token string) bool {
	stored := link.GetString(util.Fields.Link.GrantTokenHash)
	if stored == "" || token == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(stored), []byte(util.HashToken(token))) == 1
}

// SyncGrantIndex rewrites the index rows of one request-born link: one row
// per entry it resolves while it can still be read, none once it cannot.
func SyncGrantIndex(app core.App, link *core.Record) error {
	if _, err := app.DB().NewQuery(
		"DELETE FROM {{" + util.Coll.GrantRecords + "}} WHERE [[" + util.Fields.GrantRecord.Link + "]] = {:link}").
		Bind(dbx.Params{"link": link.Id}).Execute(); err != nil {
		return err
	}
	if !IsRequestGrant(link) {
		return nil
	}
	status := link.GetString(util.Fields.Link.Status)
	if status != util.StatusActive && status != util.StatusPaused {
		return nil
	}
	col, err := app.FindCollectionByNameOrId(util.Coll.GrantRecords)
	if err != nil {
		return err
	}
	seen := map[string]bool{}
	for _, recID := range LinkGrantMap(link) {
		if recID == "" || seen[recID] {
			continue
		}
		seen[recID] = true
		row := core.NewRecord(col)
		row.Set(util.Fields.GrantRecord.Link, link.Id)
		row.Set(util.Fields.GrantRecord.Record, recID)
		if err := app.Save(row); err != nil {
			return err
		}
	}
	return nil
}

// GrantLinksForRecord returns the request-born links that read an entry,
// directly or through an alias of it. The record delete hook calls it before
// the entry and its aliases are gone.
func GrantLinksForRecord(app core.App, recordID string) []*core.Record {
	ids := []string{recordID}
	aliases, _ := app.FindRecordsByFilter(util.Coll.Records,
		util.Fields.Record.AliasOf+" = {:id}", "", 0, 0, dbx.Params{"id": recordID})
	for _, a := range aliases {
		ids = append(ids, a.Id)
	}

	var linkIDs []string
	for _, id := range ids {
		rows, _ := app.FindRecordsByFilter(util.Coll.GrantRecords,
			util.Fields.GrantRecord.Record+" = {:r}", "", 0, 0, dbx.Params{"r": id})
		for _, row := range rows {
			if l := row.GetString(util.Fields.GrantRecord.Link); !slices.Contains(linkIDs, l) {
				linkIDs = append(linkIDs, l)
			}
		}
	}

	links := make([]*core.Record, 0, len(linkIDs))
	for _, id := range linkIDs {
		if link, err := app.FindRecordById(util.Coll.Links, id); err == nil && link != nil {
			links = append(links, link)
		}
	}
	return links
}

// EventTypeForStatus names the event a link's new status is announced with.
func EventTypeForStatus(status string) string {
	switch status {
	case util.StatusRevoked:
		return util.GrantEventRevoked
	case util.StatusExpired:
		return util.GrantEventExpired
	default:
		return util.GrantEventChanged
	}
}

// DispatchGrantEvents queues one event per link for whoever holds it: the
// requester's server for a cross-server grant, or this server's own request
// callback for a local one. Peer events for the same server share a batch.
//
// Best-effort like notifications: a failure to queue is logged, never
// returned, so the change that caused it still commits.
func DispatchGrantEvents(app core.App, links []*core.Record, eventType string, statusOverride string) {
	now := time.Now()
	byDomain := map[string][]server.GrantEvent{}
	for _, link := range links {
		if !IsRequestGrant(link) {
			continue
		}
		status := link.GetString(util.Fields.Link.Status)
		if statusOverride != "" {
			status = statusOverride
		}
		if domain := link.GetString(util.Fields.Link.RemoteDomain); domain != "" {
			byDomain[domain] = append(byDomain[domain], server.GrantEvent{
				Grant:  link.Id,
				Type:   eventType,
				Status: status,
				At:     now.UnixMilli(),
			})
			continue
		}
		queueLocalCallbackEvent(app, link, eventType, status, now)
	}
	for domain, events := range byDomain {
		if err := enqueueDelivery(app, util.DeliveryKindPeer, domain, "",
			map[string]any{"events": events}); err != nil {
			app.Logger().Error("Failed to queue grant events", "error", err, "domain", domain)
		}
	}
}

// queueLocalCallbackEvent passes an event about a grant on one of this
// server's own requests to that request's callback URL, if it has one.
func queueLocalCallbackEvent(app core.App, link *core.Record, eventType, status string, at time.Time) {
	reqID := link.GetString(util.Fields.Link.Request)
	req, err := app.FindRecordById(util.Coll.Requests, reqID)
	if err != nil || req == nil {
		return
	}
	QueueCallbackEvent(app, req, link.Id, "", eventType, status, at)
}

// QueueCallbackEvent queues the callback delivery that tells a request's
// owner a grant changed. server names the responder's server for a grant that
// lives elsewhere, and is empty for a local one.
func QueueCallbackEvent(app core.App, req *core.Record, responseID, peer, eventType, status string, at time.Time) {
	url := req.GetString(util.Fields.Request.CallbackUrl)
	if url == "" {
		return
	}
	payload := map[string]any{
		"event":      eventType,
		"requestId":  req.Id,
		"slug":       req.GetString(util.Fields.Request.Slug),
		"responseId": responseID,
		"linkId":     responseID,
		"status":     status,
		"at":         at.UTC().Format(time.RFC3339),
	}
	if peer != "" {
		payload["server"] = peer
	}
	if err := enqueueDelivery(app, util.DeliveryKindCallback, url, req.Id, payload); err != nil {
		app.Logger().Error("Failed to queue callback event", "error", err, "request", req.Id)
	}
}

// DispatchRecordChanged announces a changed entry to every grant that reads it.
func DispatchRecordChanged(app core.App, recordID string) {
	links := GrantLinksForRecord(app, recordID)
	live := links[:0]
	for _, l := range links {
		if s := l.GetString(util.Fields.Link.Status); s == util.StatusActive || s == util.StatusPaused {
			live = append(live, l)
		}
	}
	DispatchGrantEvents(app, live, util.GrantEventChanged, "")
}

// DispatchRecordDeleted announces a deleted entry: as a change to a grant
// that still resolves another key, and as a revocation to one left with
// nothing to resolve. The link itself is not touched — it is its owner's.
func DispatchRecordDeleted(app core.App, recordID string, links []*core.Record) {
	if _, err := app.DB().NewQuery(
		"DELETE FROM {{" + util.Coll.GrantRecords + "}} WHERE [[" + util.Fields.GrantRecord.Record + "]] = {:r}").
		Bind(dbx.Params{"r": recordID}).Execute(); err != nil {
		app.Logger().Error("Failed to drop grant index rows", "error", err, "record", recordID)
	}
	var changed, emptied []*core.Record
	for _, link := range links {
		if s := link.GetString(util.Fields.Link.Status); s != util.StatusActive && s != util.StatusPaused {
			continue
		}
		if grantStillResolves(app, link, recordID) {
			changed = append(changed, link)
		} else {
			emptied = append(emptied, link)
		}
	}
	DispatchGrantEvents(app, changed, util.GrantEventChanged, "")
	DispatchGrantEvents(app, emptied, util.GrantEventRevoked, util.StatusRevoked)
}

func grantStillResolves(app core.App, link *core.Record, gone string) bool {
	for _, recID := range LinkGrantMap(link) {
		if recID == gone {
			continue
		}
		if rec, err := app.FindRecordById(util.Coll.Records, recID); err == nil && rec != nil {
			return true
		}
	}
	return false
}

// SweepExpiredGrants settles request-born links whose expiry passed while
// nobody read them, so their holders hear grant.expired without polling.
func SweepExpiredGrants(app core.App, now time.Time) {
	links, err := app.FindRecordsByFilter(util.Coll.Links,
		"status = {:active} && expiresAt != '' && expiresAt < {:now} && (request != '' || remoteDomain != '')",
		"", 100, 0, dbx.Params{
			"active": util.StatusActive,
			"now":    now.UTC().Format(types.DefaultDateLayout),
		})
	if err != nil {
		return
	}
	for _, link := range links {
		RefreshLinkStatus(app, link)
	}
}
