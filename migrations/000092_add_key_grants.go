package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Lets a member hand a workspace key to another member's devices
// (design/e2ee-sharing.md §2.5). A copy names who granted it; its chainSeq is
// then the granter's list and recipientChainSeq the recipient's. Also teaches
// the notifications collection the new type, which 000022 snapshotted.
func init() {
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		wraps, err := app.FindCollectionByNameOrId(util.Coll.WorkspaceKeyWraps)
		if err != nil {
			return err
		}
		w := util.Fields.WorkspaceKeyWrap
		if wraps.Fields.GetByName(w.Granter) == nil {
			wraps.Fields.Add(
				&core.RelationField{
					Name:          w.Granter,
					CollectionId:  users.Id,
					MaxSelect:     1,
					CascadeDelete: false,
				},
				&core.NumberField{Name: w.RecipientChainSeq, OnlyInt: true},
			)
		}
		if err := app.Save(wraps); err != nil {
			return err
		}

		notifications, err := app.FindCollectionByNameOrId(util.Coll.Notifications)
		if err != nil {
			return err
		}
		if typeField, ok := notifications.Fields.GetByName(util.Fields.Notification.Type).(*core.SelectField); ok {
			typeField.Values = util.NotificationTypes
		}
		return app.Save(notifications)
	}, func(app core.App) error {
		wraps, err := app.FindCollectionByNameOrId(util.Coll.WorkspaceKeyWraps)
		if err != nil {
			return err
		}
		wraps.Fields.RemoveByName(util.Fields.WorkspaceKeyWrap.Granter)
		wraps.Fields.RemoveByName(util.Fields.WorkspaceKeyWrap.RecipientChainSeq)
		return app.Save(wraps)
	})
}
