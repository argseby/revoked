package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds connections.allowRevoke — whether the owner lets a tool revoke the
// links its proposals became — to a database whose connections collection was
// created before the field existed. Existing connections start without it.
func init() {
	migrations.Register(func(app core.App) error {
		connections, err := app.FindCollectionByNameOrId(util.Coll.Connections)
		if err != nil {
			return err
		}
		if connections.Fields.GetByName(util.Fields.Connection.AllowRevoke) != nil {
			return nil
		}
		connections.Fields.Add(&core.BoolField{Name: util.Fields.Connection.AllowRevoke})
		return app.Save(connections)
	}, func(app core.App) error {
		return nil
	})
}
