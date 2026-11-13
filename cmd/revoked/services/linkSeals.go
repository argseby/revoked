package services

import (
	"encoding/json"
	"slices"
	"time"

	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// MaxLinkSealsPerRecord caps how many links may carry one encrypted record.
// Every write to the record renews each of them in the same request, so the
// number has to stay one a single request can hold.
const MaxLinkSealsPerRecord = 200

// LinkSeal returns what a link holds for an encrypted record, or nil.
func LinkSeal(app core.App, linkID, recordID string) *core.Record {
	s := util.Fields.LinkSeal
	row, _ := app.FindFirstRecordByFilter(util.Coll.LinkSeals,
		s.Link+" = {:l} && "+s.Record+" = {:r}", dbx.Params{"l": linkID, "r": recordID})
	return row
}

// CurrentLinkSeal returns the link's seal for a record only when it was made
// for the record's current version. A seal of an older version wraps a key the
// value is no longer under, and is never served: showing nothing is right,
// showing yesterday's value is not (design/e2ee-sharing.md §3.3).
func CurrentLinkSeal(app core.App, linkID string, rec *core.Record) *core.Record {
	if !IsSealed(rec) {
		return nil
	}
	row := LinkSeal(app, linkID, rec.Id)
	if row == nil || row.GetInt(util.Fields.LinkSeal.Version) != rec.GetInt(util.Fields.Record.SealedVersion) {
		return nil
	}
	return row
}

// LinkSealsOfRecord returns every seal held for a record, on any link.
func LinkSealsOfRecord(app core.App, recordID string) []*core.Record {
	s := util.Fields.LinkSeal
	rows, _ := app.FindRecordsByFilter(util.Coll.LinkSeals,
		s.Record+" = {:r}", s.Created, 0, 0, dbx.Params{"r": recordID})
	return rows
}

// LinkSealsOfLink returns every seal a link holds.
func LinkSealsOfLink(app core.App, linkID string) []*core.Record {
	s := util.Fields.LinkSeal
	rows, _ := app.FindRecordsByFilter(util.Coll.LinkSeals,
		s.Link+" = {:l}", s.Created, 0, 0, dbx.Params{"l": linkID})
	return rows
}

// CountLinkSeals counts the encrypted entries a link carries.
func CountLinkSeals(app core.App, linkID string) int64 {
	n, _ := app.CountRecords(util.Coll.LinkSeals, dbx.HashExp{util.Fields.LinkSeal.Link: linkID})
	return n
}

// LinkIsLive reports whether a link can still be opened, now or once it is
// resumed. Reading a status must not change it, so an end date that has passed
// counts here even before a read has written it down.
func LinkIsLive(link *core.Record) bool {
	f := util.Fields.Link
	switch link.GetString(f.Status) {
	case util.StatusActive, util.StatusPaused:
	default:
		return false
	}
	if expiresAt := link.GetDateTime(f.ExpiresAt); !expiresAt.IsZero() && expiresAt.Time().Before(time.Now()) {
		return false
	}
	if mv := link.GetInt(f.MaxViews); mv > 0 && link.GetInt(f.ViewCount) >= mv {
		return false
	}
	return true
}

// RenewableLinkSeals returns the seals a write to this record has to renew: of
// the record's current version, on links that name it and can still be opened. Those are
// exactly the seals whose writer wrap the writer's device can open with the
// value key it holds. A seal that fell behind, on a link that was not live when
// the record changed, can only be made again from the link's own key.
func RenewableLinkSeals(app core.App, rec *core.Record) []*core.Record {
	if !IsSealed(rec) {
		return nil
	}
	s := util.Fields.LinkSeal
	version := rec.GetInt(util.Fields.Record.SealedVersion)
	var out []*core.Record
	for _, row := range LinkSealsOfRecord(app, rec.Id) {
		if row.GetInt(s.Version) != version {
			continue
		}
		link, err := app.FindRecordById(util.Coll.Links, row.GetString(s.Link))
		if err != nil || link == nil || !LinkIsLive(link) ||
			!slices.Contains(link.GetStringSlice(util.Fields.Link.Records), rec.Id) {
			continue
		}
		out = append(out, row)
	}
	return out
}

// DeleteLinkSealsOfRecord drops every seal of a record, when it stops being
// encrypted: its links then serve the plain value.
func DeleteLinkSealsOfRecord(app core.App, recordID string) error {
	for _, row := range LinkSealsOfRecord(app, recordID) {
		if err := app.Delete(row); err != nil {
			return err
		}
	}
	return nil
}

// PruneLinkSeals drops the seals of records a link no longer names.
func PruneLinkSeals(app core.App, link *core.Record) error {
	named := link.GetStringSlice(util.Fields.Link.Records)
	for _, row := range LinkSealsOfLink(app, link.Id) {
		if slices.Contains(named, row.GetString(util.Fields.LinkSeal.Record)) {
			continue
		}
		if err := app.Delete(row); err != nil {
			return err
		}
	}
	return nil
}

// LinkKeyWrap is a link's key for the devices holding one scope's key.
type LinkKeyWrap struct {
	Epoch int    `json:"epoch"`
	Wrap  string `json:"wrap"`
}

// LinkKeyWraps reads a link's key wraps by scope: the owner's account scope,
// and the workspace's id while the link is seen by more than its owner.
func LinkKeyWraps(link *core.Record) map[string]LinkKeyWrap {
	out := map[string]LinkKeyWrap{}
	raw := link.GetString(util.Fields.Link.SealedKeyWraps)
	if raw == "" || raw == "null" {
		return out
	}
	_ = json.Unmarshal([]byte(raw), &out)
	return out
}

// TrimLinkKeyWraps drops the workspace's copy of a link's key once the link is
// seen by its owner alone. The server can do that much without holding a key;
// putting it back takes a device that has the link's key.
func TrimLinkKeyWraps(link *core.Record) {
	wraps := LinkKeyWraps(link)
	workspace := link.GetString(util.Fields.Link.Workspace)
	if _, held := wraps[workspace]; !held {
		return
	}
	switch link.GetString(util.Fields.Section.AudienceKind) {
	case "", util.AudiencePrivate:
		delete(wraps, workspace)
		link.Set(util.Fields.Link.SealedKeyWraps, wraps)
	}
}
