package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Lets an API key carry an expiry. An empty value means the key never expires,
// which keeps every existing key working untouched.
func init() {
	migrations.Register(func(app core.App) error {
		keys, err := app.FindCollectionByNameOrId(util.Coll.ApiKeys)
		if err != nil {
			return err
		}
		if keys.Fields.GetByName(util.Fields.ApiKey.ExpiresAt) == nil {
			keys.Fields.Add(&core.DateField{Name: util.Fields.ApiKey.ExpiresAt})
		}
		return app.Save(keys)
	}, func(app core.App) error {
		keys, err := app.FindCollectionByNameOrId(util.Coll.ApiKeys)
		if err != nil {
			return nil
		}
		keys.Fields.RemoveByName(util.Fields.ApiKey.ExpiresAt)
		return app.Save(keys)
	})
}
