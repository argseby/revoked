package hooks

import (
	"encoding/json"
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

		return logAuditAction(app, e, "create", nil, e.Record.PublicExport())
	})

	app.OnRecordUpdateRequest().BindFunc(func(e *core.RecordRequestEvent) error {
		if e.Collection.Name == util.Coll.AuditLogs {
			return e.Next()
		}

		oldData := e.Record.PublicExport()

		if err := e.Next(); err != nil {
			return err
		}

		return logAuditAction(app, e, "update", oldData, e.Record.PublicExport())
	})

	app.OnRecordDeleteRequest().BindFunc(func(e *core.RecordRequestEvent) error {
		if e.Collection.Name == util.Coll.AuditLogs {
			return e.Next()
		}

		oldData := e.Record.PublicExport()

		if err := e.Next(); err != nil {
			return err
		}

		return logAuditAction(app, e, "delete", oldData, nil)
	})
}

// logAuditAction saves an auditLog entry describing a completed action.
//
// Its callers have already advanced the chain with e.Next(), so it must never
// call e.Next() again. Audit failures never block the operation they describe.
func logAuditAction(app core.App, e *core.RecordRequestEvent, action string, oldData any, newData any) error {
	auditCollection, err := app.FindCollectionByNameOrId(util.Coll.AuditLogs)
	if err != nil {
		app.Logger().Error("Audit log collection missing", "error", err)
		return nil
	}

	auditRecord := core.NewRecord(auditCollection)

	if e.Auth != nil {
		if e.Auth.Collection().Name == util.Coll.Users {
			auditRecord.Set(util.Fields.AuditLog.User, e.Auth.Id)
		} else if e.Auth.Collection().Name == util.Coll.ApiKeys {
			auditRecord.Set(util.Fields.AuditLog.User, e.Auth.GetString(util.Fields.ApiKey.User))
			auditRecord.Set(util.Fields.AuditLog.ApiKey, e.Auth.Id)
		}
	}

	auditRecord.Set(util.Fields.AuditLog.Action, action)
	auditRecord.Set(util.Fields.AuditLog.Collection, e.Collection.Name)
	auditRecord.Set(util.Fields.AuditLog.RecordId, e.Record.Id)

	if oldData != nil {
		oldDataJSON, _ := json.Marshal(oldData)
		auditRecord.Set(util.Fields.AuditLog.OldData, string(oldDataJSON))
	}

	if newData != nil {
		newDataJSON, _ := json.Marshal(newData)
		auditRecord.Set(util.Fields.AuditLog.NewData, string(newDataJSON))
	}

	auditRecord.Set(util.Fields.AuditLog.Ip, e.Request.RemoteAddr)
	auditRecord.Set(util.Fields.AuditLog.UserAgent, e.Request.UserAgent())

	workspaceId := ""

	if ws := e.Record.GetString("workspace"); ws != "" {
		workspaceId = ws
	}

	if workspaceId == "" && e.Collection.Name == util.Coll.Workspaces {
		workspaceId = e.Record.Id
	}

	if workspaceId == "" && e.Collection.Name == util.Coll.WorkspaceMembers {
		workspaceId = e.Record.GetString(util.Fields.WorkspaceMember.Workspace)
	}

	if workspaceId == "" && e.Auth != nil {
		workspaceId = e.Auth.GetString(util.Fields.User.ActiveWorkspace)
	}

	if workspaceId != "" {
		auditRecord.Set(util.Fields.AuditLog.Workspace, workspaceId)
	}

	if err := app.Save(auditRecord); err != nil {
		app.Logger().Error("Failed to save audit log", "error", err)
	}

	return nil
}
