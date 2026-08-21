package migrations

import (
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

func init() {
	migrations.Register(func(app core.App) error {
		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return nil
		}

		if records.Fields.GetByName(util.Fields.Record.Filename) == nil {
			records.Fields.Add(&core.TextField{
				Name: util.Fields.Record.Filename,
				Max:  255,
			})
			if err := app.Save(records); err != nil {
				return err
			}
		}

		// Rows written before this field existed only have the storage name,
		// which is snakecased and suffixed. It is a worse name than the one the
		// uploader chose, but it is the only one left.
		_, err = app.DB().NewQuery(
			"UPDATE " + util.Coll.Records +
				" SET filename = file WHERE type = {:t} AND (filename IS NULL OR filename = '')",
		).Bind(dbx.Params{"t": util.TypeFile}).Execute()
		return err
	}, func(app core.App) error {
		return nil
	})
}
