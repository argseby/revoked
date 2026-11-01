package hooks

import (
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// BindAuditLogHooks records an audit entry after every create, update and
// delete request on a non-auditLog collection.
func BindAuditLogHooks(app core.App) {
	app.OnRecordCreateRequest().BindFunc(func(e *core.RecordRequestEvent) error {
		if e.Collection.Name == util.Coll.AuditLogs {
			return e.Next()
		}

		if err := e.Next(); err != nil {
			return err
		}

		logAuditAction(app, e, util.AuditActionCreate, nil, e.Record.PublicExport())
		return nil
	})

	app.OnRecordUpdateRequest().BindFunc(func(e *core.RecordRequestEvent) error {
		if e.Collection.Name == util.Coll.AuditLogs {
			return e.Next()
		}

		oldData := e.Record.PublicExport()

		if err := e.Next(); err != nil {
			return err
		}

		logAuditAction(app, e, util.AuditActionUpdate, oldData, e.Record.PublicExport())
		return nil
	})

	app.OnRecordDeleteRequest().BindFunc(func(e *core.RecordRequestEvent) error {
		if e.Collection.Name == util.Coll.AuditLogs {
			return e.Next()
		}

		oldData := e.Record.PublicExport()

		if err := e.Next(); err != nil {
			return err
		}

		logAuditAction(app, e, util.AuditActionDelete, oldData, nil)
		return nil
	})
}

// logAuditAction records a completed request action.
//
// Its callers have already advanced the chain with e.Next(), so it must never
// call e.Next() again. Writing the row belongs to services.RecordAudit, which
// also redacts; what is left here is reading the actor, the address and the
// workspace out of the request. It reports nothing, because an audit row must
// not undo the operation it describes.
func logAuditAction(app core.App, e *core.RecordRequestEvent, action string, oldData map[string]any, newData map[string]any) {
	entry := services.AuditEntry{
		Action:     action,
		Collection: e.Collection.Name,
		RecordId:   e.Record.Id,
		Workspace:  auditWorkspace(e, action),
		Ip:         e.Request.RemoteAddr,
		UserAgent:  e.Request.UserAgent(),
		OldData:    oldData,
		NewData:    newData,
	}

	if e.Auth != nil {
		if e.Auth.Collection().Name == util.Coll.Users {
			entry.User = e.Auth.Id
		} else if e.Auth.Collection().Name == util.Coll.ApiKeys {
			entry.User = e.Auth.GetString(util.Fields.ApiKey.User)
			entry.ApiKey = e.Auth.Id
		}
	}

	services.RecordAudit(app, entry)
}

// auditWorkspace settles which workspace an action belongs to: the record's
// own, the collections that are or name one, and finally the actor's.
func auditWorkspace(e *core.RecordRequestEvent, action string) string {
	// A workspace's own deletion cannot point at it: the row is gone by now and
	// a relation to a missing record fails validation, which the save only
	// logs. Without this the one action that ends a workspace is the one action
	// never recorded — and the actor's activeWorkspace still names it, so the
	// fallback below would reintroduce it. recordId already identifies it.
	if action == util.AuditActionDelete && e.Collection.Name == util.Coll.Workspaces {
		return ""
	}
	if ws := e.Record.GetString(util.FieldWorkspace); ws != "" {
		return ws
	}
	if e.Collection.Name == util.Coll.Workspaces {
		return e.Record.Id
	}
	if e.Collection.Name == util.Coll.WorkspaceMembers {
		return e.Record.GetString(util.Fields.WorkspaceMember.Workspace)
	}
	if e.Auth != nil {
		return e.Auth.GetString(util.Fields.User.ActiveWorkspace)
	}
	return ""
}
