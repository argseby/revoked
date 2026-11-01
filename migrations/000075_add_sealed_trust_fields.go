package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds what lets a client check a device list and its keys for itself.
//
// chainSeq is how far the list had got when a key was handed over: a removal
// later than that means a removed device may know the key, which a client can
// see without trusting the server's rotationDue flag. anchorSignature is the
// recovery key's signature over the list's root: its public key alone proves
// nothing, because anyone can copy it into a list of their own.
func init() {
	migrations.Register(func(app core.App) error {
		devices, err := app.FindCollectionByNameOrId(util.Coll.DeviceKeys)
		if err != nil {
			return err
		}
		devices.Fields.Add(&core.TextField{Name: util.Fields.DeviceKey.AnchorSignature, Max: 128})
		if err := app.Save(devices); err != nil {
			return err
		}

		wraps, err := app.FindCollectionByNameOrId(util.Coll.WorkspaceKeyWraps)
		if err != nil {
			return err
		}
		wraps.Fields.Add(&core.NumberField{Name: util.Fields.WorkspaceKeyWrap.ChainSeq, OnlyInt: true})
		if err := app.Save(wraps); err != nil {
			return err
		}

		// Snapshotted by 000022, so a new notification type is inert until re-applied.
		notifications, err := app.FindCollectionByNameOrId(util.Coll.Notifications)
		if err != nil {
			return err
		}
		if typeField, ok := notifications.Fields.GetByName(util.Fields.Notification.Type).(*core.SelectField); ok {
			typeField.Values = util.NotificationTypes
		}
		return app.Save(notifications)
	}, func(app core.App) error {
		devices, err := app.FindCollectionByNameOrId(util.Coll.DeviceKeys)
		if err != nil {
			return err
		}
		devices.Fields.RemoveByName(util.Fields.DeviceKey.AnchorSignature)
		if err := app.Save(devices); err != nil {
			return err
		}
		wraps, err := app.FindCollectionByNameOrId(util.Coll.WorkspaceKeyWraps)
		if err != nil {
			return err
		}
		wraps.Fields.RemoveByName(util.Fields.WorkspaceKeyWrap.ChainSeq)
		return app.Save(wraps)
	})
}
