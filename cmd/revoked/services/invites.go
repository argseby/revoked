package services

import (
	"revoked/util"
	"slices"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// GranterScopes returns the scopes a principal may pass on in a workspace. A
// grant can never exceed what the granter holds, or "invite members" would
// silently be full control.
func GranterScopes(app core.App, auth *core.Record, workspaceId string, isSuperuser bool) []string {
	if isSuperuser {
		scopes, _ := util.ExpandPermissions(util.AllPermissionKeys())
		return scopes
	}
	if auth == nil {
		return nil
	}

	switch auth.Collection().Name {
	case util.Coll.ApiKeys:
		if auth.GetString(util.Fields.ApiKey.Workspace) != workspaceId {
			return nil
		}
		return auth.GetStringSlice(util.Fields.ApiKey.Scopes)
	case util.Coll.Users:
		member, found := util.WorkspaceMemberOf(app, workspaceId, auth.Id)
		if !found {
			return nil
		}
		// A legacy admin predates the permission field: the role stands for the full set.
		if member.GetString(util.Fields.WorkspaceMember.Role) == util.RoleAdmin &&
			len(member.GetStringSlice(util.Fields.WorkspaceMember.Permissions)) == 0 {
			scopes, _ := util.ExpandPermissions(util.AllPermissionKeys())
			return scopes
		}
		return member.GetStringSlice(util.Fields.WorkspaceMember.Permissions)
	}
	return nil
}

// RefreshInviteStatus settles an invite's lifecycle and reports whether it may
// still be spent.
func RefreshInviteStatus(app core.App, invite *core.Record) *util.AppError {
	switch invite.GetString(util.Fields.Invite.Status) {
	case util.StatusRevoked:
		return &util.Errors.InviteRevoked
	case util.StatusExpired:
		return &util.Errors.InviteExpired
	case util.StatusCompleted:
		return &util.Errors.InviteExhausted
	}

	if expiresAt := invite.GetDateTime(util.Fields.Invite.ExpiresAt); !expiresAt.IsZero() {
		if expiresAt.Time().Before(time.Now()) {
			invite.Set(util.Fields.Invite.Status, util.StatusExpired)
			if err := app.Save(invite); err != nil {
				app.Logger().Error("Failed to persist invite expiry", "error", err, "invite", invite.Id)
			}
			return &util.Errors.InviteExpired
		}
	}

	if max := invite.GetInt(util.Fields.Invite.MaxUses); max > 0 {
		if invite.GetInt(util.Fields.Invite.UseCount) >= max {
			invite.Set(util.Fields.Invite.Status, util.StatusCompleted)
			if err := app.Save(invite); err != nil {
				app.Logger().Error("Failed to persist invite completion", "error", err, "invite", invite.Id)
			}
			return &util.Errors.InviteExhausted
		}
	}

	return nil
}

// ClaimInviteUse consumes one use of an invite in a single guarded UPDATE:
// concurrent redeemers of the last use would otherwise both pass the maxUses
// test; zero rows affected means already spent.
func ClaimInviteUse(app core.App, invite *core.Record) error {
	res, err := app.DB().NewQuery(`
		UPDATE {{invites}}
		SET useCount = COALESCE(useCount, 0) + 1
		WHERE id = {:id}
		  AND (COALESCE(maxUses, 0) = 0 OR COALESCE(useCount, 0) < maxUses)
	`).Bind(dbx.Params{"id": invite.Id}).Execute()
	if err != nil {
		return err
	}
	affected, err := res.RowsAffected()
	if err != nil || affected == 0 {
		return util.ErrInviteAlreadySpent
	}

	used := invite.GetInt(util.Fields.Invite.UseCount) + 1
	invite.Set(util.Fields.Invite.UseCount, used)
	if max := invite.GetInt(util.Fields.Invite.MaxUses); max > 0 && used >= max {
		invite.Set(util.Fields.Invite.Status, util.StatusCompleted)
		if _, err := app.DB().NewQuery(`UPDATE {{invites}} SET status = {:s} WHERE id = {:id}`).
			Bind(dbx.Params{"s": util.StatusCompleted, "id": invite.Id}).Execute(); err != nil {
			app.Logger().Error("Failed to close spent invite", "error", err, "invite", invite.Id)
		}
	}
	return nil
}

// WorkspaceAdminCount counts members who can still manage membership.
func WorkspaceAdminCount(app core.App, workspaceId string, excludingMemberId string) int {
	members, err := app.FindAllRecords(util.Coll.WorkspaceMembers,
		dbx.HashExp{util.Fields.WorkspaceMember.Workspace: workspaceId})
	if err != nil {
		return 0
	}
	count := 0
	for _, m := range members {
		if excludingMemberId != "" && m.Id == excludingMemberId {
			continue
		}
		if MemberCanAdminister(m) {
			count++
		}
	}
	return count
}

// MemberCanAdminister reports whether a membership row can bring people into
// the workspace — what the derived role tracks and the last-administrator
// guard counts: without one such member, access can never be restored.
func MemberCanAdminister(member *core.Record) bool {
	perms := member.GetStringSlice(util.Fields.WorkspaceMember.Permissions)
	if slices.Contains(perms, util.ScopeWorkspaceMembersCreate) {
		return true
	}
	// Legacy rows carry the role but no permissions.
	return member.GetString(util.Fields.WorkspaceMember.Role) == util.RoleAdmin && len(perms) == 0
}

// InviteGrantedScopes returns the scopes an invite hands out, deduplicated.
func InviteGrantedScopes(invite *core.Record) []string {
	scopes := invite.GetStringSlice(util.Fields.Invite.Permissions)
	out := make([]string, 0, len(scopes))
	for _, s := range scopes {
		if !slices.Contains(out, s) {
			out = append(out, s)
		}
	}
	return out
}
