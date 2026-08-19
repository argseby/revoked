package hooks

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// scopeForCollection returns the create-scope an API key needs for a
// collection, or "" when none is required.
func scopeForCollection(name string) string {
	switch name {
	case util.Coll.Records:
		return util.ScopeRecordCreate
	case util.Coll.Sections:
		return util.ScopeSectionCreate
	case util.Coll.Links:
		return util.ScopeLinkCreate
	case util.Coll.Templates:
		return util.ScopeTemplateCreate
	case util.Coll.Identities:
		return util.ScopeIdentityCreate
	case util.Coll.Requests:
		return util.ScopeRequestCreate
	}
	return ""
}

// readScopeForCollection returns the read-scope an API key needs for a
// collection, or "" when none is required.
func readScopeForCollection(name string) string {
	switch name {
	case util.Coll.Records:
		return util.ScopeRecordRead
	case util.Coll.Sections:
		return util.ScopeSectionRead
	case util.Coll.Links:
		return util.ScopeLinkRead
	case util.Coll.Templates:
		return util.ScopeTemplateRead
	case util.Coll.Identities:
		return util.ScopeIdentityRead
	case util.Coll.Requests:
		return util.ScopeRequestRead
	case util.Coll.Notifications:
		return util.ScopeNotificationRead
	}
	return ""
}

// identityBearers are the collections carrying an `identity` relation whose
// ownership must be proven — see [validateIdentityOwnership].
var identityBearers = []string{util.Coll.Links, util.Coll.Requests}

// validateIdentityOwnership rejects a link/request whose `identity` relation
// points at another workspace's identity.
//
// PocketBase relation validation only checks that the id EXISTS, and identity
// ids are public. Without this check anyone could stamp a victim's verified
// identity onto their own request and still pass the responder's verification,
// turning the anti-phishing guarantee into a phishing tool.
func validateIdentityOwnership(app core.App, rec *core.Record) *util.AppError {
	identityId := rec.GetString(util.FieldIdentity)
	if identityId == "" {
		return nil
	}
	identity, err := app.FindRecordById(util.Coll.Identities, identityId)
	if err != nil || identity == nil {
		return &util.Errors.IdentityNotFound
	}
	if identity.GetString(util.FieldWorkspace) != rec.GetString(util.FieldWorkspace) {
		return &util.Errors.IdentityNotOwned
	}
	return nil
}

// RegisterTenancyHooks wires authentication, workspace binding, API-key scope
// checks and identity ownership onto the business collections.
func RegisterTenancyHooks(app core.App) {
	collections := []string{
		util.Coll.Records,
		util.Coll.Sections,
		util.Coll.Links,
		util.Coll.Templates,
		util.Coll.Identities,
		util.Coll.Requests,
	}

	// Identity ownership is checked on update too: a record can be created
	// without an identity and repointed later.
	for _, collName := range identityBearers {
		coll := collName
		app.OnRecordUpdateRequest(coll).BindFunc(func(e *core.RecordRequestEvent) error {
			if e.RequestEvent.HasSuperuserAuth() {
				return e.Next()
			}
			if appErr := validateIdentityOwnership(app, e.Record); appErr != nil {
				return e.RequestEvent.ForbiddenError(appErr.ErrorText, nil)
			}
			return e.Next()
		})
	}

	for _, collName := range collections {
		coll := collName

		app.OnRecordCreateRequest(coll).BindFunc(func(e *core.RecordRequestEvent) error {
			if e.Auth == nil {
				return e.RequestEvent.UnauthorizedError("Authentication required", nil)
			}

			var userId string
			var workspaceId string

			if e.Auth.Collection().Name == util.Coll.Users {
				userId = e.Auth.Id
				workspaceId = e.Auth.GetString(util.Fields.User.ActiveWorkspace)
				if workspaceId == "" {
					return e.RequestEvent.BadRequestError("No active workspace selected", nil)
				}
			} else if e.Auth.Collection().Name == util.Coll.ApiKeys {
				userId = e.Auth.GetString(util.Fields.ApiKey.User)
				workspaceId = e.Auth.GetString(util.Fields.ApiKey.Workspace)

				if requiredScope := scopeForCollection(coll); requiredScope != "" {
					if !hasScope(e.Auth, requiredScope) {
						return e.RequestEvent.BadRequestError("API Key lacks required scope: "+requiredScope, nil)
					}
				}
			}

			requestedWS := e.Record.GetString(util.FieldWorkspace)
			if requestedWS != "" && requestedWS != workspaceId {
				return e.RequestEvent.BadRequestError("Workspace mismatch", nil)
			}

			e.Record.Set(util.FieldUser, userId)
			e.Record.Set(util.FieldWorkspace, workspaceId)

			// Must run after the workspace is bound above, so the check uses the
			// workspace the record is saved in, not what the client claimed.
			if appErr := validateIdentityOwnership(app, e.Record); appErr != nil {
				return e.RequestEvent.ForbiddenError(appErr.ErrorText, nil)
			}

			return e.Next()
		})

		bindReadScopeHook(app, coll)
	}

	// Notifications take the read-scope check but NOT the create hook above:
	// they are written server-side via services.EmitNotification, so binding it
	// would only risk rewriting user/workspace on an admin-issued notification.
	bindReadScopeHook(app, util.Coll.Notifications)
}

// bindReadScopeHook enforces the API-key read scope on a collection's list
// endpoint; row-level rules cover ownership but cannot express a key's scopes.
func bindReadScopeHook(app core.App, coll string) {
	app.OnRecordsListRequest(coll).BindFunc(func(e *core.RecordsListRequestEvent) error {
		if e.Auth == nil {
			return e.Next()
		}
		if e.Auth.Collection().Name == util.Coll.ApiKeys {
			if requiredScope := readScopeForCollection(coll); requiredScope != "" {
				if !hasScope(e.Auth, requiredScope) {
					return e.RequestEvent.ForbiddenError("API Key lacks required scope: "+requiredScope, nil)
				}
			}
		}
		return e.Next()
	})
}

// hasScope reports whether the API-key record carries the scope — an exact
// match, unlike the rule layer's `~` (contains) test on the multi-select column.
func hasScope(apiKey *core.Record, scope string) bool {
	for _, s := range apiKey.GetStringSlice(util.Fields.ApiKey.Scopes) {
		if s == scope {
			return true
		}
	}
	return false
}
