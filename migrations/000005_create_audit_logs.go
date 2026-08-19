package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

func init() {
	migrations.Register(func(app core.App) error {
		collection := core.NewBaseCollection(util.Coll.AuditLogs)

		users, _ := app.FindCollectionByNameOrId(util.Coll.Users)
		workspaces, _ := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		apiKeys, _ := app.FindCollectionByNameOrId(util.Coll.ApiKeys)

		collection.Fields.Add(
			&core.RelationField{
				Name:         util.Fields.AuditLog.User,
				CollectionId: users.Id,
				MaxSelect:    1,
			},
			&core.TextField{
				Name:     util.Fields.AuditLog.Action,
				Required: true,
			},
			&core.TextField{
				Name:     util.Fields.AuditLog.Collection,
				Required: true,
			},
			&core.TextField{
				Name:     util.Fields.AuditLog.RecordId,
				Required: true,
			},
			&core.JSONField{
				Name: util.Fields.AuditLog.OldData,
			},
			&core.JSONField{
				Name: util.Fields.AuditLog.NewData,
			},
			&core.TextField{
				Name: util.Fields.AuditLog.Ip,
			},
			&core.TextField{
				Name: util.Fields.AuditLog.UserAgent,
			},
			&core.RelationField{
				Name:         util.Fields.AuditLog.Workspace,
				CollectionId: workspaces.Id,
				MaxSelect:    1,
			},
			&core.RelationField{
				Name:         util.Fields.AuditLog.ApiKey,
				CollectionId: apiKeys.Id,
				MaxSelect:    1,
			},
			&core.AutodateField{
				Name:     "created",
				OnCreate: true,
			},
		)

		collection.ListRule = nil
		collection.ViewRule = nil
		collection.CreateRule = nil
		collection.UpdateRule = nil
		collection.DeleteRule = nil

		return app.Save(collection)
	}, func(app core.App) error {
		collection, err := app.FindCollectionByNameOrId(util.Coll.AuditLogs)
		if err != nil {
			return nil
		}
		return app.Delete(collection)
	})
}
