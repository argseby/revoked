package migrations

import (
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Gives templates, contacts and attestations an audience (VISIBILITY.md,
// phase 3). Each was workspace data before: every member read it. So every
// existing row starts with the workspace as its audience and editing open to
// it, which is what members could already do with the matching permission,
// and nobody sees less or more than before.
//
// Templates gain an owner (`user`) and contacts one of their own
// (`createdBy`: a contact's `user` is the account it points to). Older rows
// keep none: they stay with the workspace, and only their audience can edit
// them. Built-in
// templates (no workspace) stay readable by everyone signed in.
func init() {
	colls := []string{util.Coll.Templates, util.Coll.Contacts, util.Coll.Attestations}
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		groups, err := app.FindCollectionByNameOrId(util.Coll.Groups)
		if err != nil {
			return err
		}
		s := util.Fields.Section
		for _, name := range colls {
			c, err := app.FindCollectionByNameOrId(name)
			if err != nil {
				return err
			}
			if name == util.Coll.Templates && c.Fields.GetByName(util.Fields.Template.User) == nil {
				c.Fields.Add(&core.RelationField{Name: util.Fields.Template.User, CollectionId: users.Id, MaxSelect: 1})
			}
			// A contact's user is the account it points to; who added it is
			// kept apart.
			if name == util.Coll.Contacts && c.Fields.GetByName(util.Fields.Contact.CreatedBy) == nil {
				c.Fields.Add(&core.RelationField{Name: util.Fields.Contact.CreatedBy, CollectionId: users.Id, MaxSelect: 1})
			}
			if c.Fields.GetByName(s.AudienceKind) == nil {
				c.Fields.Add(&core.SelectField{
					Name:      s.AudienceKind,
					Values:    []string{util.AudiencePrivate, util.AudienceWorkspace, util.AudienceGroups},
					MaxSelect: 1,
				})
			}
			if c.Fields.GetByName(s.AudienceGroups) == nil {
				c.Fields.Add(&core.RelationField{Name: s.AudienceGroups, CollectionId: groups.Id, MaxSelect: 50})
			}
			if c.Fields.GetByName(s.Editing) == nil {
				c.Fields.Add(&core.SelectField{
					Name:      s.Editing,
					Values:    []string{util.EditingOwner, util.EditingAudience},
					MaxSelect: 1,
				})
			}
			for _, f := range []string{s.Readers, s.Editors} {
				if c.Fields.GetByName(f) == nil {
					c.Fields.Add(&core.RelationField{
						Name: f, CollectionId: users.Id,
						MaxSelect: util.MaximumWorkspaceMembers, Hidden: true,
					})
				}
			}
			switch name {
			case util.Coll.Templates:
				applyAudienceRules(c,
					util.WorkspaceAudienceRead(util.ScopeTemplateRead)+" || (@request.auth.id != '' && workspace = '')",
					util.AccessSpec{Kind: util.AccessWorkspaceAudienceSelf, Scope: util.ScopeTemplateUpdate},
					util.AccessSpec{Kind: util.AccessWorkspaceAudienceSelf, Scope: util.ScopeTemplateDelete})
			case util.Coll.Contacts:
				by := util.Fields.Contact.CreatedBy
				applyAudienceRules(c, util.WorkspaceAudienceReadBy(by, util.ScopeContactRead),
					util.AccessSpec{Kind: util.AccessWorkspaceAudienceSelf, Scope: util.ScopeContactUpdate, OwnerField: by},
					util.AccessSpec{Kind: util.AccessWorkspaceAudienceSelf, Scope: util.ScopeContactDelete, OwnerField: by})
			case util.Coll.Attestations:
				applyAudienceRules(c, util.WorkspaceAudienceRead(util.ScopeAttestationRead),
					util.AccessSpec{Kind: util.AccessWorkspaceAudienceAdmin, Scope: util.ScopeAttestationUpdate},
					util.AccessSpec{Kind: util.AccessWorkspaceAudienceAdmin, Scope: util.ScopeAttestationDelete})
			}
			if err := app.Save(c); err != nil {
				return err
			}
			if _, err := app.DB().Update(name, dbx.Params{
				s.AudienceKind: util.AudienceWorkspace,
				s.Editing:      util.EditingAudience,
			}, nil).Execute(); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		s := util.Fields.Section
		frozenRead := map[string]string{
			util.Coll.Templates:    legacyWorkspaceAnyMember(util.ScopeTemplateRead) + " || (@request.auth.id != '' && workspace = '')",
			util.Coll.Contacts:     util.WorkspaceSelfOnly(util.ScopeContactRead),
			util.Coll.Attestations: util.WorkspaceAnyMember(util.ScopeAttestationRead),
		}
		for _, name := range colls {
			c, err := app.FindCollectionByNameOrId(name)
			if err != nil {
				return err
			}
			for _, f := range []string{s.AudienceKind, s.AudienceGroups, s.Editing, s.Readers, s.Editors} {
				c.Fields.RemoveByName(f)
			}
			if name == util.Coll.Templates {
				c.Fields.RemoveByName(util.Fields.Template.User)
			}
			if name == util.Coll.Contacts {
				c.Fields.RemoveByName(util.Fields.Contact.CreatedBy)
			}
			c.ListRule = types.Pointer(frozenRead[name])
			c.ViewRule = types.Pointer(frozenRead[name])
			update, remove := util.ScopeTemplateUpdate, util.ScopeTemplateDelete
			switch name {
			case util.Coll.Contacts:
				update, remove = util.ScopeContactUpdate, util.ScopeContactDelete
				c.UpdateRule = types.Pointer(util.WorkspaceSelfOnly(update))
				c.DeleteRule = types.Pointer(util.WorkspaceSelfOnly(remove))
			case util.Coll.Attestations:
				update, remove = util.ScopeAttestationUpdate, util.ScopeAttestationDelete
				c.UpdateRule = types.Pointer(util.WorkspaceAnyAdmin(update, "workspace"))
				c.DeleteRule = types.Pointer(util.WorkspaceAnyAdmin(remove, "workspace"))
			default:
				c.UpdateRule = types.Pointer(util.WorkspaceAnyAdmin(update, "workspace"))
				c.DeleteRule = types.Pointer(util.WorkspaceAnyAdmin(remove, "workspace"))
			}
			if err := app.Save(c); err != nil {
				return err
			}
		}
		return nil
	})
}
