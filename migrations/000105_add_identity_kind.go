package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Names what made an identity's key: empty for a key a device generated,
// "passkey" for one a browser derives from a passkey and never stores
// (BROWSER.md §4.8). Set at creation and fixed after.
func init() {
	migrations.Register(func(app core.App) error {
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return err
		}
		f := util.Fields.Identity
		if identities.Fields.GetByName(f.Kind) != nil {
			return nil
		}
		identities.Fields.Add(&core.TextField{Name: f.Kind, Max: 20})
		return app.Save(identities)
	}, func(app core.App) error {
		return nil
	})
}
