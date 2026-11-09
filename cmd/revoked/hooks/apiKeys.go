package hooks

import (
	"revoked/cmd/revoked/services"
	"revoked/util"
	"time"

	validation "github.com/pocketbase/ozzo-validation/v4"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/hook"
	"github.com/pocketbase/pocketbase/tools/security"
	"github.com/pocketbase/pocketbase/tools/types"
)

// BindApiKeyHooks binds a new key to the creator's active workspace, issues and
// hashes its token (returned once via X-Plain-Token), and validates its scopes:
// what the creator holds, and never the vault.
func BindApiKeyHooks(app core.App) {
	app.OnRecordCreateRequest(util.Coll.ApiKeys).BindFunc(func(e *core.RecordRequestEvent) error {
		if e.Auth == nil {
			return e.RequestEvent.UnauthorizedError(util.Errors.NotAuthenticated.ErrorCode, nil)
		}

		if e.Auth.Collection().Name == util.Coll.Users {
			user, err := e.App.FindRecordById(util.Coll.Users, e.Auth.Id)
			if err != nil {
				return e.RequestEvent.InternalServerError("Failed to retrieve user context", nil)
			}

			if e.Record.GetString(util.Fields.ApiKey.User) == "" {
				e.Record.Set(util.Fields.ApiKey.User, user.Id)
			}

			requestedWS := e.Record.GetString(util.Fields.ApiKey.Workspace)
			activeWS := user.GetString(util.Fields.User.ActiveWorkspace)

			if activeWS == "" {
				return e.RequestEvent.BadRequestError(util.Errors.InvalidActiveWorkspace.ErrorCode, nil)
			}

			if requestedWS == "" {
				e.Record.Set(util.Fields.ApiKey.Workspace, activeWS)
				requestedWS = activeWS
			}

			if requestedWS != activeWS {
				return e.RequestEvent.BadRequestError(util.Errors.ForbiddenWorkspaceAccess.ErrorCode, nil)
			}
		}

		// Any client-supplied token is discarded; only a server-generated one is
		// ever stored, and only its hash.
		plainToken := security.RandomString(48)

		e.Record.Set(util.Fields.ApiKey.Token, util.HashToken(plainToken))

		e.RequestEvent.Response.Header().Set("X-Plain-Token", plainToken)
		e.RequestEvent.Response.Header().Set("Access-Control-Expose-Headers", "X-Plain-Token")

		var raw struct {
			Scopes []string `json:"scopes"`
		}
		if err := e.RequestEvent.BindBody(&raw); err == nil && len(raw.Scopes) > 0 {
			seen := make(map[string]bool)
			for _, s := range raw.Scopes {
				if seen[s] {
					return e.RequestEvent.BadRequestError(util.Errors.DuplicateValues.ErrorCode, nil)
				}
				seen[s] = true
			}
		}

		// The vault is reached through sections, never through record scopes,
		// which the collection rules would honour across the workspace.
		workspace := e.Record.GetString(util.Fields.ApiKey.Workspace)
		rest, access := util.SplitVaultPermissions(e.Record.GetStringSlice(util.Fields.ApiKey.Scopes))
		e.Record.Set(util.Fields.ApiKey.Scopes, rest)
		if err := applyKeyReach(e, workspace, access); err != nil {
			return err
		}

		// Keys are granted by permission, exactly as invites are: the app
		// sends catalogue keys, and this expands them into stored scopes and
		// refuses anything the creator does not hold themselves. Validating the
		// submitted values against AllScopes alone rejected every key the
		// picker can produce.
		if err := normalizePermissionGrant(
			e.App,
			e,
			util.Fields.ApiKey.Scopes,
			e.Record.GetString(util.Fields.ApiKey.Workspace),
		); err != nil {
			return err
		}

		// No new key holds a record scope, whoever asks: its reach is its
		// sections. Keys issued before this rule keep their scopes until they
		// expire or are revoked.
		if vault := util.MembersOnlyScopes(e.Record.GetStringSlice(util.Fields.ApiKey.Scopes)); len(vault) > 0 {
			return validation.Errors{
				util.Fields.ApiKey.Scopes: validation.NewError(
					util.Errors.ApiKeyVaultScope.ErrorCode,
					util.Errors.ApiKeyVaultScope.ErrorText+" Refused: "+vault[0]+".",
				),
			}
		}

		return e.Next()
	})
}

