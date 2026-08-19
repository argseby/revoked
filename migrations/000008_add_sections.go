package migrations

import (
	"revoked/util"
	"strings"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds the sections collection: named groups of records, unique per
// (workspace, key, user) and readable only by their owner.
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

		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}

		sections := core.NewBaseCollection(util.Coll.Sections)
		sections.Fields.Add(
			&core.TextField{Name: util.Fields.Section.Key, Required: true, Min: 1, Max: 100, Pattern: "^[a-z0-9_]+$"},
			&core.TextField{Name: util.Fields.Section.Name, Required: true, Min: 1, Max: 100},
			&core.RelationField{
				Name:         util.Fields.Section.Records,
				CollectionId: recordsCol.Id,
				MaxSelect:    500,
			},

			&core.AutodateField{Name: util.Fields.Section.Created, OnCreate: true},
			&core.AutodateField{Name: util.Fields.Section.Updated, OnCreate: true, OnUpdate: true},
			&core.RelationField{
				Name:         util.Fields.Section.User,
				CollectionId: users.Id,
				Required:     true,
				MaxSelect:    1,
			},
			&core.RelationField{
				Name:         util.Fields.Section.Workspace,
				CollectionId: workspaces.Id,
				Required:     true,
				MaxSelect:    1,
			},
		)
		sections.AddIndex("idxSectionsKeyUserWorkspace", true, strings.Join([]string{
			util.Fields.Section.Workspace,
			util.Fields.Section.Key,
			util.Fields.Section.User,
		}, ","), "")

		sections.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeSectionRead))
		sections.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeSectionRead))
		sections.UpdateRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeSectionUpdate))
		sections.DeleteRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeSectionDelete))
		sections.CreateRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeSectionCreate))

		if err := app.Save(sections); err != nil {
			return err
		}

		return nil

	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err != nil {
			return nil
		}

		if err := app.Delete(col); err != nil {
			return err
		}

		return nil
	})
}
