package migrations

import (
	"slices"

	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// attestationScopes067 are the scopes this migration introduces, frozen here
// so the backfill below grants the same set forever.
var attestationScopes067 = []string{
	"attestation:read",
	"attestation:create",
	"attestation:update",
	"attestation:delete",
}

// Adds attestations: statements this server signs about an identity, and the
// credentials people hold.
//
// attestations is the issuing side. A row is created as an offer — what is
// stated, and a one-time token whose hash is kept — and becomes active when
// its subject accepts it with a proof of their identity key. The signed
// credential is handed over at that moment and not stored here. Writes are
// governed by the attestation permission alone; reads are narrowed to it by
// the hooks, since a row states things about a person.
//
// attestationStatus holds one row per issued credential: its place in the
// published status list and whether it was revoked. It names the attestation
// by id rather than by relation, so the bit survives the row, the workspace
// and the account — a credential revoked once stays revoked. Superuser-only.
//
// credentials is the holding side: the credential itself, bound to one of the
// holder's identities. Personal, written by the claim route alone.
//
// The permission columns are widened to the current scope list, and members
// who can already administer a workspace receive the new scopes: nobody could
// grant what nobody holds, so without this an existing workspace could never
// issue.
func init() {
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		workspaces, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return err
		}
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return err
		}

		a := util.Fields.Attestation
		attestations := core.NewBaseCollection(util.Coll.Attestations)
		attestations.Fields.Add(
			// Neither relation cascades: an attestation is removed through its
			// delete hook, which is what records the revocation. The issuing
			// member is not required, so the statement outlives their account:
			// it was the workspace's, made in the domain's name.
			&core.RelationField{Name: a.User, CollectionId: users.Id, MaxSelect: 1},
			&core.RelationField{Name: a.Workspace, CollectionId: workspaces.Id, Required: true, MaxSelect: 1},
			&core.TextField{Name: a.Type, Required: true, Max: 255},
			&core.TextField{Name: a.Label, Max: 200},
			&core.JSONField{Name: a.Claims, MaxSize: 64 << 10},
			&core.SelectField{
				Name:      a.Status,
				Required:  true,
				Values:    util.AttestationStatuses,
				MaxSelect: 1,
			},
			// When the credential itself stops being valid; empty for none.
			&core.DateField{Name: a.ExpiresAt},
			&core.TextField{Name: a.OfferTokenHash, Max: 64, Hidden: true},
			&core.DateField{Name: a.OfferExpiresAt},
			// Set by the issuer to make the offer for one identity only, and by
			// the server when the offer is accepted.
			&core.TextField{Name: a.SubjectFingerprint, Max: 64},
			&core.TextField{Name: a.SubjectDomain, Max: 255},
			&core.TextField{Name: a.SubjectName, Max: 255},
			&core.DateField{Name: a.IssuedAt},
			&core.DateField{Name: a.RevokedAt},
			&core.TextField{Name: a.RevokedReason, Max: 100},
			&core.AutodateField{Name: a.Created, OnCreate: true},
			&core.AutodateField{Name: a.Updated, OnCreate: true, OnUpdate: true},
		)
		attestations.AddIndex("idxAttestationsOffer", true, a.OfferTokenHash, a.OfferTokenHash+" != ''")
		attestations.AddIndex("idxAttestationsWorkspace", false, a.Workspace+", "+a.Status, "")

		read := util.AccessSpec{Kind: util.AccessWorkspaceMember, Scope: util.ScopeAttestationRead}
		create := util.AccessSpec{Kind: util.AccessWorkspaceAdmin, Scope: util.ScopeAttestationCreate}
		update := util.AccessSpec{Kind: util.AccessWorkspaceAdmin, Scope: util.ScopeAttestationUpdate}
		remove := util.AccessSpec{Kind: util.AccessWorkspaceAdmin, Scope: util.ScopeAttestationDelete}
		attestations.ListRule = types.Pointer(read.Rule())
		attestations.ViewRule = types.Pointer(read.Rule())
		attestations.CreateRule = types.Pointer(create.Rule())
		attestations.UpdateRule = types.Pointer(update.Rule())
		attestations.DeleteRule = types.Pointer(remove.Rule())
		if err := app.Save(attestations); err != nil {
			return err
		}

		s := util.Fields.AttestationStatus
		status := core.NewBaseCollection(util.Coll.AttestationStatus)
		status.Fields.Add(
			// Not required: zero is a valid position in the list.
			&core.NumberField{Name: s.Idx, OnlyInt: true, Min: types.Pointer(float64(0))},
			// Text, not a relation: the bit must outlive the attestation.
			&core.TextField{Name: s.Attestation, Required: true, Max: 64},
			&core.BoolField{Name: s.Revoked},
			&core.DateField{Name: s.RevokedAt},
			&core.AutodateField{Name: s.Created, OnCreate: true},
		)
		status.AddIndex("idxAttestationStatusIdx", true, s.Idx, "")
		status.AddIndex("idxAttestationStatusAttestation", true, s.Attestation, "")
		if err := app.Save(status); err != nil {
			return err
		}

		c := util.Fields.Credential
		credentials := core.NewBaseCollection(util.Coll.Credentials)
		credentials.Fields.Add(
			&core.RelationField{Name: c.User, CollectionId: users.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.RelationField{Name: c.Workspace, CollectionId: workspaces.Id, MaxSelect: 1, CascadeDelete: true},
			// A credential is bound to this identity's key and is of no use
			// without it.
			&core.RelationField{Name: c.Identity, CollectionId: identities.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.TextField{Name: c.Issuer, Required: true, Max: 255},
			&core.TextField{Name: c.Type, Required: true, Max: 255},
			&core.TextField{Name: c.Credential, Required: true, Max: util.MaxCredentialLength},
			&core.JSONField{Name: c.Claims, MaxSize: 64 << 10},
			&core.DateField{Name: c.IssuedAt},
			&core.DateField{Name: c.ExpiresAt},
			&core.AutodateField{Name: c.Created, OnCreate: true},
			&core.AutodateField{Name: c.Updated, OnCreate: true, OnUpdate: true},
		)
		credentials.AddIndex("idxCredentialsUser", false, c.User+", "+c.Workspace, "")
		owner := util.AccessSpec{Kind: util.AccessUserSelf}
		credentials.ListRule = types.Pointer(owner.Rule())
		credentials.ViewRule = types.Pointer(owner.Rule())
		credentials.DeleteRule = types.Pointer(owner.Rule())
		if err := app.Save(credentials); err != nil {
			return err
		}

		if err := widenScopeSelect(app, util.Coll.WorkspaceMembers, util.Fields.WorkspaceMember.Permissions); err != nil {
			return err
		}
		if err := widenScopeSelect(app, util.Coll.Invites, util.Fields.Invite.Permissions); err != nil {
			return err
		}
		if err := widenScopeSelect(app, util.Coll.ApiKeys, util.Fields.ApiKey.Scopes); err != nil {
			return err
		}
		if err := grantAttestationScopesToAdmins(app); err != nil {
			return err
		}

		notifications, err := app.FindCollectionByNameOrId(util.Coll.Notifications)
		if err != nil {
			return err
		}
		if typeField, ok := notifications.Fields.GetByName(util.Fields.Notification.Type).(*core.SelectField); ok {
			typeField.Values = util.NotificationTypes
			return app.Save(notifications)
		}
		return nil
	}, func(app core.App) error {
		for _, name := range []string{util.Coll.Credentials, util.Coll.AttestationStatus, util.Coll.Attestations} {
			if col, err := app.FindCollectionByNameOrId(name); err == nil {
				if err := app.Delete(col); err != nil {
					return err
				}
			}
		}
		return nil
	})
}

// widenScopeSelect brings a permission column's allowed values up to the
// current scope list. On a database built from scratch the column already has
// them, since the migrations that created it read the same list.
func widenScopeSelect(app core.App, collection, field string) error {
	col, err := app.FindCollectionByNameOrId(collection)
	if err != nil {
		return err
	}
	sel, ok := col.Fields.GetByName(field).(*core.SelectField)
	if !ok {
		return nil
	}
	if len(sel.Values) == len(util.AllScopes) {
		return nil
	}
	sel.Values = util.AllScopes
	sel.MaxSelect = len(util.AllScopes)
	return app.Save(col)
}

// grantAttestationScopesToAdmins gives the new scopes to every member who can
// already extend and withdraw other people's access. Members without that are
// left as they are; an admin grants them the permission like any other.
func grantAttestationScopesToAdmins(app core.App) error {
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
		for _, s := range attestationScopes067 {
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
