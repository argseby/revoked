package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds workspace invites: a token an admin hands to someone, carrying the exact
// permissions they will receive.
//
// Only the token's hash is stored, so a leaked database cannot be turned into
// working invites — the plaintext is shown once at creation, like an API key.
// Accepting goes through the public route, which is why create/update/delete
// stay owner-scoped and there is no public read rule: the token is the
// capability and the probe endpoint is the only way to spend it.
func init() {
	migrations.Register(func(app core.App) error {
		workspaces, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return err
		}
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}

		invites := core.NewBaseCollection(util.Coll.Invites)
		invites.Fields.Add(
			&core.RelationField{
				Name:          util.Fields.Invite.Workspace,
				CollectionId:  workspaces.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.TextField{Name: util.Fields.Invite.TokenHash, Required: true, Min: 32, Max: 200, Hidden: true},
			&core.SelectField{
				Name:      util.Fields.Invite.Permissions,
				Values:    util.AllScopes,
				MaxSelect: len(util.AllScopes),
			},
			&core.SelectField{
				Name:      util.Fields.Invite.Role,
				Values:    util.WorkspaceRoles,
				MaxSelect: 1,
			},
			&core.RelationField{
				Name:         util.Fields.Invite.InvitedBy,
				CollectionId: users.Id,
				MaxSelect:    1,
			},
			// Binding an invite to an address stops a forwarded token being
			// spent by whoever received it second.
			&core.TextField{Name: util.Fields.Invite.Email, Max: 255},
			&core.TextField{Name: util.Fields.Invite.Label, Max: 100},
			&core.SelectField{
				Name:      util.Fields.Invite.Status,
				Required:  true,
				Values:    util.InviteStatuses,
				MaxSelect: 1,
			},
			&core.DateField{Name: util.Fields.Invite.ExpiresAt},
			&core.NumberField{Name: util.Fields.Invite.MaxUses, Min: types.Pointer(float64(0))},
			&core.NumberField{Name: util.Fields.Invite.UseCount, Min: types.Pointer(float64(0))},
			&core.AutodateField{Name: util.Fields.Invite.Created, OnCreate: true},
			&core.AutodateField{Name: util.Fields.Invite.Updated, OnCreate: true, OnUpdate: true},
		)

		manage := util.AccessSpec{Kind: util.AccessWorkspaceAdmin, Scope: util.ScopeWorkspaceMembersCreate}
		read := util.AccessSpec{Kind: util.AccessWorkspaceAdmin, Scope: util.ScopeWorkspaceMembersRead}
		invites.ListRule = types.Pointer(read.Rule())
		invites.ViewRule = types.Pointer(read.Rule())
		invites.CreateRule = types.Pointer(manage.Rule())
		invites.UpdateRule = types.Pointer(manage.Rule())
		invites.DeleteRule = types.Pointer(manage.Rule())

		return app.Save(invites)
	}, func(app core.App) error {
		invites, err := app.FindCollectionByNameOrId(util.Coll.Invites)
		if err != nil {
			return nil
		}
		return app.Delete(invites)
	})
}
