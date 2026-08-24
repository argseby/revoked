package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Widens the record `type` select to the whole catalogue the client offers.
// The app has always been able to author a url, boolean or datetime record —
// the collection only accepted text, number and file, so those saves were
// refused with a bare validation error.
func init() {
	migrations.Register(func(app core.App) error {
		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return nil
		}

		f, ok := records.Fields.GetByName(util.Fields.Record.Type).(*core.SelectField)
		if !ok {
			return nil
		}
		f.Values = util.RecordTypes

		return app.Save(records)
	}, func(app core.App) error {
		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return nil
		}

		f, ok := records.Fields.GetByName(util.Fields.Record.Type).(*core.SelectField)
		if !ok {
			return nil
		}
		f.Values = []string{util.TypeText, util.TypeNumber, util.TypeFile}

		return app.Save(records)
	})
}
