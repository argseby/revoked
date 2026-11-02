package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// A passkey can hold an encryption key (E2EE.md §6.8). Its device list entry
// names the credential it derives from; the anchor signature covers the name.
func init() {
	migrations.Register(func(app core.App) error {
		devices, err := app.FindCollectionByNameOrId(util.Coll.DeviceKeys)
		if err != nil {
			return err
		}
		devices.Fields.Add(&core.TextField{Name: util.Fields.DeviceKey.CredentialId, Max: 1400})
		return app.Save(devices)
	}, func(app core.App) error {
		devices, err := app.FindCollectionByNameOrId(util.Coll.DeviceKeys)
		if err != nil {
			return err
		}
		devices.Fields.RemoveByName(util.Fields.DeviceKey.CredentialId)
		return app.Save(devices)
	})
}
