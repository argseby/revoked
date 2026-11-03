package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds connections.allowVaultRead: whether the owner lets a tool read the
// values in their vault. Existing connections start without it.
func init() {
	migrations.Register(func(app core.App) error {
		connections, err := app.FindCollectionByNameOrId(util.Coll.Connections)
		if err != nil {
			return err
		}
		if connections.Fields.GetByName(util.Fields.Connection.AllowVaultRead) != nil {
			return nil
		}
		connections.Fields.Add(&core.BoolField{Name: util.Fields.Connection.AllowVaultRead})
		return app.Save(connections)
	}, func(app core.App) error {
		return nil
	})
}
