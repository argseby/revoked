package services

import (
	"time"

	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// reminderBatch bounds one scheduler pass; whatever is left is picked up on
// the next tick.
const reminderBatch = 500

// FireDueReminders delivers every date reminder whose time has come.
func FireDueReminders(app core.App, now time.Time) {
	at, err := types.ParseDateTime(now)
	if err != nil {
		return
	}
	due, err := app.FindRecordsByFilter(util.Coll.Reminders,
		util.Fields.Reminder.Kind+" = {:kind} && "+
			util.Fields.Reminder.FiredAt+" = '' && "+
			util.Fields.Reminder.DueAt+" != '' && "+
			util.Fields.Reminder.DueAt+" <= {:now}",
		util.Fields.Reminder.DueAt, reminderBatch, 0,
		dbx.Params{"kind": util.ReminderKindDate, "now": at.String()})
	if err != nil {
		app.Logger().Error("Failed to load due reminders", "error", err)
		return
	}
	for _, reminder := range due {
		fireReminder(app, reminder, "", "You asked to be reminded about this entry today.")
	}
}

// FireChangeReminders delivers the change reminders watching an entry that
// just changed. An alias reads through its parent, so a change to the parent
// is a change to every alias of it too.
func FireChangeReminders(app core.App, changed *core.Record) {
	watched := []any{changed.Id}
	aliases, err := app.FindAllRecords(util.Coll.Records,
		dbx.HashExp{util.Fields.Record.AliasOf: changed.Id})
	if err == nil {
		for _, a := range aliases {
			watched = append(watched, a.Id)
		}
	}
	reminders, err := app.FindAllRecords(util.Coll.Reminders,
		dbx.HashExp{
			util.Fields.Reminder.Kind:    util.ReminderKindChange,
			util.Fields.Reminder.FiredAt: "",
		},
		dbx.In(util.Fields.Reminder.Watch, watched...))
	if err != nil {
		app.Logger().Error("Failed to load change reminders", "error", err, "record", changed.Id)
		return
	}
	for _, reminder := range reminders {
		fireReminder(app, reminder, reminder.GetString(util.Fields.Reminder.Watch), "")
	}
}

// fireReminder marks a reminder fired and notifies its owner. The mark is a
// guarded update, so a reminder fires once even if two passes reach it.
//
// The notification names entries but never carries a value: a hidden one
// would otherwise sit in plain sight in the notification list.
func fireReminder(app core.App, reminder *core.Record, watchedId, why string) {
	userId := reminder.GetString(util.Fields.Reminder.User)
	workspaceId := reminder.GetString(util.Fields.Reminder.Workspace)

	res, err := app.DB().NewQuery(
		"UPDATE {{" + util.Coll.Reminders + "}} SET [[" + util.Fields.Reminder.FiredAt + "]] = {:now} " +
			"WHERE [[id]] = {:id} AND [[" + util.Fields.Reminder.FiredAt + "]] = ''").
		Bind(dbx.Params{"now": types.NowDateTime().String(), "id": reminder.Id}).Execute()
	if err != nil {
		app.Logger().Error("Failed to mark a reminder fired", "error", err, "reminder", reminder.Id)
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return
	}

	// Someone who left the workspace no longer hears about its entries.
	if _, ok := util.WorkspaceMemberOf(app, workspaceId, userId); !ok {
		return
	}
	entry, err := app.FindRecordById(util.Coll.Records, reminder.GetString(util.Fields.Reminder.Record))
	if err != nil {
		return
	}

	message := why
	if watchedId != "" {
		name := RecordName(entry)
		if watchedId != entry.Id {
			if watched, err := app.FindRecordById(util.Coll.Records, watchedId); err == nil {
				name = RecordName(watched)
			}
		}
		message = "“" + name + "” changed."
	}
	if note := reminder.GetString(util.Fields.Reminder.Note); note != "" {
		message = note + "\n" + message
	}
	title := "Reminder: " + RecordName(entry)
	if r := []rune(title); len(r) > 200 {
		title = string(r[:199]) + "…"
	}
	EmitNotification(app, userId, workspaceId, util.NotificationReminder,
		title, message, util.Coll.Records, entry.Id)
}

// RecordName is what a person calls a vault entry: its label, else its key.
func RecordName(record *core.Record) string {
	if label := record.GetString(util.Fields.Record.Label); label != "" {
		return label
	}
	return record.GetString(util.Fields.Record.Key)
}
