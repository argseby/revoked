// Package services holds domain logic shared by the event hooks and the HTTP
// routes; it must not import either of them, nor touch HTTP requests or
// responses.
package services

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// EmitNotification creates an in-app notification for a link/request owner.
//
// Best-effort by design: a failure is logged and swallowed rather than failing
// the operation that triggered it. It writes via app.Save, deliberately
// bypassing the collection's superuser-only create rule and the request hooks,
// and is the only supported way to create one.
func EmitNotification(app core.App, userId, workspaceId, kind, title, message, refColl, refId string) {
	if userId == "" || workspaceId == "" {
		return
	}
	col, err := app.FindCollectionByNameOrId(util.Coll.Notifications)
	if err != nil {
		return
	}
	rec := core.NewRecord(col)
	rec.Set(util.Fields.Notification.User, userId)
	rec.Set(util.Fields.Notification.Workspace, workspaceId)
	rec.Set(util.Fields.Notification.Type, kind)
	rec.Set(util.Fields.Notification.Title, title)
	rec.Set(util.Fields.Notification.Message, message)
	rec.Set(util.Fields.Notification.RefCollection, refColl)
	rec.Set(util.Fields.Notification.RefId, refId)
	rec.Set(util.Fields.Notification.Read, false)
	if err := app.Save(rec); err != nil {
		app.Logger().Error("Failed to emit notification", "error", err)
	}
}
