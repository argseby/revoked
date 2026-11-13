package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds a section's view: a JSON layout that shows the section's records as
// the one thing they describe — a Wi-Fi card, an emergency card — instead of
// a list. The records stay as they are; the view only reads them, by key.
//
// JSON rather than text so it is stored and returned as a value, and capped
// because a layout never needs to be large.
func init() {
	migrations.Register(func(app core.App) error {
		sections, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err != nil {
			return err
		}
		if sections.Fields.GetByName(util.Fields.Section.View) != nil {
			return nil
		}
		sections.Fields.Add(&core.JSONField{
			Name:    util.Fields.Section.View,
			MaxSize: util.MaxSectionViewBytes,
		})
		return app.Save(sections)
	}, func(app core.App) error {
		sections, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err != nil {
			return err
		}
		sections.Fields.RemoveByName(util.Fields.Section.View)
		return app.Save(sections)
	})
}
