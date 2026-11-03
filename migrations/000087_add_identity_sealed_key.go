package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Lets an identity's private key follow its owner onto their other devices:
// sealedKey holds the key encrypted under the owner's workspace key of
// sealedKeyEpoch, written by the app and opened only by devices on the
// account's device list. The server stores ciphertext it cannot read; an
// account without end-to-end encryption leaves both fields empty and keeps
// each key on the device that made it.
func init() {
	migrations.Register(func(app core.App) error {
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return err
		}
		f := util.Fields.Identity
		if identities.Fields.GetByName(f.SealedKey) != nil {
			return nil
		}
		identities.Fields.Add(
			&core.TextField{Name: f.SealedKey, Max: 8192},
			&core.NumberField{Name: f.SealedKeyEpoch, OnlyInt: true},
		)
		return app.Save(identities)
	}, func(app core.App) error {
		return nil
	})
}
