package migrations

import (
	"revoked/util"
	"strings"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds the records collection: the individual vault entries, unique per
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

		records := core.NewBaseCollection(util.Coll.Records)
		records.Fields.Add(
			&core.TextField{Name: util.Fields.Record.Key, Required: true, Min: 1, Max: 100},
			&core.TextField{Name: util.Fields.Record.Value, Required: true, Min: 1, Max: 100},
			&core.TextField{Name: util.Fields.Record.Label, Required: true, Min: 1, Max: 100},
			&core.SelectField{Name: util.Fields.Record.Type, Required: true, Values: util.RecordTypes, MaxSelect: 1},
			&core.SelectField{Name: util.Fields.Record.Format, Required: true, Values: util.RecordFormats, MaxSelect: 1},

			&core.AutodateField{Name: util.Fields.Record.Created, OnCreate: true},
			&core.AutodateField{Name: util.Fields.Record.Updated, OnCreate: true, OnUpdate: true},
			&core.RelationField{
				Name:         util.Fields.Record.User,
				CollectionId: users.Id,
				Required:     true,
				MaxSelect:    1,
			},
			&core.RelationField{
				Name:         util.Fields.Record.Workspace,
				CollectionId: workspaces.Id,
				Required:     true,
				MaxSelect:    1,
			},
		)
		records.AddIndex("idxRecordsKeyUserWorkspace", true, strings.Join([]string{
			util.Fields.Record.Workspace,
			util.Fields.Record.Key,
			util.Fields.Record.User,
		}, ","), "")

		records.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRecordRead))
		records.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRecordRead))
		records.UpdateRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRecordUpdate))
		records.DeleteRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRecordDelete))
		records.CreateRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRecordCreate))

		if err := app.Save(records); err != nil {
			return err
		}

		return nil

	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return nil
		}

		if err := app.Delete(col); err != nil {
			return err
		}

		return nil
	})
}
