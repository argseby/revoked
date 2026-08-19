package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds `aliasOf` to records: an alias carries no `value` of its own and reads must
// resolve through the parent. Also constrains `key` to the slug pattern.
func init() {
	migrations.Register(func(app core.App) error {
		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}

		// Re-adding a field name replaces its definition; existing rows are not
		// re-validated, so only new writes are constrained.
		recordsCol.Fields.Add(&core.TextField{
			Name:     util.Fields.Record.Key,
			Required: true,
			Min:      1,
			Max:      100,
			Pattern:  util.SlugPattern,
		})

		if recordsCol.Fields.GetByName(util.Fields.Record.AliasOf) == nil {
			recordsCol.Fields.Add(&core.RelationField{
				Name:          util.Fields.Record.AliasOf,
				CollectionId:  recordsCol.Id,
				MaxSelect:     1,
				CascadeDelete: true,
			})
		}

		return app.Save(recordsCol)
	}, func(app core.App) error {
		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return nil
		}
		recordsCol.Fields.RemoveByName(util.Fields.Record.AliasOf)
		recordsCol.Fields.Add(&core.TextField{
			Name:     util.Fields.Record.Key,
			Required: true,
			Min:      1,
			Max:      100,
		})
		return app.Save(recordsCol)
	})
}
