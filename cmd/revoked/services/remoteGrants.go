package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"slices"
	"sync"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// RemoteResolution is what a remote grant read as for the requester.
//
// Unreachable is set when the responder's server could not be asked and no
// value was kept within its maxAge: the grant then carries no values, and the
// requester is told so instead of being handed a stale copy.
type RemoteResolution struct {
	Status      string
	Values      map[string]string
	ETag        string
	MaxAge      int
	Unreachable bool
}

type remoteCacheEntry struct {
	status  string
	values  map[string]string
	etag    string
	maxAge  int
	expires time.Time
}

// remoteGrantCache keeps what a responder's server allowed to be kept, for as
// long as it allowed. It lives in memory only: a restart forgets every value,
// which is the point.
var remoteGrantCache = struct {
	sync.Mutex
	m map[string]remoteCacheEntry
}{m: map[string]remoteCacheEntry{}}

func remoteCacheKey(domain, grant string) string { return domain + "|" + grant }

// ForgetRemoteGrant drops a cached value, as an event about the grant demands.
func ForgetRemoteGrant(domain, grant string) {
	remoteGrantCache.Lock()
	delete(remoteGrantCache.m, remoteCacheKey(domain, grant))
	remoteGrantCache.Unlock()
}

// RememberRemoteGrant caches a fresh read for as long as its maxAge allows.
func RememberRemoteGrant(domain, grant string, r GrantReadResult, now time.Time) {
	if r.MaxAge <= 0 || r.Status == GrantStatusNotFound {
		ForgetRemoteGrant(domain, grant)
		return
	}
	remoteGrantCache.Lock()
	remoteGrantCache.m[remoteCacheKey(domain, grant)] = remoteCacheEntry{
		status:  r.Status,
		values:  r.Values,
		etag:    r.ETag,
		maxAge:  r.MaxAge,
		expires: now.Add(time.Duration(r.MaxAge) * time.Second),
	}
	remoteGrantCache.Unlock()
}

