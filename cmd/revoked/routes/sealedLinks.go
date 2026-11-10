package routes

import (
	"errors"
	"net/http"
	"reflect"
	"slices"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// The most seals one request may carry: a link names at most this many records.
const maxSealedLinkSeals = 100

// linkSealInput is one record's seal as a device made it: the record's value
// key of that version for the link's viewers, and the key to that wrap for
// whoever writes the record next (design/e2ee-sharing.md §3.2).
type linkSealInput struct {
	Record     string `json:"record"`
	Version    int    `json:"version"`
	ViewerWrap string `json:"viewerWrap"`
	WriterWrap string `json:"writerWrap"`
}

// recordLinkSealInput is the same, sent with a write to the record: the link
// is named and the version is the one the write produces.
type recordLinkSealInput struct {
	Link               string                          `json:"link"`
	ViewerWrap         string                          `json:"viewerWrap"`
	WriterWrap         string                          `json:"writerWrap"`
	KeyWraps           map[string]services.LinkKeyWrap `json:"keyWraps,omitempty"`
	ExpectedWriterWrap string                          `json:"expectedWriterWrap"`
	ExpectedKeyWraps   map[string]services.LinkKeyWrap `json:"expectedKeyWraps"`
}

// validLinkWraps checks the only thing the server can: that each envelope is
// exactly as long as its content makes it. The viewer's holds a value key and
// the workspace's id, the writer's a copy key. Whether they open is for the
// devices to find out; a wrong one breaks that record on that link until the
// next write, and only someone who may write the record can send one.
func validLinkWraps(workspace, viewerWrap, writerWrap string) bool {
	viewer, ok1 := decodeSealed(viewerWrap)
	writer, ok2 := decodeSealed(writerWrap)
	return ok1 && ok2 &&
		len(viewer) == util.SealedEnvelopeOverhead+util.SealedKeyLength+len(workspace) &&
		len(writer) == util.SealedEnvelopeOverhead+util.SealedKeyLength
}

func validLinkKeyWrap(w services.LinkKeyWrap) bool {
	raw, ok := decodeSealed(w.Wrap)
	return ok && w.Epoch >= 1 && len(raw) == util.SealedEnvelopeOverhead+util.SealedKeyLength
}

// sealedLinkFor loads a link for a member of its workspace who may see it, or
// for edit, change it. Anything else looks like a missing link.
func sealedLinkFor(app core.App, re *core.RequestEvent, edit bool) *core.Record {
	link, err := app.FindRecordById(util.Coll.Links, re.Request.PathValue("id"))
	me := re.Auth.Id
	if err == nil && link != nil &&
		link.GetString(util.FieldWorkspace) == re.Auth.GetString(util.Fields.User.ActiveWorkspace) {
		if _, member := util.WorkspaceMemberOf(app, link.GetString(util.FieldWorkspace), me); member {
			owner := link.GetString(util.FieldUser) == me
			if owner || (edit && services.CanEdit(app, me, link)) || (!edit && services.CanSee(app, me, link)) {
				return link
			}
		}
	}
	_ = appErrorResponse(re, http.StatusNotFound, &util.Errors.LinkNotFound)
	return nil
}

// writeSealedLink puts encrypted records on a link, and keeps the link's key
// for the devices that may show its address again.
//
// A seal is accepted for the record's current version only, and the record
// joins the link in the same transaction, so a link never names an encrypted
// record it holds no key for. Removing a record stays with the collection API;
// its seal goes with it.
func writeSealedLink(app core.App, re *core.RequestEvent) error {
	var body struct {
		Seals            []linkSealInput                 `json:"seals"`
		KeyWraps         map[string]services.LinkKeyWrap `json:"keyWraps"`
		ReplaceKey       bool                            `json:"replaceKey"`
		ExpectedKeyWraps map[string]services.LinkKeyWrap `json:"expectedKeyWraps"`
	}
	if err := re.BindBody(&body); err != nil ||
		(len(body.Seals) == 0 && len(body.KeyWraps) == 0) ||
		len(body.Seals) > maxSealedLinkSeals || len(body.KeyWraps) > 2 {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.SealedInvalid)
	}
	first := sealedLinkFor(app, re, true)
	if first == nil {
		return nil
	}

	me := re.Auth.Id
	f := util.Fields.Link
	r := util.Fields.Record
	s := util.Fields.LinkSeal
	var saved *core.Record
	var before map[string]any
	sealed := []map[string]any{}
	err := app.RunInTransaction(func(tx core.App) error {
		link, err := tx.FindRecordById(util.Coll.Links, first.Id)
		if err != nil {
			return refuse(http.StatusNotFound, &util.Errors.LinkNotFound)
		}
		// Links the server makes by itself are read by a server, not by a
		// person holding the address: answers, sign-in shares, remote grants.
		if link.GetString(f.Request) != "" || link.GetString(f.SignInClient) != "" ||
			link.GetString(f.RemoteDomain) != "" {
			return refuse(http.StatusBadRequest, &util.Errors.SealedRecordUnsupported)
		}
		switch link.GetString(f.Status) {
		case util.StatusRevoked:
			return refuse(http.StatusGone, &util.Errors.LinkRevoked)
		case util.StatusExpired:
			return refuse(http.StatusGone, &util.Errors.LinkExpired)
		}
		workspace := link.GetString(f.Workspace)
		owner := link.GetString(f.User)
		current := services.CurrentKeyEpoch(tx, workspace)
		if current == nil || !services.HoldsWorkspaceKey(tx, workspace, me, current.GetInt(util.Fields.WorkspaceKeyEpoch.Epoch)) {
			return refuse(http.StatusForbidden, &util.Errors.SealedKeyMissing)
		}
		before = link.PublicExport()
		if body.ExpectedKeyWraps != nil && !reflect.DeepEqual(body.ExpectedKeyWraps, services.LinkKeyWraps(link)) {
			return refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
		}

		if body.ReplaceKey {
			if me != owner {
				return refuse(http.StatusForbidden, &util.Errors.NotAuthorized)
			}
			if !reflect.DeepEqual(body.ExpectedKeyWraps, services.LinkKeyWraps(link)) {
				return refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
			}
			covered := map[string]bool{}
			for _, seal := range body.Seals {
				if !slices.Contains(link.GetStringSlice(f.Records), seal.Record) {
					return refuse(http.StatusBadRequest, &util.Errors.SealedLinkContent)
				}
				covered[seal.Record] = true
			}
			for _, rec := range services.LinkRecords(tx, link) {
				if services.IsSealed(rec) && !covered[rec.Id] {
					return refuse(http.StatusConflict, &util.Errors.SealedLinkSealsMissing)
				}
			}
			if _, ok := body.KeyWraps[util.SealedAccountScope(owner)]; !ok {
				return refuse(http.StatusBadRequest, &util.Errors.SealedLinkContent)
			}
			if audience := link.GetString(util.Fields.Section.AudienceKind); audience != "" && audience != util.AudiencePrivate {
				if _, ok := body.KeyWraps[workspace]; !ok {
					return refuse(http.StatusBadRequest, &util.Errors.SealedLinkContent)
				}
			}
		}
		wraps := services.LinkKeyWraps(link)
		accountScope := util.SealedAccountScope(owner)
		if body.ReplaceKey {
			wraps = map[string]services.LinkKeyWrap{}
		}
		if failure := mergeLinkKeyWraps(tx, link, me, wraps, body.KeyWraps); failure != nil {
			return failure
		}

		records := link.GetStringSlice(f.Records)
		seen := map[string]bool{}
		for _, seal := range body.Seals {
			if seen[seal.Record] || !sealedRecordID.MatchString(seal.Record) {
				return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
			}
			seen[seal.Record] = true
			rec, err := tx.FindRecordById(util.Coll.Records, seal.Record)
			// A record the caller cannot see reads like one that is not there.
			if err != nil || rec == nil || rec.GetString(r.Workspace) != workspace ||
				!services.IsSealed(rec) || rec.GetString(r.Type) == util.TypeFile || rec.GetString(r.AliasOf) != "" ||
				(rec.GetString(r.User) != me && !services.CanSee(tx, me, rec)) {
				return refuse(http.StatusBadRequest, &util.Errors.SealedLinkContent)
			}
			if rec.GetInt(r.SealedVersion) != seal.Version {
				return refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
			}
			if !validLinkWraps(workspace, seal.ViewerWrap, seal.WriterWrap) {
				return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
			}
			row := services.LinkSeal(tx, link.Id, rec.Id)
			if row == nil {
				if len(services.LinkSealsOfRecord(tx, rec.Id)) >= services.MaxLinkSealsPerRecord {
					return refuse(http.StatusConflict, &util.Errors.SealedLinkContent)
				}
				collection, err := tx.FindCollectionByNameOrId(util.Coll.LinkSeals)
				if err != nil {
					return err
				}
				row = core.NewRecord(collection)
				row.Set(s.Link, link.Id)
				row.Set(s.Record, rec.Id)
			}
			row.Set(s.Version, seal.Version)
			row.Set(s.ViewerWrap, seal.ViewerWrap)
			row.Set(s.WriterWrap, seal.WriterWrap)
			if err := tx.Save(row); err != nil {
				return err
			}
			if !slices.Contains(records, rec.Id) {
				records = append(records, rec.Id)
			}
			sealed = append(sealed, map[string]any{"record": rec.Id, "version": seal.Version})
		}

		// Without the owner's copy of the key, the owner could never show the
		// address of their own link again.
		if _, held := wraps[accountScope]; !held && len(services.LinkSealsOfLink(tx, link.Id)) > 0 {
			return refuse(http.StatusBadRequest, &util.Errors.SealedLinkContent)
		}
		link.Set(f.Records, records)
		link.Set(f.SealedKeyWraps, wraps)
		// The link's own hooks run on this save: its owner must see every
		// record added, and each encrypted one must have its seal by now.
		if err := tx.Save(link); err != nil {
			return err
		}
		saved = link
		return nil
	})
	if err != nil {
		var refusal *sealedRefusal
		if errors.As(err, &refusal) {
			return writeSealedResult(re, err)
		}
		return re.BadRequestError("Failed to save.", err)
	}

	services.RecordAudit(app, services.AuditEntry{
		Action:     util.AuditActionUpdate,
		Collection: util.Coll.Links,
		RecordId:   saved.Id,
		Workspace:  saved.GetString(f.Workspace),
		User:       me,
		Ip:         re.Request.RemoteAddr,
		UserAgent:  re.Request.UserAgent(),
		OldData:    before,
		NewData:    saved.PublicExport(),
	})
	return re.JSON(http.StatusOK, map[string]any{
		"ok":      true,
		"link":    saved.Id,
		"records": saved.GetStringSlice(f.Records),
		"seals":   sealed,
	})
}

