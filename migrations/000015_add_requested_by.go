package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds a nullable `requestedBy` to records and sections, naming the requestor whose
// fulfilled request created the row so the owner can trace where the data came from.
func init() {
	migrations.Register(func(app core.App) error {
		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}
		if recordsCol.Fields.GetByName(util.Fields.Record.RequestedBy) == nil {
			recordsCol.Fields.Add(&core.TextField{
				Name:     util.Fields.Record.RequestedBy,
				Required: false,
				Max:      200,
			})
			if err := app.Save(recordsCol); err != nil {
				return err
			}
		}

		sectionsCol, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err != nil {
			return err
		}
		if sectionsCol.Fields.GetByName(util.Fields.Section.RequestedBy) == nil {
			sectionsCol.Fields.Add(&core.TextField{
				Name:     util.Fields.Section.RequestedBy,
				Required: false,
				Max:      200,
			})
			if err := app.Save(sectionsCol); err != nil {
				return err
			}
		}

		return nil
	}, func(app core.App) error {
		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err == nil {
			recordsCol.Fields.RemoveByName(util.Fields.Record.RequestedBy)
			_ = app.Save(recordsCol)
		}

		sectionsCol, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err == nil {
			sectionsCol.Fields.RemoveByName(util.Fields.Section.RequestedBy)
			_ = app.Save(sectionsCol)
		}

		return nil
	})
}
