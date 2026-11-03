package hooks

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// connectedFields names, per collection, the fields that tie a row to the
// connected tool whose proposal it came from. Workspace is empty for a
// collection that belongs to a person rather than a workspace.
type connectedFields struct {
	Connection, Ref, ProposedBy, User, Workspace string
}

var connectedCollections = map[string]connectedFields{
	util.Coll.Requests: {
		Connection: util.Fields.Request.Connection, Ref: util.Fields.Request.Ref,
		ProposedBy: util.Fields.Request.ProposedBy,
		User:       util.Fields.Request.User, Workspace: util.Fields.Request.Workspace,
	},
	util.Coll.Attestations: {
		Connection: util.Fields.Attestation.Connection, Ref: util.Fields.Attestation.Ref,
		ProposedBy: util.Fields.Attestation.ProposedBy,
		User:       util.Fields.Attestation.User, Workspace: util.Fields.Attestation.Workspace,
	},
	util.Coll.AttestationChecks: {
		Connection: util.Fields.AttestationCheck.Connection, Ref: util.Fields.AttestationCheck.Ref,
		ProposedBy: util.Fields.AttestationCheck.ProposedBy,
		User:       util.Fields.AttestationCheck.User,
	},
}

// BindConnectedHooks keeps the tool behind a request, attestation or check
// honest, as validateLinkConnection does for links: model-level, so a row
// saved by a route is held to the same rule as one written through the API.
func BindConnectedHooks(app core.App) {
	for coll, f := range connectedCollections {
		app.OnRecordCreate(coll).BindFunc(func(e *core.RecordEvent) error {
			if err := validateConnected(e.App, e.Record, f, ""); err != nil {
				return err
			}
			e.Record.Set(f.ProposedBy, connectionOrigin(e.App, e.Record.GetString(f.Connection)))
			return e.Next()
		})
		app.OnRecordUpdate(coll).BindFunc(func(e *core.RecordEvent) error {
			if err := validateConnected(e.App, e.Record, f, e.Record.Original().GetString(f.Connection)); err != nil {
				return err
			}
			e.Record.Set(f.ProposedBy, e.Record.Original().GetString(f.ProposedBy))
			return e.Next()
		})
	}
}

// validateConnected lets a row name one of its owner's own connections, only
// when it is created: attaching an existing row later would show a tool
// something it never proposed. Clearing it is allowed and hides the row from
// the tool.
func validateConnected(app core.App, rec *core.Record, f connectedFields, before string) error {
	id := rec.GetString(f.Connection)
	if id == "" {
		rec.Set(f.Ref, "")
		return nil
	}
	if !rec.IsNew() && id != before {
		return util.AsFieldValidationError(f.Connection, util.Errors.ConnectionForeign)
	}
	if !rec.IsNew() {
		return nil
	}
	conn, err := app.FindRecordById(util.Coll.Connections, id)
	if err != nil || conn == nil ||
		conn.GetString(util.Fields.Connection.User) != rec.GetString(f.User) ||
		(f.Workspace != "" && conn.GetString(util.Fields.Connection.Workspace) != rec.GetString(f.Workspace)) {
		return util.AsFieldValidationError(f.Connection, util.Errors.ConnectionForeign)
	}
	if util.ConnectionExpired(conn.GetDateTime(util.Fields.Connection.ExpiresAt).Time()) {
		return util.AsFieldValidationError(f.Connection, util.Errors.ConnectionExpired)
	}
	if conn.GetBool(util.Fields.Connection.Paused) {
		return util.AsFieldValidationError(f.Connection, util.Errors.ConnectionPaused)
	}
	return nil
}

func connectionOrigin(app core.App, id string) string {
	if id == "" {
		return ""
	}
	conn, err := app.FindRecordById(util.Coll.Connections, id)
	if err != nil || conn == nil {
		return ""
	}
	return conn.GetString(util.Fields.Connection.ClientId)
}