// sealedLinkState tells a device that sees a link what it holds for encrypted
// records: the link's key for the scopes it was wrapped to, and per record
// whether the seal is of the record's current version. A seal that fell behind
// shows nothing to viewers until a device holding the link's key makes it
// again.
func sealedLinkState(app core.App, re *core.RequestEvent) error {
	link := sealedLinkFor(app, re, false)
	if link == nil {
		return nil
	}
	s := util.Fields.LinkSeal
	seals := []map[string]any{}
	for _, row := range services.LinkSealsOfLink(app, link.Id) {
		rec, err := app.FindRecordById(util.Coll.Records, row.GetString(s.Record))
		seals = append(seals, map[string]any{
			"record":  row.GetString(s.Record),
			"version": row.GetInt(s.Version),
			"current": err == nil && services.CurrentLinkSeal(app, link.Id, rec) != nil,
		})
	}
	return re.JSON(http.StatusOK, map[string]any{
		"link":     link.Id,
		"keyWraps": services.LinkKeyWraps(link),
		"seals":    seals,
	})
}

// sealedRecordLinks lists what a device has to renew along with a write to an
// encrypted record: per live link carrying it, the key to that link's wrap.
// The writer learns that those links exist, and nothing else about them.
func sealedRecordLinks(app core.App, re *core.RequestEvent) error {
	rec, err := app.FindRecordById(util.Coll.Records, re.Request.PathValue("id"))
	if err != nil || rec == nil {
		return appErrorResponse(re, http.StatusNotFound, &util.Errors.RecordNotFound)
	}
	if !authorizeSealedUpdate(app, re, rec) {
		return nil
	}
	if !services.IsSealed(rec) {
		links := []map[string]any{}
		for _, link := range services.LinksReadingRecord(app, rec.Id) {
			if !services.CanSee(app, re.Auth.Id, link) || !linkCanCarryRecord(app, link, rec.Id) {
				continue
			}
			links = append(links, map[string]any{
				"id": link.Id, "user": link.GetString(util.FieldUser),
				"workspace":      link.GetString(util.FieldWorkspace),
				"audienceKind":   link.GetString(util.Fields.Section.AudienceKind),
				"sealedKeyWraps": services.LinkKeyWraps(link),
			})
		}
		return re.JSON(http.StatusOK, map[string]any{"record": rec.Id, "version": rec.GetInt(util.Fields.Record.SealedVersion), "links": links})
	}
	s := util.Fields.LinkSeal
	links := []map[string]any{}
	for _, row := range services.RenewableLinkSeals(app, rec) {
		links = append(links, map[string]any{
			"link":       row.GetString(s.Link),
			"writerWrap": row.GetString(s.WriterWrap),
		})
	}
	return re.JSON(http.StatusOK, map[string]any{
		"record":  rec.Id,
		"version": rec.GetInt(util.Fields.Record.SealedVersion),
		"links":   links,
	})
}

