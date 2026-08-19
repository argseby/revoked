package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

func init() {
	migrations.Register(func(app core.App) error {
		apiKeys, err := app.FindCollectionByNameOrId(util.Coll.ApiKeys)
		if err != nil {
			return nil
		}

		if apiKeys.Type == core.CollectionTypeAuth {
			apiKeys.Type = core.CollectionTypeBase
		}

		if apiKeys.Fields.GetByName(util.Fields.ApiKey.LastUsedAt) == nil {
			apiKeys.Fields.Add(&core.AutodateField{
				Name:     util.Fields.ApiKey.LastUsedAt,
				OnCreate: true,
			})
		}

		return app.Save(apiKeys)
	}, func(app core.App) error {
		return nil
	})
}
