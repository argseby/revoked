package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Lets the delivery outbox carry a grant by email.
//
// Two selects are re-applied because each was snapshotted when it was created:
// `grantDeliveries.kind` by `000065` and `notifications.type` by `000022`. The
// new values are inert in the database until this runs.
//
// The index is what makes the per-address cap exact. That cap protects a
// stranger's inbox, so it must not live in an in-process rate limiter — two
// instances behind a load balancer would give it twice the budget. Counting
// the outbox rows instead is shared by every instance, and this index is what
// keeps that count cheap.
func init() {
	migrations.Register(func(app core.App) error {
		deliveries, err := app.FindCollectionByNameOrId(util.Coll.GrantDeliveries)
		if err != nil {
			return err
		}
		if kind, ok := deliveries.Fields.GetByName(util.Fields.GrantDelivery.Kind).(*core.SelectField); ok {
			kind.Values = util.DeliveryKinds
		}
		d := util.Fields.GrantDelivery
		deliveries.AddIndex("idxGrantDeliveriesEmailTarget", false,
			d.Kind+", "+d.Target+", "+d.Created, "")
		if err := app.Save(deliveries); err != nil {
			return err
		}

		notifications, err := app.FindCollectionByNameOrId(util.Coll.Notifications)
		if err != nil {
			return err
		}
		if typeField, ok := notifications.Fields.GetByName(util.Fields.Notification.Type).(*core.SelectField); ok {
			typeField.Values = util.NotificationTypes
		}
		return app.Save(notifications)
	}, func(app core.App) error {
		deliveries, err := app.FindCollectionByNameOrId(util.Coll.GrantDeliveries)
		if err != nil {
			return nil
		}
		deliveries.RemoveIndex("idxGrantDeliveriesEmailTarget")
		return app.Save(deliveries)
	})
}
