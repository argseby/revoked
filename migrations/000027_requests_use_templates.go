package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Replaces 000026's join collections with a direct `template` relation on requests.
// The template's `schema` JSON is the authoritative list of what a responder must
// fill in, including the per-entry `required` and `reason` metadata.
func init() {
	migrations.Register(func(app core.App) error {
		// Names are literals because the schema constants were deleted with them.
		for _, name := range []string{
			"requestTemplateSections",
			"requestTemplateRecords",
		} {
			if col, err := app.FindCollectionByNameOrId(name); err == nil && col != nil {
				if err := app.Delete(col); err != nil {
					return err
				}
			}
		}

		requestsCol, err := app.FindCollectionByNameOrId(util.Coll.Requests)
		if err != nil {
			return err
		}
		templatesCol, err := app.FindCollectionByNameOrId(util.Coll.Templates)
		if err != nil {
			return err
		}

		if requestsCol.Fields.GetByName(util.Fields.Request.Template) == nil {
			requestsCol.Fields.Add(&core.RelationField{
				Name:         util.Fields.Request.Template,
				CollectionId: templatesCol.Id,
				MaxSelect:    1,
			})
			if err := app.Save(requestsCol); err != nil {
				return err
			}
		}

		return nil
	}, func(app core.App) error {
		// The join collections are deliberately not recreated; re-running 000026 would.
		requestsCol, err := app.FindCollectionByNameOrId(util.Coll.Requests)
		if err == nil {
			requestsCol.Fields.RemoveByName(util.Fields.Request.Template)
			_ = app.Save(requestsCol)
		}
		return nil
	})
}
