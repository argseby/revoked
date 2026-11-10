package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"revoked/util"
	"slices"
)

func init() {
	migrations.Register(func(app core.App) error {
		col, err := app.FindCollectionByNameOrId(util.Coll.Notifications)
		if err != nil {
			return err
		}
		field := col.Fields.GetByName(util.Fields.Notification.Type).(*core.SelectField)
		if !slices.Contains(field.Values, util.NotificationSealedLinkChanged) {
			field.Values = append(field.Values, util.NotificationSealedLinkChanged)
		}
		return app.Save(col)
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId(util.Coll.Notifications)
		if err != nil {
			return err
		}
		field := col.Fields.GetByName(util.Fields.Notification.Type).(*core.SelectField)
		field.Values = slices.DeleteFunc(field.Values, func(s string) bool { return s == util.NotificationSealedLinkChanged })
		return app.Save(col)
	})
}
