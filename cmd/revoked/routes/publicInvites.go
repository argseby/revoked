package routes

import (
	"net/http"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"strings"

	"github.com/pocketbase/pocketbase/core"
)

// PublicInvitesRoute exposes probing and accepting a workspace invite by token.
// The token is the capability — there is no listing endpoint — and the probe
// deliberately shows the workspace and exact permissions before anyone accepts.
func PublicInvitesRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/public/invites/{token}", func(re *core.RequestEvent) error {
			if !allowRequest(re, probeLimiter, "") {
				return rateLimitedResponse(re)
			}
			invite, appErr := findLiveInvite(app, re.Request.PathValue("token"))
			if appErr != nil {
				return inviteErrorResponse(re, appErr)
			}
			return re.JSON(http.StatusOK, inviteProbe(app, invite))
		})

		e.Router.POST("/api/public/invites/{token}", func(re *core.RequestEvent) error {
			if !allowRequest(re, gatePasswordLimiter, "invite") {
				return rateLimitedResponse(re)
			}
			if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}

			invite, appErr := findLiveInvite(app, re.Request.PathValue("token"))
			if appErr != nil {
				return inviteErrorResponse(re, appErr)
			}

			// An email-bound invite is not transferable by forwarding the token.
			if want := invite.GetString(util.Fields.Invite.Email); want != "" &&
				!strings.EqualFold(want, re.Auth.GetString(util.Fields.User.Email)) {
				return appErrorResponse(re, http.StatusForbidden, &util.Errors.InviteWrongAccount)
			}

			workspaceId := invite.GetString(util.Fields.Invite.Workspace)
			if _, already := util.WorkspaceMemberOf(app, workspaceId, re.Auth.Id); already {
				return appErrorResponse(re, http.StatusConflict, &util.Errors.AlreadyWorkspaceMember)
			}

			if err := services.ClaimInviteUse(app, invite); err != nil {
				return appErrorResponse(re, http.StatusGone, &util.Errors.InviteExhausted)
			}

			members, err := app.FindCollectionByNameOrId(util.Coll.WorkspaceMembers)
			if err != nil {
				return re.InternalServerError("Membership collection missing", nil)
			}
			member := core.NewRecord(members)
			member.Set(util.Fields.WorkspaceMember.User, re.Auth.Id)
			member.Set(util.Fields.WorkspaceMember.Workspace, workspaceId)
			member.Set(util.Fields.WorkspaceMember.Permissions, services.InviteGrantedScopes(invite))
			role := invite.GetString(util.Fields.Invite.Role)
			if role == "" {
				role = util.RoleMember
			}
			member.Set(util.Fields.WorkspaceMember.Role, role)
			if err := app.Save(member); err != nil {
				app.Logger().Error("Failed to accept invite", "error", err, "invite", invite.Id)
				return re.InternalServerError("Failed to join the workspace", nil)
			}

			services.EmitNotification(app, invite.GetString(util.Fields.Invite.InvitedBy), workspaceId,
				util.NotificationInviteAccepted,
				"Invite accepted",
				re.Auth.GetString(util.Fields.User.Email)+" joined the workspace.",
				util.Coll.Invites, invite.Id)

			return re.JSON(http.StatusOK, map[string]any{
				"ok":          true,
				"workspace":   workspaceId,
				"membership":  member.Id,
				"permissions": util.SurfacesFor(services.InviteGrantedScopes(invite)),
			})
		})

		return e.Next()
	})
}

// findLiveInvite resolves a plaintext token to an invite that may still be
// spent; only the hash is stored.
func findLiveInvite(app core.App, token string) (*core.Record, *util.AppError) {
	if token == "" {
		return nil, &util.Errors.InviteNotFound
	}
	invite, err := app.FindFirstRecordByFilter(util.Coll.Invites,
		"tokenHash = {:h}", map[string]any{"h": util.HashToken(token)})
	if err != nil || invite == nil {
		return nil, &util.Errors.InviteNotFound
	}
	if appErr := services.RefreshInviteStatus(app, invite); appErr != nil {
		return nil, appErr
	}
	return invite, nil
}

func inviteProbe(app core.App, invite *core.Record) map[string]any {
	out := map[string]any{
		"label":         invite.GetString(util.Fields.Invite.Label),
		"role":          invite.GetString(util.Fields.Invite.Role),
		"permissions":   permissionDetails(services.InviteGrantedScopes(invite)),
		"requiresEmail": invite.GetString(util.Fields.Invite.Email) != "",
		"expiresAt":     invite.GetString(util.Fields.Invite.ExpiresAt),
	}
	if ws, err := app.FindRecordById(util.Coll.Workspaces, invite.GetString(util.Fields.Invite.Workspace)); err == nil && ws != nil {
		out["workspace"] = map[string]any{
			"name": ws.GetString(util.Fields.Workspace.Name),
			"type": ws.GetString(util.Fields.Workspace.Type),
		}
	}
	if by, err := app.FindRecordById(util.Coll.Users, invite.GetString(util.Fields.Invite.InvitedBy)); err == nil && by != nil {
		out["invitedBy"] = by.GetString(util.Fields.User.Email)
	}
	return out
}

// permissionDetails labels granted scopes so screens never show raw scope strings.
func permissionDetails(scopes []string) []map[string]any {
	out := []map[string]any{}
	for _, key := range util.SurfacesFor(scopes) {
		perm, ok := util.PermissionByKey(key)
		if !ok {
			continue
		}
		out = append(out, map[string]any{
			"key":         perm.Key,
			"label":       perm.Label,
			"description": perm.Description,
			"destructive": perm.Destructive,
		})
	}
	return out
}

func inviteErrorResponse(re *core.RequestEvent, appErr *util.AppError) error {
	status := http.StatusGone
	if appErr.ErrorCode == util.Errors.InviteNotFound.ErrorCode {
		status = http.StatusNotFound
	}
	return appErrorResponse(re, status, appErr)
}
