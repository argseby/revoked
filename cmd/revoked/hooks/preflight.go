package hooks

import (
	"net/http"
	"revoked/util"
	"strings"

	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/hook"
	"github.com/pocketbase/pocketbase/tools/router"
)

// genericCrudFailures are the reason-free messages PocketBase emits when a
// collection rule denies a write.
var genericCrudFailures = map[string]bool{
	"Failed to create record.": true,
	"Failed to update record.": true,
	"Failed to delete record.": true,
}

// BindAccessPreflight explains authorization failures on the collection CRUD
// endpoints.
//
// PocketBase evaluates a collection's API rule before any record hook runs and
// discards the reason, so no hook can explain a denial; the explanation instead
// comes from the declaration the rule was built from (util.CollectionAccess).
// This is advisory only — the rule remains the enforcement boundary, so a gap
// here is a worse message, never weaker access control.
func BindAccessPreflight(app core.App) {
	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		se.Router.Bind(&hook.Handler[*core.RequestEvent]{
			Id: "revokedAccessPreflight",
			// After the auth loaders so e.Auth is resolved, before the handlers.
			Priority: apis.DefaultLoadAuthTokenMiddlewarePriority + 2,
			Func: func(e *core.RequestEvent) error {
				collection, action, recordId, ok := parseCrudRequest(e)
				if !ok {
					return e.Next()
				}
				spec, declared := util.AccessSpecFor(collection, action)
				if !declared {
					return e.Next()
				}

				if errs := diagnoseAccess(app, e, spec, collection, action, recordId); len(errs) > 0 {
					return router.NewApiError(http.StatusForbidden,
						"Not permitted to "+action+" this record.", errs)
				}

				return normalizeGenericFailure(e.Next(), collection, action)
			},
		})
		return se.Next()
	})
}

// parseCrudRequest matches the collection write endpoints and reports the
// collection, the action, and the target record id for update/delete.
func parseCrudRequest(e *core.RequestEvent) (collection, action, recordId string, ok bool) {
	const prefix = "/api/collections/"
	path := e.Request.URL.Path
	if !strings.HasPrefix(path, prefix) {
		return "", "", "", false
	}
	rest := strings.TrimPrefix(path, prefix)
	parts := strings.Split(strings.Trim(rest, "/"), "/")
	if len(parts) < 2 || parts[1] != "records" {
		return "", "", "", false
	}
	collection = parts[0]
	if len(parts) > 2 {
		recordId = parts[2]
	}

	switch e.Request.Method {
	case http.MethodPost:
		if recordId != "" {
			return "", "", "", false
		}
		action = util.ActionCreate
	case http.MethodPatch:
		if recordId == "" {
			return "", "", "", false
		}
		action = util.ActionUpdate
	case http.MethodDelete:
		if recordId == "" {
			return "", "", "", false
		}
		action = util.ActionDelete
	default:
		return "", "", "", false
	}
	return collection, action, recordId, true
}

// diagnoseAccess builds the subject for a request and runs the spec against it.
func diagnoseAccess(app core.App, e *core.RequestEvent, spec util.AccessSpec, collection, action, recordId string) validation.Errors {
	subject := util.AccessSubject{
		Auth:        e.Auth,
		IsSuperuser: e.HasSuperuserAuth(),
	}

	if action == util.ActionCreate {
		subject.RecordWorkspace = requestedWorkspace(e)
		return spec.Diagnose(app, subject)
	}

	existing, err := app.FindRecordById(collection, recordId)
	if err != nil || existing == nil {
		return nil
	}
	subject.RecordWorkspace = existing.GetString(util.FieldWorkspace)
	subject.RecordUser = existing.GetString(util.FieldUser)
	if collection == util.Coll.Workspaces {
		subject.RecordWorkspace = existing.Id
	}

	// Explaining a denial confirms the record exists, so only a caller already
	// inside the record's workspace gets one; an outsider must fall through to
	// PocketBase's 404, which is what stops ids being probed across tenants.
	if !belongsToWorkspace(app, subject) {
		return nil
	}

	return spec.Diagnose(app, subject)
}

// belongsToWorkspace reports whether the caller is inside the record's
// workspace and may therefore be told why an action was refused.
func belongsToWorkspace(app core.App, subj util.AccessSubject) bool {
	if subj.IsSuperuser {
		return true
	}
	if subj.Auth == nil || subj.RecordWorkspace == "" {
		return false
	}
	switch subj.Auth.Collection().Name {
	case util.Coll.ApiKeys:
		return subj.Auth.GetString(util.Fields.ApiKey.Workspace) == subj.RecordWorkspace
	case util.Coll.Users:
		member, err := app.FindFirstRecordByFilter(
			util.Coll.WorkspaceMembers,
			"workspace = {:w} && user = {:u}",
			map[string]any{"w": subj.RecordWorkspace, "u": subj.Auth.Id},
		)
		return err == nil && member != nil
	}
	return false
}

// requestedWorkspace reads the workspace the payload asks for; empty means the
// create inherits the caller's context, which is no mismatch to report.
func requestedWorkspace(e *core.RequestEvent) string {
	info, err := e.RequestInfo()
	if err != nil {
		return ""
	}
	if v, ok := info.Body[util.FieldWorkspace].(string); ok {
		return v
	}
	return ""
}

// normalizeGenericFailure replaces a bare rule denial with a typed error, so a
// caller always receives a machine-readable code even when the preflight found
// nothing to report.
func normalizeGenericFailure(err error, collection, action string) error {
	if err == nil {
		return nil
	}
	apiErr, isApi := err.(*router.ApiError)
	if !isApi || apiErr.Status != http.StatusBadRequest || len(apiErr.Data) > 0 {
		return err
	}
	if !genericCrudFailures[apiErr.Message] {
		return err
	}

	return router.NewApiError(http.StatusForbidden,
		"Not permitted to "+action+" this record.",
		validation.Errors{
			"access": validation.NewError(
				util.Errors.AccessDenied.ErrorCode,
				"The "+collection+" access rule rejected this request. Check the authenticated identity, its workspace and its scopes.",
			),
		})
}
