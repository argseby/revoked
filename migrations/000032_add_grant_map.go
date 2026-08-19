package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds `grants`, a { templateKey: recordId } map on responses. The `records` relation
// from 000031 is not enough on its own: an aliased or auto-created record's own key can
// differ from the template key it answers, so the resolver needs the mapping explicitly.
func init() {
	migrations.Register(func(app core.App) error {
		responses, err := app.FindCollectionByNameOrId(util.Coll.RequestResponses)
		if err != nil {
			return err
		}
		responses.Fields.Add(&core.JSONField{Name: util.Fields.RequestResponse.Grants})
		return app.Save(responses)
	}, func(app core.App) error {
		responses, err := app.FindCollectionByNameOrId(util.Coll.RequestResponses)
		if err != nil {
			return nil
		}
		responses.Fields.RemoveByName(util.Fields.RequestResponse.Grants)
		return app.Save(responses)
	})
}
