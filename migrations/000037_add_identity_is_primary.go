package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds the `isPrimary` bool the identities hooks have always read and written to keep
// one primary identity per (user, workspace). No migration ever created the column, so
// GetBool always returned false and the uniqueness reset silently did nothing.
func init() {
	migrations.Register(func(app core.App) error {
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return err
		}
		if identities.Fields.GetByName(util.Fields.Identity.IsPrimary) == nil {
			identities.Fields.Add(&core.BoolField{
				Name: util.Fields.Identity.IsPrimary,
			})
			if err := app.Save(identities); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err == nil {
			identities.Fields.RemoveByName(util.Fields.Identity.IsPrimary)
			_ = app.Save(identities)
		}
		return nil
	})
}