// FetchRemoteGrants asks one responder's server for a batch of grants.
func FetchRemoteGrants(domain string, items []GrantReadItem) ([]GrantReadResult, error) {
	body, err := json.Marshal(map[string]any{"grants": items})
	if err != nil {
		return nil, err
	}
	base, _ := util.PeerBaseURL(domain)
	req, err := http.NewRequest(http.MethodPost, base+"/api/grants/resolve", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := util.NewSafeCallbackClient(PeerFetchTimeout).Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, err
	}
	var out struct {
		Items []GrantReadResult `json:"items"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, err
	}
	return out.Items, nil
}

// ResolveRemoteGrants reads remote grants for the requester, keyed by
// remoteGrants id. Grants on the same server are read in batches, values kept
// within their maxAge are reused without asking, and a kept value past its
// maxAge is revalidated with its ETag.
//
// A status the responder's server reports is written back, so the stored one
// follows the server even when an event was missed.
func ResolveRemoteGrants(app core.App, grants []*core.Record) map[string]RemoteResolution {
	f := util.Fields.RemoteGrant
	now := time.Now()
	out := map[string]RemoteResolution{}

	type pending struct {
		rec    *core.Record
		cached *remoteCacheEntry
	}
	byDomain := map[string][]pending{}

	remoteGrantCache.Lock()
	for _, rec := range grants {
		domain, grant := rec.GetString(f.Domain), rec.GetString(f.Grant)
		entry, ok := remoteGrantCache.m[remoteCacheKey(domain, grant)]
		if ok && now.Before(entry.expires) {
			out[rec.Id] = RemoteResolution{Status: entry.status, Values: entry.values, ETag: entry.etag, MaxAge: entry.maxAge}
			continue
		}
		p := pending{rec: rec}
		if ok {
			e := entry
			p.cached = &e
		}
		byDomain[domain] = append(byDomain[domain], p)
	}
	remoteGrantCache.Unlock()

	for domain, list := range byDomain {
		for start := 0; start < len(list); start += MaxGrantReadBatch {
			chunk := list[start:min(start+MaxGrantReadBatch, len(list))]
			items := make([]GrantReadItem, 0, len(chunk))
			for _, p := range chunk {
				item := GrantReadItem{ID: p.rec.GetString(f.Grant), Token: p.rec.GetString(f.Token)}
				if p.cached != nil {
					item.ETag = p.cached.etag
				}
				items = append(items, item)
			}
			results, err := FetchRemoteGrants(domain, items)
			byID := map[string]GrantReadResult{}
			for _, r := range results {
				byID[r.ID] = r
			}
			for _, p := range chunk {
				r, ok := byID[p.rec.GetString(f.Grant)]
				if err != nil || !ok {
					out[p.rec.Id] = RemoteResolution{Status: p.rec.GetString(f.Status), Unreachable: true}
					continue
				}
				if r.NotModified && p.cached != nil {
					r.Values = p.cached.values
				}
				RememberRemoteGrant(domain, p.rec.GetString(f.Grant), r, now)
				status := r.Status
				if status == GrantStatusNotFound {
					status = util.StatusRevoked
				}
				out[p.rec.Id] = RemoteResolution{Status: status, Values: r.Values, ETag: r.ETag, MaxAge: r.MaxAge}
				// statusAt is left alone: it orders events in the responder's
				// server's clock, which this server's clock cannot stand in for.
				if status != p.rec.GetString(f.Status) && slices.Contains(util.LinkStatuses, status) {
					p.rec.Set(f.Status, status)
					if err := app.Save(p.rec); err != nil {
						app.Logger().Error("Failed to update remote grant status", "error", err, "grant", p.rec.Id)
					}
				}
			}
		}
	}
	return out
}

// ApplyGrantEvents records verified events from a responder's server against
// the remote grants this server holds from it, and passes each on to the
// request's owner: as a notification when data went dark, and to the request's
// callback URL in every case. Events about grants this server does not hold
// are ignored, as are events older than the status already recorded.
func ApplyGrantEvents(app core.App, sender string, events []server.GrantEvent) int {
	f := util.Fields.RemoteGrant
	applied := 0
	for _, ev := range events {
		if !slices.Contains(util.GrantEventTypes, ev.Type) || !slices.Contains(util.LinkStatuses, ev.Status) {
			continue
		}
		rec, err := app.FindFirstRecordByFilter(util.Coll.RemoteGrants,
			f.Domain+" = {:d} && "+f.Grant+" = {:g}", dbx.Params{"d": sender, "g": ev.Grant})
		if err != nil || rec == nil {
			continue
		}
		ForgetRemoteGrant(sender, ev.Grant)
		if ev.At < int64(rec.GetInt(f.StatusAt)) {
			continue
		}
		previous := rec.GetString(f.Status)
		rec.Set(f.Status, ev.Status)
		rec.Set(f.StatusAt, ev.At)
		if err := app.Save(rec); err != nil {
			app.Logger().Error("Failed to apply grant event", "error", err, "grant", rec.Id)
			continue
		}
		applied++

		req, err := app.FindRecordById(util.Coll.Requests, rec.GetString(f.Request))
		if err != nil || req == nil {
			continue
		}
		if ev.Status != previous {
			notifyRemoteGrantEnded(app, req, ev.Status)
		}
		QueueCallbackEvent(app, req, rec.Id, sender, ev.Type, ev.Status, time.UnixMilli(ev.At))
	}
	return applied
}

// notifyRemoteGrantEnded tells the requester that an answer stopped
// resolving, as notifyLinkRevoked does for an answer kept on this server.
func notifyRemoteGrantEnded(app core.App, req *core.Record, status string) {
	slug := req.GetString(util.Fields.Request.Slug)
	switch status {
	case util.StatusRevoked:
		EmitNotification(app, req.GetString(util.Fields.Request.User),
			req.GetString(util.Fields.Request.Workspace),
			util.NotificationLinkRevoked,
			"Shared data revoked",
			"A response to your request \""+slug+"\" was revoked by the sender.",
			util.Coll.Requests, req.Id)
	case util.StatusExpired:
		EmitNotification(app, req.GetString(util.Fields.Request.User),
			req.GetString(util.Fields.Request.Workspace),
			util.NotificationLinkExpired,
			"Shared data expired",
			"A response to your request \""+slug+"\" has expired.",
			util.Coll.Requests, req.Id)
	}
}
