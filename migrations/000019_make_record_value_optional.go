package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Makes records.value optional so a blueprint or requested record can exist before
// anyone has filled it in.
func init() {
	migrations.Register(func(app core.App) error {
		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}

		recordsCol.Fields.Add(
			&core.TextField{
				Name:     util.Fields.Record.Value,
				Required: false,
				Max:      1000,
			},
		)

		if err := app.Save(recordsCol); err != nil {
			return err
		}

		return nil
	}, func(app core.App) error {
		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}

		recordsCol.Fields.Add(
			&core.TextField{
				Name:     util.Fields.Record.Value,
				Required: true,
				Min:      1,
				Max:      100,
			},
		)

		if err := app.Save(recordsCol); err != nil {
			return err
		}

		return nil
	})
}
