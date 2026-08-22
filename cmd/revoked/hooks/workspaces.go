package hooks

import (
	"fmt"
	"revoked/cmd/revoked/services"
	"revoked/util"

	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
)

// BindWorkspacesHooks enforces the per-type workspace creation limits, adds the
// creator as an admin member, and clears the active context of any user pointing
// at a deleted workspace.
func BindWorkspacesHooks(app core.App) {
	app.OnRecordCreateRequest(util.Coll.Workspaces).BindFunc(func(e *core.RecordRequestEvent) error {
		if e.Auth == nil {
			return apis.NewForbiddenError(util.Errors.NotAuthorized.ErrorText, nil)
		}

		memberships, err := e.App.FindRecordsByFilter(
			util.Coll.WorkspaceMembers,
			fmt.Sprintf("%s = {:user}", util.Fields.WorkspaceMember.User),
			"",
			0,
			0,
			map[string]any{"user": e.Auth.Id},
		)
		if err != nil {
			return err
		}

		if len(memberships) >= util.MaximumWorkspacesPerUser {
			return validation.Errors{"user": util.AsValidationError(util.Errors.WorkspaceLimitReached)}
		}

		nextErr := e.Next()
		if nextErr != nil {
			return nextErr
		}

		workspaceMemberships, err := e.App.FindCollectionByNameOrId(util.Coll.WorkspaceMembers)
		if err != nil {
			return nil
		}

		// The creator holds every permission: they are the only member, and a
		// workspace that starts with nobody able to administer it could never
		// be granted anything afterwards.
		ownerScopes, _ := util.ExpandPermissions(util.AllPermissionKeys())

		membership := core.NewRecord(workspaceMemberships)
		membership.Set(util.Fields.WorkspaceMember.User, e.Auth.Id)
		membership.Set(util.Fields.WorkspaceMember.Workspace, e.Record.Id)
		membership.Set(util.Fields.WorkspaceMember.Role, util.RoleAdmin)
		membership.Set(util.Fields.WorkspaceMember.Permissions, ownerScopes)

		if err := e.App.Save(membership); err != nil {
			return err
		}

		return nil
	})

	app.OnRecordDelete(util.Coll.Workspaces).BindFunc(func(e *core.RecordEvent) error {
		// Must be collected before the delete: PocketBase clears the
		// activeWorkspace relation as part of it, so querying afterwards misses
		// these users and leaves a stale activeRole behind.
		users, _ := e.App.FindRecordsByFilter(
			util.Coll.Users,
			fmt.Sprintf("%s = {:workspace}", util.Fields.User.ActiveWorkspace),
			"",
			0,
			0,
			map[string]any{"workspace": e.Record.Id},
		)

		// Children first: most hold a required workspace relation that does not
		// cascade, so PocketBase refuses the delete while any of them exist.
		// Inside this hook rather than before the request, so the teardown and
		// the delete share one transaction — a failure halfway through must
		// leave the workspace whole rather than half-emptied.
		if err := services.TearDownWorkspace(e.App, e.Record.Id); err != nil {
			return err
		}

		if err := e.Next(); err != nil {
			return err
		}

		for _, user := range users {
			user.Set(util.Fields.User.ActiveWorkspace, "")
			user.Set(util.Fields.User.ActiveRole, "")
			_ = e.App.Save(user)
		}

		return nil
	})
}
