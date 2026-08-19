package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Binds an identity to its issuing server: `parentSignature` is the root key's
// signature over the certificate fingerprint and `domainAtIssue` pins $DOMAIN at
// creation so a later rotation cannot re-frame old identities. Both optional, so
// pre-existing identities survive and simply read as unverified until re-issued.
func init() {
	migrations.Register(func(app core.App) error {
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return err
		}

		identities.Fields.Add(
			&core.TextField{
				Name:     util.Fields.Identity.ParentSignature,
				Required: false,
				// 1024 hex chars for an RSA-2048 signature, plus headroom.
				Max: 2048,
			},
			&core.TextField{
				Name:     util.Fields.Identity.DomainAtIssue,
				Required: false,
				// RFC 1035 caps domain names at 253 characters.
				Max: 253,
			},
		)

		return app.Save(identities)
	}, func(app core.App) error {
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return nil
		}
		for _, name := range []string{
			util.Fields.Identity.ParentSignature,
			util.Fields.Identity.DomainAtIssue,
		} {
			if f := identities.Fields.GetByName(name); f != nil {
				identities.Fields.RemoveByName(name)
			}
		}
		return app.Save(identities)
	})
}
