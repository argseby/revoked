package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

func init() {
	migrations.Register(func(app core.App) error {
		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return nil
		}

		// A file record's value lives in the file, so the text column can no
		// longer be required; the record hook enforces it per type instead.
		if f, ok := records.Fields.GetByName(util.Fields.Record.Value).(*core.TextField); ok {
			f.Required = false
			f.Min = 0
		}

		if f, ok := records.Fields.GetByName(util.Fields.Record.Type).(*core.SelectField); ok {
			f.Values = util.RecordTypes
		}

		if records.Fields.GetByName(util.Fields.Record.File) == nil {
			records.Fields.Add(&core.FileField{
				Name:      util.Fields.Record.File,
				MaxSelect: 1,
				// Permissive on purpose: the operator's FILE_MAX_SIZE policy is
				// enforced by the record hook at request time, and PocketBase
				// derives the route's body limit from this value — capping it
				// here would silently cap every deployment.
				MaxSize:   1 << 50,
				Protected: true,
			})
		}

		if records.Fields.GetByName(util.Fields.Record.ContentHash) == nil {
			records.Fields.Add(&core.TextField{Name: util.Fields.Record.ContentHash, Max: 64})
		}
		if records.Fields.GetByName(util.Fields.Record.HashSalt) == nil {
			records.Fields.Add(&core.TextField{Name: util.Fields.Record.HashSalt, Max: 64})
		}
		if records.Fields.GetByName(util.Fields.Record.Mime) == nil {
			records.Fields.Add(&core.TextField{Name: util.Fields.Record.Mime, Max: 255})
		}
		if records.Fields.GetByName(util.Fields.Record.Size) == nil {
			records.Fields.Add(&core.NumberField{Name: util.Fields.Record.Size, OnlyInt: true})
		}

		return app.Save(records)
	}, func(app core.App) error {
		return nil
	})
}
