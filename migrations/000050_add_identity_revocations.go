package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds the identityRevocations tombstone: fingerprint, when, and why, kept after
// the identity row itself is gone.
//
// Without it a hard delete — closing an account, tearing down a workspace — would
// answer a status query with silence, and silence is indistinguishable from a
// restored backup or a fresh install on the same domain. A verifier cannot fail
// closed on an answer that ambiguous, so the tombstone is what lets "deleted"
// mean "revoked" instead of "unknown".
//
// Rules are nil throughout: this is read via GET /api/identities/{fp}/status,
// never through the record API, and nothing but the server ever writes it.
func init() {
	migrations.Register(func(app core.App) error {
		if existing, _ := app.FindCollectionByNameOrId(util.Coll.IdentityRevocations); existing != nil {
			return nil
		}

		revocations := core.NewBaseCollection(util.Coll.IdentityRevocations)
		revocations.Fields.Add(
			&core.TextField{
				Name:     util.Fields.IdentityRevocation.Fingerprint,
				Required: true,
				Min:      1,
				Max:      200,
			},
			&core.DateField{
				Name: util.Fields.IdentityRevocation.RevokedAt,
			},
			&core.SelectField{
				Name:      util.Fields.IdentityRevocation.Reason,
				Required:  false,
				Values:    util.RevocationReasons,
				MaxSelect: 1,
			},
			&core.TextField{
				Name:     util.Fields.IdentityRevocation.Domain,
				Required: false,
				Max:      253,
			},
			&core.AutodateField{Name: util.Fields.IdentityRevocation.Created, OnCreate: true},
		)
		revocations.AddIndex("idxIdentityRevocationFingerprint", true, util.Fields.IdentityRevocation.Fingerprint, "")

		return app.Save(revocations)
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId(util.Coll.IdentityRevocations)
		if err != nil {
			return nil
		}
		return app.Delete(col)
	})
}
