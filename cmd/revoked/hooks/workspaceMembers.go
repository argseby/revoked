package hooks

import (
	"fmt"
	"revoked/cmd/revoked/services"
	"revoked/util"

	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
)

// BindWorkspaceMembersHooks restricts member creation to the caller's active
// workspace, rejects duplicates, and enforces the per-type member cap.
func BindWorkspaceMembersHooks(app core.App) {
	app.OnRecordCreateRequest(util.Coll.WorkspaceMembers).BindFunc(func(e *core.RecordRequestEvent) error {
		if e.Auth == nil {
			return apis.NewForbiddenError("", nil)
		}

		var activeWS string
		switch e.Auth.Collection().Name {
		case util.Coll.Users:
			activeWS = e.Auth.GetString(util.Fields.User.ActiveWorkspace)
		case util.Coll.ApiKeys:
			activeWS = e.Auth.GetString(util.Fields.ApiKey.Workspace)
		}

		targetWS := e.Record.GetString(util.Fields.WorkspaceMember.Workspace)
		if targetWS == "" || targetWS != activeWS {
			return apis.NewForbiddenError("Members can only be managed within your active workspace.", nil)
		}

		// Same ceiling as an invite: adding a member directly must not be a way
		// to hand out access the granter does not hold.
		if err := normalizePermissionGrant(app, e, util.Fields.WorkspaceMember.Permissions, targetWS); err != nil {
			return err
		}

		return e.Next()
	})

	// A member's permissions may never exceed the granter's own, and a
	// workspace must always keep someone who can manage membership.
	app.OnRecordUpdateRequest(util.Coll.WorkspaceMembers).BindFunc(func(e *core.RecordRequestEvent) error {
		if e.RequestEvent.HasSuperuserAuth() {
			return e.Next()
		}
		workspaceId := e.Record.GetString(util.Fields.WorkspaceMember.Workspace)

		if err := normalizePermissionGrant(app, e, util.Fields.WorkspaceMember.Permissions, workspaceId); err != nil {
			return err
		}

		if !services.MemberCanAdminister(e.Record) &&
			services.WorkspaceAdminCount(app, workspaceId, e.Record.Id) == 0 {
			return validation.Errors{
				util.Fields.WorkspaceMember.Permissions: util.AsValidationError(util.Errors.LastAdminProtected),
			}
		}

		return e.Next()
	})

	app.OnRecordDeleteRequest(util.Coll.WorkspaceMembers).BindFunc(func(e *core.RecordRequestEvent) error {
		if e.RequestEvent.HasSuperuserAuth() {
			return e.Next()
		}
		// Removing yourself is allowed; removing the last administrator is not,
		// because nobody would be left who could restore access.
		workspaceId := e.Record.GetString(util.Fields.WorkspaceMember.Workspace)
		if services.MemberCanAdminister(e.Record) &&
			services.WorkspaceAdminCount(app, workspaceId, e.Record.Id) == 0 {
			return validation.Errors{
				util.Fields.WorkspaceMember.User: util.AsValidationError(util.Errors.LastAdminProtected),
			}
		}
		return e.Next()
	})

	// Losing membership must invalidate the credentials that assert it. The
	// certificate the departing member already holds names this workspace's
	// domain and is signed for ten years; nothing but a revocation stops it from
	// going on making that claim from another server, where the local
	// membership check never runs.
	//
	// Inside the delete transaction, so the revocation cannot commit without the
	// removal or the removal without it.
	app.OnRecordDelete(util.Coll.WorkspaceMembers).BindFunc(func(e *core.RecordEvent) error {
		userId := e.Record.GetString(util.Fields.WorkspaceMember.User)
		workspaceId := e.Record.GetString(util.Fields.WorkspaceMember.Workspace)

		if err := e.Next(); err != nil {
			return err
		}
		return services.RevokeWorkspaceIdentities(e.App, userId, workspaceId, util.RevocationMembershipEnded)
	})

	// role is a denormalization of the permissions so the collection rules can
	// test it: matching the permission list inside a rule is not reliable, but
	// matching a single-value select is. Derive it on every write rather than
	// letting a caller set the two independently.
	syncRole := func(e *core.RecordEvent) error {
		if services.MemberCanAdminister(e.Record) {
			e.Record.Set(util.Fields.WorkspaceMember.Role, util.RoleAdmin)
		} else {
			e.Record.Set(util.Fields.WorkspaceMember.Role, util.RoleMember)
		}
		return e.Next()
	}
	app.OnRecordCreate(util.Coll.WorkspaceMembers).BindFunc(syncRole)
	app.OnRecordUpdate(util.Coll.WorkspaceMembers).BindFunc(syncRole)

	app.OnRecordCreate(util.Coll.WorkspaceMembers).BindFunc(func(e *core.RecordEvent) error {
		userId := e.Record.GetString(util.Fields.WorkspaceMember.User)
		workspaceId := e.Record.GetString(util.Fields.WorkspaceMember.Workspace)

		if userId == "" || workspaceId == "" {
			return e.Next()
		}

		existing, err := e.App.FindFirstRecordByFilter(
			util.Coll.WorkspaceMembers,
			fmt.Sprintf(
				"%s = {:user} && %s = {:workspace}",
				util.Fields.WorkspaceMember.User,
				util.Fields.WorkspaceMember.Workspace,
			),
			map[string]any{
				"user":      userId,
				"workspace": workspaceId,
			},
		)
		if err == nil && existing != nil {
			return validation.Errors{
				util.Fields.WorkspaceMember.User: util.AsValidationError(util.Errors.DuplicateWorkspaceMember),
			}
		}

		maxMembers := util.MaximumWorkspaceMembers

		count, err := e.App.CountRecords(
			util.Coll.WorkspaceMembers,
			dbx.HashExp{util.Fields.WorkspaceMember.Workspace: workspaceId},
		)
		if err != nil {
			return err
		}

		if int(count) >= maxMembers {
			return validation.Errors{
				util.Fields.WorkspaceMember.Workspace: util.AsValidationError(util.Errors.WorkspaceMemberLimitReached),
			}
		}

		return e.Next()
	})
}
