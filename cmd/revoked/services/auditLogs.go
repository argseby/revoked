package services

import (
	"encoding/json"

	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// AuditEntry describes one completed action for the audit log.
//
// Everything is already resolved: which workspace the action belongs to, who
// acted, and where from. The request hooks derive that from the request they
// are handling; a server-side write states it outright.
type AuditEntry struct {
	Action     string
	Collection string
	RecordId   string
	Workspace  string
	User       string
	ApiKey     string
	Ip         string
	UserAgent  string
	OldData    map[string]any
	NewData    map[string]any
}

// RecordAudit saves an audit row describing a completed action. It never
// returns a failure: an audit row must not undo the operation it describes.
//
// Both snapshots pass through util.RedactAuditData here rather than in the
// callers, so no path can record a snapshot nobody redacted. An audit row
// outlives and outtravels the record it describes, and a secret written into
// one — a vault value, a submitted gate password — would persist in plaintext
// under a collection nobody thinks of as secret storage.
func RecordAudit(app core.App, entry AuditEntry) {
	collection, err := app.FindCollectionByNameOrId(util.Coll.AuditLogs)
	if err != nil {
		app.Logger().Error("Audit log collection missing", "error", err)
		return
	}

	row := core.NewRecord(collection)
	row.Set(util.Fields.AuditLog.Action, entry.Action)
	row.Set(util.Fields.AuditLog.Collection, entry.Collection)
	row.Set(util.Fields.AuditLog.RecordId, entry.RecordId)
	row.Set(util.Fields.AuditLog.Ip, entry.Ip)
	row.Set(util.Fields.AuditLog.UserAgent, entry.UserAgent)
	if entry.User != "" {
		row.Set(util.Fields.AuditLog.User, entry.User)
	}
	if entry.ApiKey != "" {
		row.Set(util.Fields.AuditLog.ApiKey, entry.ApiKey)
	}
	if entry.Workspace != "" {
		row.Set(util.Fields.AuditLog.Workspace, entry.Workspace)
	}

	if old := util.RedactAuditData(entry.Collection, entry.OldData); old != nil {
		encoded, _ := json.Marshal(old)
		row.Set(util.Fields.AuditLog.OldData, string(encoded))
	}
	if next := util.RedactAuditData(entry.Collection, entry.NewData); next != nil {
		encoded, _ := json.Marshal(next)
		row.Set(util.Fields.AuditLog.NewData, string(encoded))
	}

	if err := app.Save(row); err != nil {
		app.Logger().Error("Failed to save audit log", "error", err)
	}
}
