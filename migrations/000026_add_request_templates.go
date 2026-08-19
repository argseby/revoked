package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds `allowExtraFields` to requests, letting the creator accept ad-hoc fields
// outside the template. An earlier revision of this file also created the
// requestTemplateRecords / requestTemplateSections join collections; 000027 drops them.
func init() {
	migrations.Register(func(app core.App) error {
		requestsCol, err := app.FindCollectionByNameOrId(util.Coll.Requests)
		if err != nil {
			return err
		}
		if requestsCol.Fields.GetByName(util.Fields.Request.AllowExtraFields) == nil {
			requestsCol.Fields.Add(&core.BoolField{
				Name: util.Fields.Request.AllowExtraFields,
			})
			if err := app.Save(requestsCol); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		if requestsCol, err := app.FindCollectionByNameOrId(util.Coll.Requests); err == nil {
			requestsCol.Fields.RemoveByName(util.Fields.Request.AllowExtraFields)
			_ = app.Save(requestsCol)
		}
		return nil
	})
}
