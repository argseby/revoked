package hooks

import (
	"revoked/cmd/revoked/services"
	"revoked/util"

	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/pocketbase/pocketbase/core"
)

// The token alone guards workspace access, so it gets a share slug's entropy budget.
const inviteTokenBytes = 24

// BindInviteHooks mints the invite token and refuses grants that exceed the
// granter's own access.
func BindInviteHooks(app core.App) {
	app.OnRecordCreateRequest(util.Coll.Invites).BindFunc(func(e *core.RecordRequestEvent) error {
		if e.Auth == nil {
			return e.RequestEvent.UnauthorizedError(util.Errors.NotAuthenticated.ErrorText, nil)
		}

		workspaceId := e.Record.GetString(util.Fields.Invite.Workspace)
		if workspaceId == "" {
			if e.Auth.Collection().Name == util.Coll.Users {
				workspaceId = e.Auth.GetString(util.Fields.User.ActiveWorkspace)
			} else {
				workspaceId = e.Auth.GetString(util.Fields.ApiKey.Workspace)
			}
			e.Record.Set(util.Fields.Invite.Workspace, workspaceId)
		}

		if ws, err := app.FindRecordById(util.Coll.Workspaces, workspaceId); err != nil || ws == nil {
			return validation.Errors{
				util.Fields.Invite.Workspace: util.AsValidationError(util.Errors.WorkspaceNotFound),
			}
		}

		if err := bindInviteGrant(app, e, workspaceId); err != nil {
			return err
		}

		token, err := util.GenerateToken(inviteTokenBytes)
		if err != nil {
			return e.RequestEvent.InternalServerError("Failed to generate invite token", nil)
		}
		e.Record.Set(util.Fields.Invite.TokenHash, util.HashToken(token))
		if e.Record.GetString(util.Fields.Invite.Status) == "" {
			e.Record.Set(util.Fields.Invite.Status, util.StatusActive)
		}
		if e.Auth.Collection().Name == util.Coll.Users {
			e.Record.Set(util.Fields.Invite.InvitedBy, e.Auth.Id)
		}

		// The plaintext exists only in this response; only its hash is stored.
		e.RequestEvent.Response.Header().Set("X-Invite-Token", token)
		e.RequestEvent.Response.Header().Set("Access-Control-Expose-Headers", "X-Invite-Token")

		return e.Next()
	})

	app.OnRecordUpdateRequest(util.Coll.Invites).BindFunc(func(e *core.RecordRequestEvent) error {
		if e.RequestEvent.HasSuperuserAuth() {
			return e.Next()
		}
		if err := bindInviteGrant(app, e, e.Record.GetString(util.Fields.Invite.Workspace)); err != nil {
			return err
		}
		return e.Next()
	})

	// The hash is a bearer credential: never let it back out, even to an admin.
	app.OnRecordEnrich(util.Coll.Invites).BindFunc(func(e *core.RecordEnrichEvent) error {
		if e.Record != nil {
			e.Record.Set(util.Fields.Invite.TokenHash, "")
		}
		return e.Next()
	})
}

func bindInviteGrant(app core.App, e *core.RecordRequestEvent, workspaceId string) error {
	if len(e.Record.GetStringSlice(util.Fields.Invite.Permissions)) == 0 {
		return validation.Errors{
			util.Fields.Invite.Permissions: validation.NewError(
				util.Errors.ValidationFieldRequired.ErrorCode,
				"An invite must grant at least one permission.",
			),
		}
	}
	return normalizePermissionGrant(app, e, util.Fields.Invite.Permissions, workspaceId)
}

// normalizePermissionGrant expands permission keys or raw scopes into stored
// scopes, refusing any the granter does not hold.
func normalizePermissionGrant(app core.App, e *core.RecordRequestEvent, field, workspaceId string) error {
	requested := e.Record.GetStringSlice(field)

	scopes, unknown := util.ExpandPermissions(requested)
	if len(unknown) > 0 {
		scopes = append(scopes, util.KnownScopes(unknown)...)
		if rejected := util.UnknownScopes(unknown); len(rejected) > 0 {
			return validation.Errors{
				field: validation.NewError(
					util.Errors.InvalidScope.ErrorCode,
					"Unknown permission: "+rejected[0]+".",
				),
			}
		}
	}

	if !e.RequestEvent.HasSuperuserAuth() {
		granter := services.GranterScopes(app, e.Auth, workspaceId, false)
		if missing := util.MissingScopes(granter, scopes); len(missing) > 0 {
			return validation.Errors{
				field: validation.NewError(
					util.Errors.PermissionEscalation.ErrorCode,
					"You cannot grant access you do not hold yourself: "+missing[0]+".",
				),
			}
		}
	}

	e.Record.Set(field, scopes)
	return nil
}
