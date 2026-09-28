package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds links.purpose, which marks a share as a rental application, and widens
// notifications.type to the current list: 000022 snapshotted the list it was
// created with, so an existing database would reject link_opened.
func init() {
	migrations.Register(func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}
		if links.Fields.GetByName(util.Fields.Link.Purpose) == nil {
			links.Fields.Add(&core.SelectField{
				Name:      util.Fields.Link.Purpose,
				Values:    util.LinkPurposes,
				MaxSelect: 1,
			})
			if err := app.Save(links); err != nil {
				return err
			}
		}

		notifications, err := app.FindCollectionByNameOrId(util.Coll.Notifications)
		if err != nil {
			return err
		}
		typeField, ok := notifications.Fields.GetByName(util.Fields.Notification.Type).(*core.SelectField)
		if !ok {
			return nil
		}
		typeField.Values = util.NotificationTypes
		return app.Save(notifications)
	}, func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return nil
		}
		links.Fields.RemoveByName(util.Fields.Link.Purpose)
		return app.Save(links)
	})
}
