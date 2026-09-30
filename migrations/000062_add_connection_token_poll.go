package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds connectionTokens.poll — whether the page that asked collects the
// answer itself, with its verifier, instead of being handed a code in its
// return address. Codes issued before the field existed stay codes.
func init() {
	migrations.Register(func(app core.App) error {
		tokens, err := app.FindCollectionByNameOrId(util.Coll.ConnectionTokens)
		if err != nil {
			return err
		}
		if tokens.Fields.GetByName(util.Fields.ConnectionToken.Poll) != nil {
			return nil
		}
		tokens.Fields.Add(&core.BoolField{Name: util.Fields.ConnectionToken.Poll})
		return app.Save(tokens)
	}, func(app core.App) error {
		tokens, err := app.FindCollectionByNameOrId(util.Coll.ConnectionTokens)
		if err != nil {
			return nil
		}
		tokens.Fields.RemoveByName(util.Fields.ConnectionToken.Poll)
		return app.Save(tokens)
	})
}
