package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds `publicKey` to identities: the client generates the keypair locally and submits
// only the PEM public half, so the server can issue a certificate without ever seeing
// the private key.
func init() {
	migrations.Register(func(app core.App) error {
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return err
		}
		if identities.Fields.GetByName(util.Fields.Identity.PublicKey) == nil {
			identities.Fields.Add(&core.TextField{
				Name:     util.Fields.Identity.PublicKey,
				Required: false,
				Max:      10000,
			})
			if err := app.Save(identities); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err == nil {
			identities.Fields.RemoveByName(util.Fields.Identity.PublicKey)
			_ = app.Save(identities)
		}
		return nil
	})
}
