package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds the notifications collection: server-emitted events (callback delivered, link
// expired, max views reached, new response) that only the owning user can read and
// mark read; the system is the sole creator.
func init() {
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		workspaces, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return err
		}

		notifications := core.NewBaseCollection(util.Coll.Notifications)
		notifications.Fields.Add(
			&core.RelationField{
				Name:          util.Fields.Notification.User,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.RelationField{
				Name:          util.Fields.Notification.Workspace,
				CollectionId:  workspaces.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.SelectField{
				Name:      util.Fields.Notification.Type,
				Required:  true,
				Values:    util.NotificationTypes,
				MaxSelect: 1,
			},
			&core.TextField{
				Name:     util.Fields.Notification.Title,
				Required: true,
				Max:      200,
			},
			&core.TextField{
				Name: util.Fields.Notification.Message,
				Max:  2000,
			},
			&core.TextField{
				Name: util.Fields.Notification.RefCollection,
				Max:  100,
			},
			&core.TextField{
				Name: util.Fields.Notification.RefId,
				Max:  100,
			},
			&core.BoolField{Name: util.Fields.Notification.Read},
			&core.AutodateField{Name: util.Fields.Notification.Created, OnCreate: true},
		)
		notifications.AddIndex("idxNotificationsUserCreated", false,
			util.Fields.Notification.User+","+util.Fields.Notification.Created, "")

		notifications.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeNotificationRead))
		notifications.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeNotificationRead))
		notifications.UpdateRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeNotificationUpdate))
		notifications.DeleteRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeNotificationDelete))
		notifications.CreateRule = nil

		return app.Save(notifications)
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId(util.Coll.Notifications)
		if err != nil {
			return nil
		}
		return app.Delete(col)
	})
}
