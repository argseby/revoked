package migrations

import (
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds revocation state to identities. A certificate is minted for ten years and
// its parentSignature never expires, so without a status a holder keeps proving
// membership of a workspace they were removed from. Existing rows are backfilled
// to active — they were issued under the old, unrevocable regime.
func init() {
	migrations.Register(func(app core.App) error {
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return err
		}

		if identities.Fields.GetByName(util.Fields.Identity.Status) == nil {
			identities.Fields.Add(&core.SelectField{
				Name:      util.Fields.Identity.Status,
				Required:  false,
				Values:    util.IdentityStatuses,
				MaxSelect: 1,
			})
		}
		if identities.Fields.GetByName(util.Fields.Identity.RevokedAt) == nil {
			identities.Fields.Add(&core.DateField{
				Name: util.Fields.Identity.RevokedAt,
			})
		}
		if identities.Fields.GetByName(util.Fields.Identity.RevokedReason) == nil {
			identities.Fields.Add(&core.SelectField{
				Name:      util.Fields.Identity.RevokedReason,
				Required:  false,
				Values:    util.RevocationReasons,
				MaxSelect: 1,
			})
		}

		if err := app.Save(identities); err != nil {
			return err
		}

		_, err = app.DB().
			Update(
				util.Coll.Identities,
				dbx.Params{util.Fields.Identity.Status: util.StatusActive},
				dbx.NewExp(util.Fields.Identity.Status+" = '' OR "+util.Fields.Identity.Status+" IS NULL"),
			).
			Execute()
		return err
	}, func(app core.App) error {
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return nil
		}
		identities.Fields.RemoveByName(util.Fields.Identity.Status)
		identities.Fields.RemoveByName(util.Fields.Identity.RevokedAt)
		identities.Fields.RemoveByName(util.Fields.Identity.RevokedReason)
		_ = app.Save(identities)
		return nil
	})
}
