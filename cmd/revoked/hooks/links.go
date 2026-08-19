package hooks

import (
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// BindLinkHooks bcrypt-hashes a link's plaintext password before save and keeps
// the hash out of API responses; the public route verifies it server-side.
func BindLinkHooks(app core.App) {
	app.OnRecordCreate(util.Coll.Links).BindFunc(func(e *core.RecordEvent) error {
		hashLinkPasswordInPlace(e.Record)
		if e.Record.GetString(util.Fields.Link.Status) == "" {
			e.Record.Set(util.Fields.Link.Status, util.StatusActive)
		}
		return e.Next()
	})

	app.OnRecordUpdate(util.Coll.Links).BindFunc(func(e *core.RecordEvent) error {
		hashLinkPasswordInPlace(e.Record)
		// The transition is only visible before the save, and may only be
		// announced once it commits. Auto-revoke by max-views notifies on its
		// own path.
		revoked := isNewlyRevoked(e.App, e.Record)
		if err := e.Next(); err != nil {
			return err
		}
		if revoked {
			notifyLinkRevoked(e.App, e.Record)
		}
		return nil
	})

	app.OnRecordEnrich(util.Coll.Links).BindFunc(func(e *core.RecordEnrichEvent) error {
		if e.Record != nil {
			// Never expose the hash, but keep a non-secret "is gated" signal for
			// the owner UI. The public route reads the real hash from the DB
			// record, never from this enriched copy.
			if e.Record.GetString(util.Fields.Link.Password) != "" {
				e.Record.Set(util.Fields.Link.Password, linkPasswordMask)
			}
		}
		return e.Next()
	})
}

// linkPasswordMask stands in for the bcrypt hash in API responses; clients read
// it only as a has-password flag.
const linkPasswordMask = "********"

// hashLinkPasswordInPlace bcrypt-hashes a link's plaintext password, skipping
// empty or already-hashed values.
func hashLinkPasswordInPlace(rec *core.Record) {
	pw := rec.GetString(util.Fields.Link.Password)
	if pw == "" || pw == linkPasswordMask || isBcryptHash(pw) {
		return
	}
	hash, err := util.HashPassword(pw)
	if err != nil {
		return
	}
	rec.Set(util.Fields.Link.Password, hash)
}

// isNewlyRevoked reports whether this update flips the link to revoked from
// some other state, so re-saving an already-revoked link does not re-notify.
func isNewlyRevoked(app core.App, rec *core.Record) bool {
	if rec.GetString(util.Fields.Link.Status) != util.StatusRevoked {
		return false
	}
	old, err := app.FindRecordById(util.Coll.Links, rec.Id)
	if err != nil || old == nil {
		return false
	}
	return old.GetString(util.Fields.Link.Status) != util.StatusRevoked
}

// notifyLinkRevoked notifies the link owner and, when the link answered a
// request, the requester whose granted data just went dark.
func notifyLinkRevoked(app core.App, link *core.Record) {
	slug := link.GetString(util.Fields.Link.Slug)
	services.EmitNotification(app,
		link.GetString(util.Fields.Link.User),
		link.GetString(util.Fields.Link.Workspace),
		util.NotificationLinkRevoked,
		"Link revoked",
		"Link "+slug+" was revoked and no longer grants access.",
		util.Coll.Links, link.Id)

	reqId := link.GetString(util.Fields.Link.Request)
	if reqId == "" {
		return
	}
	req, err := app.FindRecordById(util.Coll.Requests, reqId)
	if err != nil || req == nil {
		return
	}
	services.EmitNotification(app,
		req.GetString(util.Fields.Request.User),
		req.GetString(util.Fields.Request.Workspace),
		util.NotificationLinkRevoked,
		"Shared data revoked",
		"A response to your request \""+req.GetString(util.Fields.Request.Slug)+"\" was revoked by the sender.",
		util.Coll.Links, link.Id)
}
