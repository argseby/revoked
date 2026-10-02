package hooks

import (
	"slices"
	"time"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// reminderCronId names the scheduler job, so a second Bind replaces it.
const reminderCronId = "revokedReminders"

// BindReminderHooks keeps reminders inside their owner's reach, fires change
// reminders when a watched entry changes, and schedules date reminders.
func BindReminderHooks(app core.App) {
	app.OnRecordCreate(util.Coll.Reminders).BindFunc(func(e *core.RecordEvent) error {
		if err := prepareReminder(e.App, e.Record, true); err != nil {
			return err
		}
		return e.Next()
	})
	app.OnRecordUpdate(util.Coll.Reminders).BindFunc(func(e *core.RecordEvent) error {
		if err := prepareReminder(e.App, e.Record, false); err != nil {
			return err
		}
		return e.Next()
	})

	// Fired from the save itself, with the app it ran in: inside a
	// transaction the notification commits or rolls back with the change.
	app.OnRecordUpdate(util.Coll.Records).BindFunc(func(e *core.RecordEvent) error {
		changed := recordContentChanged(e.Record)
		if err := e.Next(); err != nil {
			return err
		}
		if changed {
			services.FireChangeReminders(e.App, e.Record)
		}
		return nil
	})

	// Every minute: a reminder is a date, not a deadline, so a minute late is
	// on time.
	app.Cron().MustAdd(reminderCronId, "* * * * *", func() {
		services.FireDueReminders(app, time.Now())
	})
}

// recordContentChanged reports whether what an entry resolves to changed: its
// value, its file, or the parent an alias reads through. A rename is not a
// change of the data behind it.
func recordContentChanged(rec *core.Record) bool {
	original := rec.Original()
	for _, field := range []string{
		util.Fields.Record.Value,
		util.Fields.Record.ContentHash,
		util.Fields.Record.AliasOf,
	} {
		if rec.GetString(field) != original.GetString(field) {
			return true
		}
	}
	return false
}

// prepareReminder validates a reminder and fills in what the server decides:
// the workspace (the entry's), the watched entry (the entry itself, unless
// another was named), and whether it has fired.
//
// Relation validation only proves an id exists, and record ids travel in
// responses and links, so without the membership check a reminder could name
// an entry in a stranger's workspace and learn when it changes.
func prepareReminder(app core.App, rec *core.Record, creating bool) error {
	f := util.Fields.Reminder
	kind := rec.GetString(f.Kind)
	if !slices.Contains(util.ReminderKinds, kind) {
		return util.AsFieldValidationError(f.Kind, util.Errors.ReminderKindInvalid)
	}

	entry, err := app.FindRecordById(util.Coll.Records, rec.GetString(f.Record))
	if err != nil || entry == nil {
		return util.AsFieldValidationError(f.Record, util.Errors.ReminderRecordMissing)
	}
	workspaceId := entry.GetString(util.Fields.Record.Workspace)
	if _, ok := util.WorkspaceMemberOf(app, workspaceId, rec.GetString(f.User)); !ok {
		return util.AsFieldValidationError(f.Record, util.Errors.ReminderRecordMissing)
	}
	rec.Set(f.Workspace, workspaceId)

	switch kind {
	case util.ReminderKindDate:
		if rec.GetDateTime(f.DueAt).IsZero() {
			return util.AsFieldValidationError(f.DueAt, util.Errors.ReminderDueRequired)
		}
		rec.Set(f.Watch, "")
	case util.ReminderKindChange:
		rec.Set(f.DueAt, "")
		if rec.GetString(f.Watch) == "" {
			rec.Set(f.Watch, entry.Id)
		} else if rec.GetString(f.Watch) != entry.Id {
			watched, err := app.FindRecordById(util.Coll.Records, rec.GetString(f.Watch))
			if err != nil || watched == nil || watched.GetString(util.Fields.Record.Workspace) != workspaceId {
				return util.AsFieldValidationError(f.Watch, util.Errors.ReminderWatchMissing)
			}
		}
	}

	// firedAt is the server's to set. A client may only clear it, which arms
	// the reminder again; a changed condition is a new reminder and arms it
	// too.
	if creating {
		rec.Set(f.FiredAt, "")
		return nil
	}
	original := rec.Original()
	if fired := rec.GetString(f.FiredAt); fired != "" && fired != original.GetString(f.FiredAt) {
		rec.Set(f.FiredAt, original.GetString(f.FiredAt))
	}
	for _, field := range []string{f.Kind, f.DueAt, f.Watch, f.Record} {
		if rec.GetString(field) != original.GetString(field) {
			rec.Set(f.FiredAt, "")
			break
		}
	}
	return nil
}
