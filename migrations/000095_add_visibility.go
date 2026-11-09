package migrations

import (
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Gives sections an audience and records and sections the server-kept list
// of who sees and who edits them (VISIBILITY.md, phase 1).
//
//   - sections.audienceKind / audienceGroups / editing: who sees the section,
//     and whether that audience may change it. Only the owner sets them.
//   - readers / editors on sections and records: the outcome of
//     services.Access, written by the server alone and matched by the rules,
//     so a rule never has to evaluate a permission or join through a
//     multi-value column. Hidden: no response carries them.
//   - groups / groupMembers: the shape audiences will name once groups can be
//     managed. Superuser-only until then.
//
// Every section starts as it is seen today: shared sections become
// "workspace" with editing open to the audience (members who may manage the
// vault could already change them), every other section "private". readers
// and editors are filled in at startup by the reconcile pass, before the
// server takes requests.
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

		g := util.Fields.Group
		groups := core.NewBaseCollection(util.Coll.Groups)
		groups.Fields.Add(
			&core.RelationField{Name: g.Workspace, CollectionId: workspaces.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.TextField{Name: g.Key, Required: true, Min: 1, Max: 40, Pattern: util.SlugPattern},
			&core.TextField{Name: g.Name, Required: true, Min: 1, Max: 80},
			&core.AutodateField{Name: g.Created, OnCreate: true},
			&core.AutodateField{Name: g.Updated, OnCreate: true, OnUpdate: true},
		)
		groups.AddIndex("idxGroupsWorkspaceKey", true, g.Workspace+", "+g.Key, "")
		if err := app.Save(groups); err != nil {
			return err
		}

		gm := util.Fields.GroupMember
		groupMembers := core.NewBaseCollection(util.Coll.GroupMembers)
		groupMembers.Fields.Add(
			&core.RelationField{Name: gm.Group, CollectionId: groups.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.RelationField{Name: gm.User, CollectionId: users.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.AutodateField{Name: gm.Created, OnCreate: true},
		)
		groupMembers.AddIndex("idxGroupMembersGroupUser", true, gm.Group+", "+gm.User, "")
		if err := app.Save(groupMembers); err != nil {
			return err
		}

		audienceColumns := func(c *core.Collection) {
			for _, name := range []string{util.Fields.Section.Readers, util.Fields.Section.Editors} {
				if c.Fields.GetByName(name) == nil {
					c.Fields.Add(&core.RelationField{
						Name: name, CollectionId: users.Id,
						MaxSelect: util.MaximumWorkspaceMembers, Hidden: true,
					})
				}
			}
		}

		s := util.Fields.Section
		sections, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err != nil {
			return err
		}
		if sections.Fields.GetByName(s.AudienceKind) == nil {
			sections.Fields.Add(&core.SelectField{
				Name:      s.AudienceKind,
				Values:    []string{util.AudiencePrivate, util.AudienceWorkspace, util.AudienceGroups},
				MaxSelect: 1,
			})
		}
		if sections.Fields.GetByName(s.AudienceGroups) == nil {
			sections.Fields.Add(&core.RelationField{Name: s.AudienceGroups, CollectionId: groups.Id, MaxSelect: 50})
		}
		if sections.Fields.GetByName(s.Editing) == nil {
			sections.Fields.Add(&core.SelectField{
				Name:      s.Editing,
				Values:    []string{util.EditingOwner, util.EditingAudience},
				MaxSelect: 1,
			})
		}
		audienceColumns(sections)
		applyAudienceRules(sections, util.WorkspaceAudienceRead(util.ScopeSectionRead),
			util.AccessSpec{Kind: util.AccessWorkspaceAudience, Scope: util.ScopeSectionUpdate, ResponseScope: util.ScopeResponseUpdate},
			util.AccessSpec{Kind: util.AccessWorkspaceAudience, Scope: util.ScopeSectionDelete, ResponseScope: util.ScopeResponseDelete})
		if err := app.Save(sections); err != nil {
			return err
		}

		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}
		audienceColumns(records)
		applyAudienceRules(records, util.WorkspaceAudienceRead(util.ScopeRecordRead),
			util.AccessSpec{Kind: util.AccessWorkspaceAudience, Scope: util.ScopeRecordUpdate, ResponseScope: util.ScopeResponseUpdate},
			util.AccessSpec{Kind: util.AccessWorkspaceAudience, Scope: util.ScopeRecordDelete, ResponseScope: util.ScopeResponseDelete})
		if err := app.Save(records); err != nil {
			return err
		}

		_, err = app.DB().NewQuery(
			"UPDATE {{" + util.Coll.Sections + "}} SET " +
				"[[" + s.AudienceKind + "]] = CASE WHEN [[" + s.Shared + "]] THEN {:workspace} ELSE {:private} END, " +
				"[[" + s.Editing + "]] = CASE WHEN [[" + s.Shared + "]] THEN {:audience} ELSE {:owner} END",
		).Bind(dbx.Params{
			"workspace": util.AudienceWorkspace, "private": util.AudiencePrivate,
			"audience": util.EditingAudience, "owner": util.EditingOwner,
		}).Execute()
		return err
	}, func(app core.App) error {
		for _, name := range []string{util.Coll.Sections, util.Coll.Records} {
			c, err := app.FindCollectionByNameOrId(name)
			if err != nil {
				return err
			}
			for _, f := range []string{
				util.Fields.Section.AudienceKind, util.Fields.Section.AudienceGroups,
				util.Fields.Section.Editing, util.Fields.Section.Readers, util.Fields.Section.Editors,
			} {
				c.Fields.RemoveByName(f)
			}
			scope := util.ScopeRecordRead
			update, remove := util.ScopeRecordUpdate, util.ScopeRecordDelete
			if name == util.Coll.Sections {
				scope = util.ScopeSectionRead
				update, remove = util.ScopeSectionUpdate, util.ScopeSectionDelete
			}
			c.ListRule = types.Pointer(legacyWorkspaceSelfOnly(scope))
			c.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(scope))
			c.UpdateRule = types.Pointer(util.WorkspaceSplitOrigin(update, util.ScopeResponseUpdate))
			c.DeleteRule = types.Pointer(util.WorkspaceSplitOrigin(remove, util.ScopeResponseDelete))
			if err := app.Save(c); err != nil {
				return err
			}
		}
		for _, name := range []string{util.Coll.GroupMembers, util.Coll.Groups} {
			if c, err := app.FindCollectionByNameOrId(name); err == nil {
				if err := app.Delete(c); err != nil {
					return err
				}
			}
		}
		return nil
	})
}

// applyAudienceRules installs the read rule and the update/delete rules of a
// collection with an audience. Each migration passes the specs as they stand
// there, never the live registry (see applyFrozenRules); the registry test
// checks the result.
func applyAudienceRules(c *core.Collection, read string, update, remove util.AccessSpec) {
	c.ListRule = types.Pointer(read)
	c.ViewRule = types.Pointer(read)
	c.UpdateRule = types.Pointer(update.Rule())
	c.DeleteRule = types.Pointer(remove.Rule())
}
