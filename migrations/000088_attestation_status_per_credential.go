package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// An attestation can be moved to its subject's new identity: the credential it
// was issued as is revoked, and the one issued in its place stands at a fresh
// position, so a verifier cannot link the two. One attestation therefore holds
// a position per credential it was issued as, and the index on attestation is
// no longer unique. Positions themselves stay unique.
func init() {
	migrations.Register(func(app core.App) error {
		status, err := app.FindCollectionByNameOrId(util.Coll.AttestationStatus)
		if err != nil {
			return err
		}
		status.AddIndex("idxAttestationStatusAttestation", false, util.Fields.AttestationStatus.Attestation, "")
		return app.Save(status)
	}, func(app core.App) error {
		return nil
	})
}
