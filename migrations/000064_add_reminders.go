package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds reminders: a person's note to self about a vault entry, delivered as a
// notification. A reminder fires once — at dueAt (kind "date"), or the first
// time the entry it watches changes (kind "change"; watch defaults to the
// entry itself) — and firedAt records that it did. Clearing firedAt arms it
// again.
//
// Personal, like bookmarks: only its owner reads or writes it. The workspace
// is not the client's to pick — the hooks copy it from the entry, and refuse
// an entry in a workspace the owner is not a member of. Removing the entry,
// the watched entry, the workspace or the account removes the reminder.
//
// Also widens notifications.type to the current list, which now has reminder.
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
		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}

		reminders := core.NewBaseCollection(util.Coll.Reminders)
		reminders.Fields.Add(
			&core.RelationField{
				Name:          util.Fields.Reminder.User,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			// Set by the hooks from the entry; never what the client sent.
			&core.RelationField{
				Name:          util.Fields.Reminder.Workspace,
				CollectionId:  workspaces.Id,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.RelationField{
				Name:          util.Fields.Reminder.Record,
				CollectionId:  records.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.SelectField{
				Name:      util.Fields.Reminder.Kind,
				Required:  true,
				Values:    util.ReminderKinds,
				MaxSelect: 1,
			},
			&core.DateField{Name: util.Fields.Reminder.DueAt},
			&core.RelationField{
				Name:          util.Fields.Reminder.Watch,
				CollectionId:  records.Id,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.TextField{Name: util.Fields.Reminder.Note, Max: 500},
			&core.DateField{Name: util.Fields.Reminder.FiredAt},
			&core.AutodateField{Name: util.Fields.Reminder.Created, OnCreate: true},
			&core.AutodateField{Name: util.Fields.Reminder.Updated, OnCreate: true, OnUpdate: true},
		)
		// The scheduler's scan, and the change hook's lookup.
		reminders.AddIndex("idxRemindersDue", false,
			util.Fields.Reminder.Kind+", "+util.Fields.Reminder.FiredAt+", "+util.Fields.Reminder.DueAt, "")
		reminders.AddIndex("idxRemindersWatch", false, util.Fields.Reminder.Watch, "")
		reminders.AddIndex("idxRemindersUserRecord", false,
			util.Fields.Reminder.User+", "+util.Fields.Reminder.Record, "")

		owner := util.AccessSpec{Kind: util.AccessUserSelf}
		update := util.AccessSpec{Kind: util.AccessUserSelf, Extra: util.OwnerImmutable}
		reminders.ListRule = types.Pointer(owner.Rule())
		reminders.ViewRule = types.Pointer(owner.Rule())
		reminders.CreateRule = types.Pointer(owner.Rule())
		reminders.UpdateRule = types.Pointer(update.Rule())
		reminders.DeleteRule = types.Pointer(owner.Rule())
		if err := app.Save(reminders); err != nil {
			return err
		}

		notifications, err := app.FindCollectionByNameOrId(util.Coll.Notifications)
		if err != nil {
			return err
		}
		typeField, ok := notifications.Fields.GetByName(util.Fields.Notification.Type).(*core.SelectField)
		if !ok {
			return nil
		}
		typeField.Values = util.NotificationTypes
		return app.Save(notifications)
	}, func(app core.App) error {
		reminders, err := app.FindCollectionByNameOrId(util.Coll.Reminders)
		if err != nil {
			return nil
		}
		return app.Delete(reminders)
	})
}