// applyKeyReach sets the vault access and sections a new key reaches. Every
// section must be its creator's own in the key's workspace, and the creator
// must hold the access they hand on.
func applyKeyReach(e *core.RecordRequestEvent, workspace, access string) error {
	f := util.Fields.ApiKey
	refuse := func(appErr util.AppError) error {
		return validation.Errors{f.Sections: validation.NewError(appErr.ErrorCode, appErr.ErrorText)}
	}
	sections := e.Record.GetStringSlice(f.Sections)
	if access == "" {
		e.Record.Set(f.VaultAccess, "")
		e.Record.Set(f.Sections, []string{})
		return nil
	}
	if len(sections) == 0 {
		return validation.Errors{f.Scopes: validation.NewError(
			util.Errors.ApiKeyVaultScope.ErrorCode, util.Errors.ApiKeyVaultScope.ErrorText)}
	}
	if e.Auth == nil || e.Auth.Collection().Name != util.Coll.Users {
		return refuse(util.Errors.PermissionEscalation)
	}
	want := []string{util.ScopeRecordRead}
	if access == util.VaultAccessWrite {
		want = append(want, util.ScopeRecordCreate, util.ScopeRecordUpdate, util.ScopeRecordDelete)
	}
	if !util.HasAllScopes(services.GranterScopes(e.App, e.Auth, workspace, false), want) {
		return refuse(util.Errors.PermissionEscalation)
	}
	for _, id := range sections {
		s, err := e.App.FindRecordById(util.Coll.Sections, id)
		if err != nil || s == nil ||
			s.GetString(util.Fields.Section.Workspace) != workspace ||
			s.GetString(util.Fields.Section.User) != e.Auth.Id ||
			s.GetString(util.Fields.Section.RequestedBy) != "" {
			return refuse(util.Errors.VaultSectionInvalid)
		}
	}
	e.Record.Set(f.VaultAccess, access)
	return nil
}

// BindApiKeyAuthMiddleware authenticates an X-API-Key request by matching the
// token hash against a stored apiKey and exposing it as e.Auth.
//
// It must bind immediately after PocketBase's own auth-token loader: collection
// API rules are evaluated before any OnRecord*Request hook, so authenticating
// later would leave every API-key request looking like a guest.
func BindApiKeyAuthMiddleware(app core.App) {
	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		se.Router.Bind(&hook.Handler[*core.RequestEvent]{
			Id:       "revokedApiKeyAuth",
			Priority: apis.DefaultLoadAuthTokenMiddlewarePriority + 1,
			Func: func(e *core.RequestEvent) error {
				if e.Auth != nil {
					return e.Next()
				}

				token := e.Request.Header.Get("X-API-Key")
				if token == "" {
					return e.Next()
				}

				apiKey, err := app.FindFirstRecordByFilter(
					util.Coll.ApiKeys,
					"token = {:token}",
					map[string]any{"token": util.HashToken(token)},
				)
				// Reject an unusable key here rather than falling through as a
				// guest: the collection rule would then deny it with an opaque
				// 400, making a typo indistinguishable from a permissions problem.
				if err != nil || apiKey == nil {
					return e.UnauthorizedError(util.Errors.InvalidApiKey.ErrorText,
						validation.Errors{
							"apiKey": util.AsValidationError(util.Errors.InvalidApiKey),
						})
				}

				// An expired key is rejected here rather than by a rule, so the
				// caller learns the key aged out instead of seeing a permissions
				// failure.
				if expiresAt := apiKey.GetDateTime(util.Fields.ApiKey.ExpiresAt); !expiresAt.IsZero() &&
					expiresAt.Time().Before(time.Now()) {
					return e.UnauthorizedError(util.Errors.ApiKeyExpired.ErrorText,
						validation.Errors{
							"apiKey": util.AsValidationError(util.Errors.ApiKeyExpired),
						})
				}

				e.Auth = apiKey
				touchApiKeyLastUsed(app, apiKey)

				return e.Next()
			},
		})

		return se.Next()
	})
}

// lastUsedResolution is how stale apiKeys.lastUsedAt is allowed to be.
const lastUsedResolution = time.Minute

// touchApiKeyLastUsed refreshes lastUsedAt at most once per
// [lastUsedResolution] per key: the timestamp is diagnostic, not
// security-relevant, and is not worth a write on every authenticated request.
func touchApiKeyLastUsed(app core.App, apiKey *core.Record) {
	last := apiKey.GetDateTime(util.Fields.ApiKey.LastUsedAt)
	if !last.IsZero() && time.Since(last.Time()) < lastUsedResolution {
		return
	}
	apiKey.Set(util.Fields.ApiKey.LastUsedAt, types.NowDateTime())
	if err := app.Save(apiKey); err != nil {
		app.Logger().Error("Failed to update apiKey lastUsedAt", "error", err)
	}
}
