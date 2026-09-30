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
		if err := requireApplicationWatermark(e.Record); err != nil {
			return err
		}
		if err := validateLinkConnection(e.App, e.Record, ""); err != nil {
			return err
		}
		resolvePasswordWrite(e.Record, util.Fields.Link.Password)
		if e.Record.GetString(util.Fields.Link.Status) == "" {
			e.Record.Set(util.Fields.Link.Status, util.StatusActive)
		}
		return e.Next()
	})

	app.OnRecordUpdate(util.Coll.Links).BindFunc(func(e *core.RecordEvent) error {
		if err := requireApplicationWatermark(e.Record); err != nil {
			return err
		}
		if err := validateLinkConnection(e.App, e.Record,
			e.Record.Original().GetString(util.Fields.Link.Connection)); err != nil {
			return err
		}
		resolvePasswordWrite(e.Record, util.Fields.Link.Password)
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
			maskStoredPassword(e.Record, util.Fields.Link.Password)
		}
		return e.Next()
	})
}

// requireApplicationWatermark refuses an application link that would hand its
// documents out unstamped.
func requireApplicationWatermark(rec *core.Record) error {
	if rec.GetString(util.Fields.Link.Purpose) == util.PurposeApplication &&
		!rec.GetBool(util.Fields.Link.Watermark) {
		return util.AsFieldValidationError(util.Fields.Link.Watermark, util.Errors.ApplicationNeedsWatermark)
	}
	return nil
}

// validateLinkConnection keeps a link's tool honest. A link may name one of
// its owner's own connections in the same workspace — the tool whose proposal
// it came from — and only when it is created: attaching an existing link to a
// tool later would hand that tool its status without a proposal behind it.
// Clearing it is allowed; it hides the link from the tool. Without a
// connection there is no tool to hand the link to or to keep a reference for.
func validateLinkConnection(app core.App, rec *core.Record, before string) error {
	id := rec.GetString(util.Fields.Link.Connection)
	if id == "" {
		rec.Set(util.Fields.Link.HandedOver, false)
		rec.Set(util.Fields.Link.Ref, "")
		return nil
	}
	if !rec.IsNew() && id != before {
		return util.AsFieldValidationError(util.Fields.Link.Connection, util.Errors.LinkConnectionForeign)
	}
	conn, err := app.FindRecordById(util.Coll.Connections, id)
	if err != nil || conn == nil ||
		conn.GetString(util.Fields.Connection.User) != rec.GetString(util.Fields.Link.User) ||
		conn.GetString(util.Fields.Connection.Workspace) != rec.GetString(util.Fields.Link.Workspace) {
		return util.AsFieldValidationError(util.Fields.Link.Connection, util.Errors.LinkConnectionForeign)
	}
	// A link goes to a tool only when the owner lets that tool receive links.
	// Checked when it is handed over, not after: taking the permission away
	// later hides the link from the tool without making it unsaveable.
	if rec.GetBool(util.Fields.Link.HandedOver) &&
		(rec.IsNew() || !rec.Original().GetBool(util.Fields.Link.HandedOver)) &&
		!conn.GetBool(util.Fields.Connection.AllowHandOver) {
		return util.AsFieldValidationError(util.Fields.Link.HandedOver, util.Errors.LinkHandOverNotAllowed)
	}
	// A new link cannot join a connection the owner has let lapse.
	if rec.IsNew() && util.ConnectionExpired(conn.GetDateTime(util.Fields.Connection.ExpiresAt).Time()) {
		return util.AsFieldValidationError(util.Fields.Link.Connection, util.Errors.ConnectionExpired)
	}
	return nil
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
