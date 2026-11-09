package migrations

import (
	"slices"

	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// contactScopes071 are the scopes this migration introduces, frozen here so a
// later edit to the scope catalogue cannot change what this migration did.
var contactScopes071 = []string{
	"contact:read",
	"contact:create",
	"contact:update",
	"contact:delete",
}

// Adds contacts: the counterparties a workspace sends to and asks from.
//
// A contact is a route, not an identity. It names at most one of each way to
// reach someone — an account on this server, a peer server, an email address —
// and a peer's key material is kept as its own fingerprint and domain rather
// than an identities relation, because that relation is ownership-checked for
// this workspace's own identities and a contact is by definition somebody
// else's.
//
// trustState, verifiedAt and peerFingerprint are the server's to write: a
// member who could mark an address verified would be able to dress it up as a
// proven peer for a co-member to send the vault to, which is the phishing
// primitive this product exists to prevent. The hooks hold them.
//
// The account relation deliberately does not cascade: an address book entry
// outlives the account it pointed at, so a closed account leaves the name and
// email behind rather than deleting what someone wrote down.
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

		contacts := core.NewBaseCollection(util.Coll.Contacts)
		contacts.Fields.Add(
			&core.RelationField{
				Name:          util.Fields.Contact.Workspace,
				CollectionId:  workspaces.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.TextField{Name: util.Fields.Contact.Name, Required: true, Max: 255},
			&core.RelationField{
				Name:         util.Fields.Contact.User,
				CollectionId: users.Id,
				MaxSelect:    1,
			},
			&core.EmailField{Name: util.Fields.Contact.Email},
			&core.TextField{Name: util.Fields.Contact.PeerDomain, Max: 255},
			&core.TextField{Name: util.Fields.Contact.PeerFingerprint, Max: 64},
			&core.SelectField{
				Name:      util.Fields.Contact.TrustState,
				Required:  true,
				Values:    util.ContactTrustStates,
				MaxSelect: 1,
			},
			&core.DateField{Name: util.Fields.Contact.VerifiedAt},
			&core.DateField{Name: util.Fields.Contact.LastUsedAt},
			&core.AutodateField{Name: util.Fields.Contact.Created, OnCreate: true},
			&core.AutodateField{Name: util.Fields.Contact.Updated, OnCreate: true, OnUpdate: true},
		)
		contacts.AddIndex("idxContactsWorkspace", false, util.Fields.Contact.Workspace, "")
		contacts.AddIndex("idxContactsWorkspaceUser", false,
			util.Fields.Contact.Workspace+", "+util.Fields.Contact.User, "")
		contacts.AddIndex("idxContactsWorkspaceEmail", false,
			util.Fields.Contact.Workspace+", "+util.Fields.Contact.Email, "")

		read := util.AccessSpec{Kind: util.AccessWorkspaceSelf, Scope: util.ScopeContactRead}
		contacts.ListRule = types.Pointer(read.Rule())
		contacts.ViewRule = types.Pointer(read.Rule())
		// The specs as they stood here, not the live registry: a later change
		// to it (000097 gave contacts an audience) must not reach back into
		// this migration (see applyFrozenRules).
		for target, scope := range map[**string]string{
			&contacts.CreateRule: util.ScopeContactCreate,
			&contacts.UpdateRule: util.ScopeContactUpdate,
			&contacts.DeleteRule: util.ScopeContactDelete,
		} {
			spec := util.AccessSpec{Kind: util.AccessWorkspaceSelf, Scope: scope}
			*target = types.Pointer(spec.Rule())
		}
		if err := app.Save(contacts); err != nil {
			return err
		}

		for _, col := range []struct{ name, field string }{
			{util.Coll.WorkspaceMembers, util.Fields.WorkspaceMember.Permissions},
			{util.Coll.Invites, util.Fields.Invite.Permissions},
			{util.Coll.ApiKeys, util.Fields.ApiKey.Scopes},
		} {
			if err := widenScopeSelect(app, col.name, col.field); err != nil {
				return err
			}
		}
		return grantContactScopesToAdmins(app)
	}, func(app core.App) error {
		contacts, err := app.FindCollectionByNameOrId(util.Coll.Contacts)
		if err != nil {
			return nil
		}
		return app.Delete(contacts)
	})
}

// grantContactScopesToAdmins gives the new scopes to every member who can
// already extend and withdraw other people's access, as the attestation
// scopes were handed out. Everyone else is granted them by an admin.
func grantContactScopesToAdmins(app core.App) error {
	rows, err := app.FindAllRecords(util.Coll.WorkspaceMembers)
	if err != nil {
		return err
	}
	for _, row := range rows {
		scopes := row.GetStringSlice(util.Fields.WorkspaceMember.Permissions)
		if !util.IsAdminScopeSet(scopes) {
			continue
		}
		changed := false
		for _, s := range contactScopes071 {
			if !slices.Contains(scopes, s) {
				scopes = append(scopes, s)
				changed = true
			}
		}
		if !changed {
			continue
		}
		slices.Sort(scopes)
		row.Set(util.Fields.WorkspaceMember.Permissions, scopes)
		if err := app.Save(row); err != nil {
			return err
		}
	}
	return nil
}
