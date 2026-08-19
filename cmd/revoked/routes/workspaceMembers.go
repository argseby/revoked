package routes

import (
	"net/http"
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// WorkspaceMembersRoute lists who is in a workspace and what each may do. A
// custom route because users.viewRule is self-only, so the collection API
// cannot expand member names; being a member is the only requirement.
func WorkspaceMembersRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/workspaces/{id}/members", func(re *core.RequestEvent) error {
			if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			workspaceId := re.Request.PathValue("id")

			caller, isMember := util.WorkspaceMemberOf(app, workspaceId, re.Auth.Id)
			if !isMember {
				return appErrorResponse(re, http.StatusForbidden, &util.Errors.NotWorkspaceMember)
			}
			callerScopes := services.GranterScopes(app, re.Auth, workspaceId, false)

			members, err := app.FindAllRecords(util.Coll.WorkspaceMembers,
				dbx.HashExp{util.Fields.WorkspaceMember.Workspace: workspaceId})
			if err != nil {
				return re.InternalServerError("Failed to load members", nil)
			}

			admins := services.WorkspaceAdminCount(app, workspaceId, "")

			out := make([]map[string]any, 0, len(members))
			for _, member := range members {
				scopes := member.GetStringSlice(util.Fields.WorkspaceMember.Permissions)
				userId := member.GetString(util.Fields.WorkspaceMember.User)

				entry := map[string]any{
					"id":          member.Id,
					"user":        userId,
					"role":        member.GetString(util.Fields.WorkspaceMember.Role),
					"permissions": permissionDetails(scopes),
					"isSelf":      userId == re.Auth.Id,
					// Losing the last member able to invite leaves the workspace unadministrable.
					"isLastAdmin": services.MemberCanAdminister(member) && admins <= 1,
					"joined":      member.GetString(util.Fields.WorkspaceMember.Created),
				}
				if user, err := app.FindRecordById(util.Coll.Users, userId); err == nil && user != nil {
					entry["email"] = user.GetString(util.Fields.User.Email)
				}
				out = append(out, entry)
			}

			return re.JSON(http.StatusOK, map[string]any{
				"members": out,
				// What the caller may hand out without it being refused as escalation.
				"grantable": permissionDetails(callerScopes),
				"canManage": services.MemberCanAdminister(caller),
			})
		})
		return e.Next()
	})
}
