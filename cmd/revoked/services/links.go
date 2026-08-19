package services

import (
	"errors"
	"revoked/util"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// ErrLinkViewCapReached is returned by ClaimLinkView when the link's maxViews
// cap was already consumed, so the caller must withhold the data.
var ErrLinkViewCapReached = errors.New("link view cap reached")

// RefreshLinkStatus settles a link's lifecycle state, mutating it in place on
// expiry or view-cap exhaustion, and returns a non-nil AppError for every state
// that must reject the request.
func RefreshLinkStatus(app core.App, link *core.Record) *util.AppError {
	status := link.GetString(util.Fields.Link.Status)

	if status == util.StatusRevoked {
		return &util.Errors.LinkRevoked
	}
	if status == util.StatusExpired {
		return &util.Errors.LinkExpired
	}

	if expiresAt := link.GetDateTime(util.Fields.Link.ExpiresAt); !expiresAt.IsZero() {
		if expiresAt.Time().Before(time.Now()) {
			link.Set(util.Fields.Link.Status, util.StatusExpired)
			// Notify only once the transition is persisted; a failed save would
			// re-notify on every subsequent request.
			if err := app.Save(link); err != nil {
				app.Logger().Error("Failed to persist link expiry", "error", err, "link", link.Id)
			} else {
				EmitNotification(app, link.GetString(util.Fields.Link.User),
					link.GetString(util.Fields.Link.Workspace),
					util.NotificationLinkExpired,
					"Link expired",
					"Link "+link.GetString(util.Fields.Link.Slug)+" has expired.",
					util.Coll.Links, link.Id)
			}
			return &util.Errors.LinkExpired
		}
	}

	// A concurrent reader may have taken the last view since this record was read.
	if mv := link.GetInt(util.Fields.Link.MaxViews); mv > 0 {
		if link.GetInt(util.Fields.Link.ViewCount) >= mv {
			link.Set(util.Fields.Link.Status, util.StatusRevoked)
			if err := app.Save(link); err != nil {
				app.Logger().Error("Failed to persist link revocation", "error", err, "link", link.Id)
			}
			return &util.Errors.LinkMaxViewsReached
		}
	}

	if status == util.StatusPaused {
		return &util.Errors.LinkPaused
	}
	if status != util.StatusActive {
		return &util.Errors.LinkRevoked
	}

	return nil
}

// ClaimLinkView atomically consumes one view against the link's cap and reports
// the new count plus whether this view exhausted it.
//
// The check and the increment MUST stay one statement: with a read-modify-write,
// concurrent readers all observe the same pre-increment count, all pass the
// maxViews check, and a maxViews=1 secret could be read N times in parallel.
// Here the WHERE clause is the check, and zero rows affected means the cap is
// gone. maxViews and viewCount are COALESCEd because both are NULL on links
// created without a cap, and NULL comparisons match no rows.
func ClaimLinkView(app core.App, link *core.Record) (views int, revokedByLimit bool, err error) {
	res, err := app.DB().NewQuery(`
		UPDATE {{links}}
		SET viewCount = COALESCE(viewCount, 0) + 1
		WHERE id = {:id}
		  AND (COALESCE(maxViews, 0) = 0 OR COALESCE(viewCount, 0) < maxViews)
	`).Bind(dbx.Params{"id": link.Id}).Execute()
	if err != nil {
		app.Logger().Error("Failed to claim link view", "error", err, "link", link.Id)
		return 0, false, err
	}
	affected, err := res.RowsAffected()
	if err != nil || affected == 0 {
		return 0, false, ErrLinkViewCapReached
	}

	views = link.GetInt(util.Fields.Link.ViewCount) + 1
	maxViews := link.GetInt(util.Fields.Link.MaxViews)
	link.Set(util.Fields.Link.ViewCount, views)

	if maxViews > 0 && views >= maxViews {
		link.Set(util.Fields.Link.Status, util.StatusRevoked)
		revokedByLimit = true
		// Persist only the status: re-saving the stale in-memory record would
		// roll back a concurrent increment.
		if _, err := app.DB().NewQuery(`UPDATE {{links}} SET status = {:status} WHERE id = {:id}`).
			Bind(dbx.Params{"status": util.StatusRevoked, "id": link.Id}).Execute(); err != nil {
			app.Logger().Error("Failed to auto-revoke link at max views", "error", err, "link", link.Id)
		}
	}
	return views, revokedByLimit, nil
}

// RefreshRequestStatus is the requests-collection counterpart of
// [RefreshLinkStatus], settling expiry and the max-responses cap.
func RefreshRequestStatus(app core.App, req *core.Record) *util.AppError {
	status := req.GetString(util.Fields.Request.Status)
	if status == util.StatusRevoked {
		return &util.Errors.RequestRevoked
	}
	if status == util.StatusExpired {
		return &util.Errors.RequestExpired
	}
	if status == util.StatusCompleted {
		return &util.Errors.RequestCompleted
	}

	if expiresAt := req.GetDateTime(util.Fields.Request.ExpiresAt); !expiresAt.IsZero() {
		if expiresAt.Time().Before(time.Now()) {
			req.Set(util.Fields.Request.Status, util.StatusExpired)
			if err := app.Save(req); err != nil {
				app.Logger().Error("Failed to persist request expiry", "error", err, "request", req.Id)
			} else {
				EmitNotification(app, req.GetString(util.Fields.Request.User),
					req.GetString(util.Fields.Request.Workspace),
					util.NotificationRequestExpired,
					"Request expired",
					"Request "+req.GetString(util.Fields.Request.Slug)+" has expired.",
					util.Coll.Requests, req.Id)
			}
			return &util.Errors.RequestExpired
		}
	}

	if mr := req.GetInt(util.Fields.Request.MaxResponses); mr > 0 {
		if req.GetInt(util.Fields.Request.ResponseCount) >= mr {
			req.Set(util.Fields.Request.Status, util.StatusCompleted)
			if err := app.Save(req); err != nil {
				app.Logger().Error("Failed to persist request completion", "error", err, "request", req.Id)
			}
			return &util.Errors.RequestCompleted
		}
	}

	if status == util.StatusPaused {
		return &util.Errors.RequestPaused
	}
	if status != util.StatusActive {
		return &util.Errors.RequestRevoked
	}
	return nil
}
