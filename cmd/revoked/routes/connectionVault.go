package routes

import (
	"net/http"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// vaultReadLimiter bounds what one connection reads per minute, so a tool
// gone wrong cannot drain the vault faster than its owner notices.
var vaultReadLimiter = util.NewRateLimiter(util.LimitFromEnv("RATELIMIT_CONNECTION_VAULT_READS", 120), time.Minute)

// ConnectionVaultRoute lets a connected tool read its owner's vault, when the
// owner allowed it:
//
//	GET /api/connection/vault        the owner's records: id, key, label, type
//	GET /api/connection/vault/{id}   one record with its current value
//
// Only the owner's own vault entries: not what others sent them, and never
// an encrypted record, whose value this server cannot read. Every value read
// is written to the audit log by key, so the owner can see what left.
func ConnectionVaultRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/connection/vault", func(re *core.RequestEvent) error {
			conn, ok := vaultConnection(app, re)
			if !ok {
				return nil
			}
			rows, err := app.FindRecordsByFilter(util.Coll.Records,
				"workspace = {:ws} && user = {:user} && requestedBy = ''", "key", 1000, 0,
				dbx.Params{"ws": conn.GetString(util.Fields.Connection.Workspace),
					"user": conn.GetString(util.Fields.Connection.User)})
			if err != nil {
				return re.InternalServerError("Failed to list the vault", err)
			}
			out := make([]map[string]any, 0, len(rows))
			for _, rec := range rows {
				if services.IsSealedThroughAlias(app, rec) {
					continue
				}
				out = append(out, vaultRecordView(rec))
			}
			auditConnection(app, re, conn, auditToolListedVault, map[string]any{"count": len(out)})
			return re.JSON(http.StatusOK, map[string]any{"records": out})
		})

		e.Router.GET("/api/connection/vault/{id}", func(re *core.RequestEvent) error {
			conn, ok := vaultConnection(app, re)
			if !ok {
				return nil
			}
			rec, err := app.FindRecordById(util.Coll.Records, re.Request.PathValue("id"))
			if err != nil || rec == nil ||
				rec.GetString(util.Fields.Record.Workspace) != conn.GetString(util.Fields.Connection.Workspace) ||
				rec.GetString(util.Fields.Record.User) != conn.GetString(util.Fields.Connection.User) ||
				rec.GetString(util.Fields.Record.RequestedBy) != "" {
				return appErrorResponse(re, http.StatusNotFound, &util.Errors.RecordNotFound)
			}
			// An encrypted record looks like a missing one: the tool learns
			// nothing it could not read.
			if services.IsSealedThroughAlias(app, rec) {
				return appErrorResponse(re, http.StatusNotFound, &util.Errors.RecordNotFound)
			}
			source := rec
			if parentID := rec.GetString(util.Fields.Record.AliasOf); parentID != "" {
				parent, err := app.FindRecordById(util.Coll.Records, parentID)
				if err != nil || parent == nil {
					return appErrorResponse(re, http.StatusNotFound, &util.Errors.RecordNotFound)
				}
				source = parent
			}
			view := vaultRecordView(rec)
			if source.GetString(util.Fields.Record.Type) == util.TypeFile {
				view["filename"] = source.GetString(util.Fields.Record.Filename)
				view["mime"] = source.GetString(util.Fields.Record.Mime)
				view["size"] = source.GetInt(util.Fields.Record.Size)
			} else {
				view["value"] = source.GetString(util.Fields.Record.Value)
			}
			auditConnection(app, re, conn, auditToolReadRecord, map[string]any{
				"record": rec.Id,
				"key":    rec.GetString(util.Fields.Record.Key),
			})
			re.Response.Header().Set("Cache-Control", "no-store")
			return re.JSON(http.StatusOK, view)
		})
		return e.Next()
	})
}

// vaultConnection resolves a token that may read the vault, or writes the
// refusal and reports false.
func vaultConnection(app core.App, re *core.RequestEvent) (*core.Record, bool) {
	token, conn, _, ok := connectionTokenFromRequest(app, re)
	if !ok {
		return nil, false
	}
	if !conn.GetBool(util.Fields.Connection.AllowVaultRead) {
		return nil, denyGate(re, http.StatusForbidden, &util.Errors.ConnectionVaultNotAllowed)
	}
	if !vaultReadable(conn, token) {
		return nil, denyGate(re, http.StatusForbidden, &util.Errors.ConnectionVaultPolled)
	}
	if !allowRequest(re, vaultReadLimiter, conn.Id) {
		_ = rateLimitedResponse(re)
		return nil, false
	}
	return conn, true
}

// vaultReadable reports whether this token may read the vault. A token
// collected by polling never may: anyone can send the owner a connect link and
// read them its check code, but only the owner's own machine receives an
// answer sent back to the tool's address.
func vaultReadable(conn, token *core.Record) bool {
	return conn.GetBool(util.Fields.Connection.AllowVaultRead) &&
		token != nil && !token.GetBool(util.Fields.ConnectionToken.Poll)
}

func vaultRecordView(rec *core.Record) map[string]any {
	return map[string]any{
		"id":      rec.Id,
		"key":     rec.GetString(util.Fields.Record.Key),
		"label":   rec.GetString(util.Fields.Record.Label),
		"type":    rec.GetString(util.Fields.Record.Type),
		"format":  rec.GetString(util.Fields.Record.Format),
		"updated": rec.GetString(util.Fields.Record.Updated),
	}
}
