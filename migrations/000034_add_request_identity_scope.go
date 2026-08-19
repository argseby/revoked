package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds `identityScope` to requests, narrowing which identities may respond when
// requireHandshake is set: "any" accepts any cryptographic identity, "from_root" only
// those whose domainAtIssue matches this server's root. Absent is treated as "any".
func init() {
	migrations.Register(func(app core.App) error {
		requests, err := app.FindCollectionByNameOrId(util.Coll.Requests)
		if err != nil {
			return err
		}
		requests.Fields.Add(&core.SelectField{
			Name:      util.Fields.Request.IdentityScope,
			Required:  false,
			MaxSelect: 1,
			Values:    []string{"any", "from_root"},
		})
		return app.Save(requests)
	}, func(app core.App) error {
		requests, err := app.FindCollectionByNameOrId(util.Coll.Requests)
		if err != nil {
			return nil
		}
		if f := requests.Fields.GetByName(util.Fields.Request.IdentityScope); f != nil {
			requests.Fields.RemoveByName(util.Fields.Request.IdentityScope)
		}
		return app.Save(requests)
	})
}
