package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Lets a connected tool propose requests, attestations and attestation checks,
// as it already proposes links. Each gains the connection it came from
// (cleared, not cascaded, on disconnect: the owner's rows outlive the tool),
// the tool's own ref, and proposedBy, which keeps the tool's origin after the
// connection is gone. Requests also gain heldPaused, so pausing the tool holds
// its requests the way it holds its links.
func init() {
	migrations.Register(func(app core.App) error {
		connections, err := app.FindCollectionByNameOrId(util.Coll.Connections)
		if err != nil {
			return err
		}
		for _, target := range []struct {
			coll                        string
			connection, ref, proposedBy string
			heldPaused                  string
		}{
			{util.Coll.Requests, util.Fields.Request.Connection, util.Fields.Request.Ref,
				util.Fields.Request.ProposedBy, util.Fields.Request.HeldPaused},
			{util.Coll.Attestations, util.Fields.Attestation.Connection, util.Fields.Attestation.Ref,
				util.Fields.Attestation.ProposedBy, ""},
			{util.Coll.AttestationChecks, util.Fields.AttestationCheck.Connection, util.Fields.AttestationCheck.Ref,
				util.Fields.AttestationCheck.ProposedBy, ""},
		} {
			c, err := app.FindCollectionByNameOrId(target.coll)
			if err != nil {
				return err
			}
			if c.Fields.GetByName(target.connection) != nil {
				continue
			}
			c.Fields.Add(
				&core.RelationField{Name: target.connection, CollectionId: connections.Id, MaxSelect: 1},
				&core.TextField{Name: target.ref, Max: 80},
				&core.TextField{Name: target.proposedBy, Max: 255},
			)
			if target.heldPaused != "" {
				c.Fields.Add(&core.BoolField{Name: target.heldPaused})
			}
			if err := app.Save(c); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		for _, coll := range []string{util.Coll.Requests, util.Coll.Attestations, util.Coll.AttestationChecks} {
			c, err := app.FindCollectionByNameOrId(coll)
			if err != nil {
				continue
			}
			for _, name := range []string{"connection", "ref", "proposedBy", "heldPaused"} {
				c.Fields.RemoveByName(name)
			}
			if err := app.Save(c); err != nil {
				return err
			}
		}
		return nil
	})
}