// renewLinkSeals moves a record's seals to the version a write just made. Every
// live link carrying the record has to be covered, or the write is refused and
// names the links it missed: a link must never fall behind a value it is meant
// to show. rec is the record as it was before the write.
func renewLinkSeals(tx core.App, rec *core.Record, version int, given []recordLinkSealInput) *sealedRefusal {
	required := services.RenewableLinkSeals(tx, rec)
	if len(required) == 0 {
		return nil
	}
	s := util.Fields.LinkSeal
	workspace := rec.GetString(util.Fields.Record.Workspace)
	byLink := map[string]recordLinkSealInput{}
	for _, seal := range given {
		byLink[seal.Link] = seal
	}
	var missing []string
	for _, row := range required {
		seal, ok := byLink[row.GetString(s.Link)]
		if !ok || seal.ExpectedWriterWrap != row.GetString(s.WriterWrap) {
			missing = append(missing, row.GetString(s.Link))
		}
	}
	if len(missing) > 0 {
		refusal := refuse(http.StatusConflict, &util.Errors.SealedLinkSealsMissing)
		refusal.extra = map[string]any{"links": missing}
		return refusal
	}
	for _, row := range required {
		seal := byLink[row.GetString(s.Link)]
		if !validLinkWraps(workspace, seal.ViewerWrap, seal.WriterWrap) {
			return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
		row.Set(s.Version, version)
		row.Set(s.ViewerWrap, seal.ViewerWrap)
		row.Set(s.WriterWrap, seal.WriterWrap)
		if err := tx.Save(row); err != nil {
			return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
	}
	return nil
}

// mergeLinkKeyWraps validates each scope before making it available on a link.
func mergeLinkKeyWraps(tx core.App, link *core.Record, me string, wraps, given map[string]services.LinkKeyWrap) *sealedRefusal {
	if len(given) > 2 {
		return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
	}
	owner, workspace := link.GetString(util.FieldUser), link.GetString(util.FieldWorkspace)
	for scope, wrap := range given {
		if !validLinkKeyWrap(wrap) {
			return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
		switch scope {
		case util.SealedAccountScope(owner):
			if me != owner {
				return refuse(http.StatusForbidden, &util.Errors.NotAuthorized)
			}
			epoch := services.CurrentAccountEpoch(tx, owner)
			a := util.Fields.AccountKeyEpoch
			if epoch == nil || epoch.GetBool(a.RotationDue) || epoch.GetInt(a.Epoch) != wrap.Epoch || !services.HoldsAccountKey(tx, owner, wrap.Epoch) {
				return refuse(http.StatusConflict, &util.Errors.SealedEpochStale)
			}
		case workspace:
			switch link.GetString(util.Fields.Section.AudienceKind) {
			case "", util.AudiencePrivate:
				return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
			}
			if failure := checkSealedWrite(tx, workspace, me, wrap.Epoch); failure != nil {
				return failure
			}
		default:
			return refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
		wraps[scope] = wrap
	}
	return nil
}

// A real record may be carried from a section, but encrypted aliases and
// server-to-server grants are deliberately excluded.
func linkCanCarryRecord(app core.App, link *core.Record, id string) bool {
	f := util.Fields.Link
	if link.GetString(f.Request) != "" || link.GetString(f.SignInClient) != "" || link.GetString(f.RemoteDomain) != "" {
		return false
	}
	if slices.Contains(link.GetStringSlice(f.Records), id) {
		return true
	}
	for _, sid := range link.GetStringSlice(f.Sections) {
		section, err := app.FindRecordById(util.Coll.Sections, sid)
		if err == nil && slices.Contains(section.GetStringSlice(util.Fields.Section.Records), id) {
			return true
		}
	}
	return false
}

// carryPlainRecord installs the seals for a record's first encrypted version.
// The record and all of these links commit together, or none do.
func carryPlainRecord(tx core.App, rec *core.Record, me string, version int, given []recordLinkSealInput, drop bool) ([]*core.Record, *sealedRefusal) {
	live := services.LinksReadingRecord(tx, rec.Id)
	byID := map[string]*core.Record{}
	for _, link := range live {
		byID[link.Id] = link
	}
	kept := map[string]bool{}
	for _, seal := range given {
		link := byID[seal.Link]
		if kept[seal.Link] || link == nil || !services.CanSee(tx, me, link) || !linkCanCarryRecord(tx, link, rec.Id) ||
			!validLinkWraps(rec.GetString(util.FieldWorkspace), seal.ViewerWrap, seal.WriterWrap) {
			return nil, refuse(http.StatusBadRequest, &util.Errors.SealedLinkContent)
		}
		kept[seal.Link] = true
	}
	var dropped []*core.Record
	for _, link := range live {
		if !kept[link.Id] {
			dropped = append(dropped, link)
		}
	}
	if len(dropped) > 0 && !drop {
		failure := refuse(http.StatusConflict, &util.Errors.SealedLinksAffected)
		failure.extra = map[string]any{"links": len(dropped)}
		return nil, failure
	}
	collection, err := tx.FindCollectionByNameOrId(util.Coll.LinkSeals)
	if err != nil {
		return nil, refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
	}
	for _, seal := range given {
		link := byID[seal.Link]
		wraps := services.LinkKeyWraps(link)
		if !reflect.DeepEqual(wraps, seal.ExpectedKeyWraps) {
			return nil, refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
		}
		// Carrying a record must never replace a link's existing owner key.
		for scope, wrap := range seal.KeyWraps {
			if old, ok := wraps[scope]; ok && old != wrap {
				return nil, refuse(http.StatusConflict, &util.Errors.SealedVersionConflict)
			}
		}
		if failure := mergeLinkKeyWraps(tx, link, me, wraps, seal.KeyWraps); failure != nil {
			return nil, failure
		}
		if _, ok := wraps[util.SealedAccountScope(link.GetString(util.FieldUser))]; !ok {
			return nil, refuse(http.StatusBadRequest, &util.Errors.SealedLinkContent)
		}
		row := core.NewRecord(collection)
		s := util.Fields.LinkSeal
		row.Set(s.Link, link.Id)
		row.Set(s.Record, rec.Id)
		row.Set(s.Version, version)
		row.Set(s.ViewerWrap, seal.ViewerWrap)
		row.Set(s.WriterWrap, seal.WriterWrap)
		if err := tx.Save(row); err != nil {
			return nil, refuse(http.StatusBadRequest, &util.Errors.SealedInvalid)
		}
		ids := link.GetStringSlice(util.Fields.Link.Records)
		if !slices.Contains(ids, rec.Id) {
			ids = append(ids, rec.Id)
		}
		link.Set(util.Fields.Link.Records, ids)
		link.Set(util.Fields.Link.SealedKeyWraps, wraps)
		if err := tx.Save(link); err != nil {
			return nil, refuse(http.StatusBadRequest, &util.Errors.SealedLinkContent)
		}
	}
	return dropped, nil
}
