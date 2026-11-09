package migrations

import (
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Gives shares (links) and requests an audience, and the server-kept lists of
// who sees and who edits them (VISIBILITY.md, phase 2), as 000095 did for
// sections.
//
// Every share and request starts private with the owner editing, as they are
// seen today. readers and editors are filled in by the reconcile pass at
// startup.
func init() {
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
		for _, name := range []string{util.Coll.Links, util.Coll.Requests} {
			c, err := app.FindCollectionByNameOrId(name)
			if err != nil {
				return err
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
			read, update, remove := util.ScopeLinkRead, util.ScopeLinkUpdate, util.ScopeLinkDelete
			if name == util.Coll.Requests {
				read, update, remove = util.ScopeRequestRead, util.ScopeRequestUpdate, util.ScopeRequestDelete
			}
			applyAudienceRules(c, util.WorkspaceAudienceRead(read),
				util.AccessSpec{Kind: util.AccessWorkspaceAudienceSelf, Scope: update},
				util.AccessSpec{Kind: util.AccessWorkspaceAudienceSelf, Scope: remove})
			if err := app.Save(c); err != nil {
				return err
			}
			if _, err := app.DB().Update(name, dbx.Params{
				s.AudienceKind: util.AudiencePrivate,
				s.Editing:      util.EditingOwner,
			}, nil).Execute(); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		s := util.Fields.Section
		for _, name := range []string{util.Coll.Links, util.Coll.Requests} {
			c, err := app.FindCollectionByNameOrId(name)
			if err != nil {
				return err
			}
			for _, f := range []string{s.AudienceKind, s.AudienceGroups, s.Editing, s.Readers, s.Editors} {
				c.Fields.RemoveByName(f)
			}
			read, update, remove := util.ScopeLinkRead, util.ScopeLinkUpdate, util.ScopeLinkDelete
			if name == util.Coll.Requests {
				read, update, remove = util.ScopeRequestRead, util.ScopeRequestUpdate, util.ScopeRequestDelete
			}
			c.ListRule = types.Pointer(legacyWorkspaceSelfOnly(read))
			c.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(read))
			c.UpdateRule = types.Pointer(util.WorkspaceSelfOnly(update))
			c.DeleteRule = types.Pointer(util.WorkspaceSelfOnly(remove))
			if err := app.Save(c); err != nil {
				return err
			}
		}
		return nil
	})
}
