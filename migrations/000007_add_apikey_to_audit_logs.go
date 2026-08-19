package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

func init() {
	migrations.Register(func(app core.App) error {
		auditLogs, err := app.FindCollectionByNameOrId(util.Coll.AuditLogs)
		if err != nil {
			return nil
		}

		apiKeys, err := app.FindCollectionByNameOrId(util.Coll.ApiKeys)
		if err != nil {
			return nil
		}

		if auditLogs.Fields.GetByName(util.Fields.AuditLog.ApiKey) == nil {
			auditLogs.Fields.Add(&core.RelationField{
				Name:         util.Fields.AuditLog.ApiKey,
				CollectionId: apiKeys.Id,
				MaxSelect:    1,
			})
		}

		return app.Save(auditLogs)
	}, func(app core.App) error {
		return nil
	})
}
