package migrations

import (
	"slices"

	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Gives vault entries a visibility of their own, beside the sections holding
// them (a company's root vault: its address, its phone number), and locks the
// shared vault behind a permission (VISIBILITY.md):
//
//   - records.audienceKind / audienceGroups / editing, as sections have.
//     Every existing entry starts private, as it was.
//   - record:publish ("Publish to the workspace vault"): needed to make a
//     vault entry or section visible beyond its owner, and to change one that
//     is. Handed to every member who administers a workspace, and to every
//     member who already owns a section visible beyond them, so nothing they
//     published stops working; everyone else asks an admin for it.
func init() {
	migrations.Register(func(app core.App) error {
		groups, err := app.FindCollectionByNameOrId(util.Coll.Groups)
		if err != nil {
			return err
		}
		s := util.Fields.Section
		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}
		if records.Fields.GetByName(s.AudienceKind) == nil {
			records.Fields.Add(&core.SelectField{
				Name:      s.AudienceKind,
				Values:    []string{util.AudiencePrivate, util.AudienceWorkspace, util.AudienceGroups},
				MaxSelect: 1,
			})
		}
		if records.Fields.GetByName(s.AudienceGroups) == nil {
			records.Fields.Add(&core.RelationField{Name: s.AudienceGroups, CollectionId: groups.Id, MaxSelect: 50})
		}
		if records.Fields.GetByName(s.Editing) == nil {
			records.Fields.Add(&core.SelectField{
				Name:      s.Editing,
				Values:    []string{util.EditingOwner, util.EditingAudience},
				MaxSelect: 1,
			})
		}
		if err := app.Save(records); err != nil {
			return err
		}
		if _, err := app.DB().Update(util.Coll.Records, dbx.Params{
			s.AudienceKind: util.AudiencePrivate,
			s.Editing:      util.EditingOwner,
		}, nil).Execute(); err != nil {
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

		// Who already published something keeps being able to.
		publishers := map[string]bool{}
		shared, err := app.FindRecordsByFilter(util.Coll.Sections,
			s.AudienceKind+" != {:p} && "+s.AudienceKind+" != ''", "", 0, 0, dbx.Params{"p": util.AudiencePrivate})
		if err != nil {
			return err
		}
		for _, sec := range shared {
			publishers[sec.GetString(s.Workspace)+"/"+sec.GetString(s.User)] = true
		}
		members, err := app.FindAllRecords(util.Coll.WorkspaceMembers)
		if err != nil {
			return err
		}
		m := util.Fields.WorkspaceMember
		for _, row := range members {
			scopes := row.GetStringSlice(m.Permissions)
			if len(scopes) == 0 || slices.Contains(scopes, util.ScopeRecordPublish) {
				continue // a legacy row holds everything already
			}
			if !util.IsAdminScopeSet(scopes) && !publishers[row.GetString(m.Workspace)+"/"+row.GetString(m.User)] {
				continue
			}
			scopes = append(scopes, util.ScopeRecordPublish)
			slices.Sort(scopes)
			row.Set(m.Permissions, scopes)
			if err := app.Save(row); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}
		s := util.Fields.Section
		for _, f := range []string{s.AudienceKind, s.AudienceGroups, s.Editing} {
			records.Fields.RemoveByName(f)
		}
		return app.Save(records)
	})
}
