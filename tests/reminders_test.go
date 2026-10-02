package tests

import (
	"net/http"
	"strings"
	"testing"
	"time"

	"revoked/cmd/revoked/services"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
	"github.com/google/uuid"
)

func reminderEntry(t *testing.T, baseURL, token, userID, wsID string, extra map[string]any) string {
	t.Helper()
	body := map[string]any{
		util.Fields.Record.Key:       "rem_" + uuid.New().String()[:8],
		util.Fields.Record.Value:     "secret-value",
		util.Fields.Record.Label:     "Passport number",
		util.Fields.Record.Type:      util.TypeText,
		util.Fields.Record.Format:    util.FormatHidden,
		util.Fields.Record.Workspace: wsID,
		util.Fields.Record.User:      userID,
	}
	for k, v := range extra {
		body[k] = v
	}
	return extractID(t, baseURL, util.Coll.Records, token, body)
}

func reminderNotifications(api *testutils.PBClient, token, recordID string) []*httpexpect.Object {
	items := api.E.GET("/api/collections/"+util.Coll.Notifications+"/records").
		WithQuery("filter", "type = '"+util.NotificationReminder+"' && refId = '"+recordID+"'").
		WithQuery("sort", "-created").
		WithHeader("Authorization", token).
		Expect().Status(http.StatusOK).JSON().Object().Value("items").Array()
	out := []*httpexpect.Object{}
	for i := 0; i < int(items.Length().Raw()); i++ {
		out = append(out, items.Value(i).Object())
	}
	return out
}

func TestRemindersOnChange(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()
	recordID := reminderEntry(t, baseURL, token, userID, wsID, nil)

	created := api.Create(util.Coll.Reminders, token, map[string]any{
		util.Fields.Reminder.User:   userID,
		util.Fields.Reminder.Record: recordID,
		util.Fields.Reminder.Kind:   util.ReminderKindChange,
		util.Fields.Reminder.Note:   "Tell the bank",
		// The server decides these; whatever the client says is ignored.
		util.Fields.Reminder.FiredAt: "2020-01-01 00:00:00.000Z",
	}).Expect().Status(http.StatusOK).JSON().Object()
	reminderID := created.Value("id").String().Raw()

	t.Run("it watches its own entry, in the entry's workspace", func(t *testing.T) {
		created.Value(util.Fields.Reminder.Workspace).String().IsEqual(wsID)
		created.Value(util.Fields.Reminder.Watch).String().IsEqual(recordID)
		created.Value(util.Fields.Reminder.FiredAt).String().IsEmpty()
	})

	t.Run("a rename is not a change", func(t *testing.T) {
		api := api.T(t)
		api.Update(util.Coll.Records, recordID, token, map[string]any{
			util.Fields.Record.Label: "Passport no.",
		}).Expect().Status(http.StatusOK)
		if n := len(reminderNotifications(api, token, recordID)); n != 0 {
			t.Fatalf("%d notifications after a rename", n)
		}
	})

	t.Run("a new value fires it, once, without the value", func(t *testing.T) {
		api := api.T(t)
		api.Update(util.Coll.Records, recordID, token, map[string]any{
			util.Fields.Record.Value: "new-secret",
		}).Expect().Status(http.StatusOK)
		got := reminderNotifications(api, token, recordID)
		if len(got) != 1 {
			t.Fatalf("%d notifications, want 1", len(got))
		}
		got[0].Value(util.Fields.Notification.Title).String().IsEqual("Reminder: Passport no.")
		message := got[0].Value(util.Fields.Notification.Message).String().Raw()
		if !strings.Contains(message, "Tell the bank") || strings.Contains(message, "secret") {
			t.Fatalf("unexpected message %q", message)
		}
		api.Get(util.Coll.Reminders, reminderID, token).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Reminder.FiredAt).String().NotEmpty()

		api.Update(util.Coll.Records, recordID, token, map[string]any{
			util.Fields.Record.Value: "newer-secret",
		}).Expect().Status(http.StatusOK)
		if n := len(reminderNotifications(api, token, recordID)); n != 1 {
			t.Fatalf("%d notifications after a second change, want still 1", n)
		}
	})

	t.Run("clearing firedAt arms it again", func(t *testing.T) {
		api := api.T(t)
		api.Update(util.Coll.Reminders, reminderID, token, map[string]any{
			util.Fields.Reminder.FiredAt: "",
		}).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Reminder.FiredAt).String().IsEmpty()
		api.Update(util.Coll.Records, recordID, token, map[string]any{
			util.Fields.Record.Value: "newest-secret",
		}).Expect().Status(http.StatusOK)
		if n := len(reminderNotifications(api, token, recordID)); n != 2 {
			t.Fatalf("%d notifications, want 2", n)
		}
	})

	t.Run("an alias changes when its parent does", func(t *testing.T) {
		api := api.T(t)
		parentID := reminderEntry(t, baseURL, token, userID, wsID, nil)
		aliasID := reminderEntry(t, baseURL, token, userID, wsID, map[string]any{
			util.Fields.Record.AliasOf: parentID,
			util.Fields.Record.Label:   "Alias",
		})
		api.Create(util.Coll.Reminders, token, map[string]any{
			util.Fields.Reminder.User:   userID,
			util.Fields.Reminder.Record: aliasID,
			util.Fields.Reminder.Kind:   util.ReminderKindChange,
		}).Expect().Status(http.StatusOK)
		api.Update(util.Coll.Records, parentID, token, map[string]any{
			util.Fields.Record.Value: "moved",
		}).Expect().Status(http.StatusOK)
		if n := len(reminderNotifications(api, token, aliasID)); n != 1 {
			t.Fatalf("%d notifications for the alias, want 1", n)
		}
	})

	t.Run("it can watch another entry in the workspace", func(t *testing.T) {
		api := api.T(t)
		watchedID := reminderEntry(t, baseURL, token, userID, wsID, map[string]any{
			util.Fields.Record.Label: "Address",
		})
		api.Create(util.Coll.Reminders, token, map[string]any{
			util.Fields.Reminder.User:   userID,
			util.Fields.Reminder.Record: recordID,
			util.Fields.Reminder.Kind:   util.ReminderKindChange,
			util.Fields.Reminder.Watch:  watchedID,
		}).Expect().Status(http.StatusOK)
		before := len(reminderNotifications(api, token, recordID))
		api.Update(util.Coll.Records, watchedID, token, map[string]any{
			util.Fields.Record.Value: "elsewhere",
		}).Expect().Status(http.StatusOK)
		got := reminderNotifications(api, token, recordID)
		if len(got) != before+1 {
			t.Fatalf("%d notifications, want %d", len(got), before+1)
		}
		got[0].Value(util.Fields.Notification.Message).String().Contains("Address")
	})
}

func TestRemindersStayWithTheirOwner(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	ownerID, ownerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	strangerID, strangerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	wsID := api.Get(util.Coll.Users, ownerID, ownerToken).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()
	strangerWS := api.Get(util.Coll.Users, strangerID, strangerToken).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()
	recordID := reminderEntry(t, baseURL, ownerToken, ownerID, wsID, nil)

	reminderID := extractID(t, baseURL, util.Coll.Reminders, ownerToken, map[string]any{
		util.Fields.Reminder.User:   ownerID,
		util.Fields.Reminder.Record: recordID,
		util.Fields.Reminder.Kind:   util.ReminderKindChange,
	})

	t.Run("nobody else sees or touches it", func(t *testing.T) {
		api := api.T(t)
		api.List(util.Coll.Reminders, strangerToken).Expect().Status(http.StatusOK).
			JSON().Object().Value("items").Array().Length().IsEqual(0)
		api.Get(util.Coll.Reminders, reminderID, strangerToken).Expect().Status(http.StatusNotFound)
		api.Delete(util.Coll.Reminders, reminderID, strangerToken).Expect().Status(http.StatusNotFound)
	})

	t.Run("an entry outside your workspaces cannot be watched", func(t *testing.T) {
		api := api.T(t)
		api.Create(util.Coll.Reminders, strangerToken, map[string]any{
			util.Fields.Reminder.User:   strangerID,
			util.Fields.Reminder.Record: recordID,
			util.Fields.Reminder.Kind:   util.ReminderKindChange,
		}).Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("data").Object().Value(util.Fields.Reminder.Record).Object().
			Value("code").String().IsEqual(util.Errors.ReminderRecordMissing.ErrorCode)

		ownID := reminderEntry(t, baseURL, strangerToken, strangerID, strangerWS, nil)
		api.Create(util.Coll.Reminders, strangerToken, map[string]any{
			util.Fields.Reminder.User:   strangerID,
			util.Fields.Reminder.Record: ownID,
			util.Fields.Reminder.Kind:   util.ReminderKindChange,
			util.Fields.Reminder.Watch:  recordID,
		}).Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("data").Object().Value(util.Fields.Reminder.Watch).Object().
			Value("code").String().IsEqual(util.Errors.ReminderWatchMissing.ErrorCode)
	})

	t.Run("nobody can make one for someone else", func(t *testing.T) {
		api := api.T(t)
		api.Create(util.Coll.Reminders, strangerToken, map[string]any{
			util.Fields.Reminder.User:   ownerID,
			util.Fields.Reminder.Record: recordID,
			util.Fields.Reminder.Kind:   util.ReminderKindChange,
		}).Expect().Status(http.StatusForbidden)
	})
}

func TestRemindersOnADate(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()
	recordID := reminderEntry(t, baseURL, token, userID, wsID, nil)

	t.Run("a date reminder needs a date", func(t *testing.T) {
		api.T(t).Create(util.Coll.Reminders, token, map[string]any{
			util.Fields.Reminder.User:   userID,
			util.Fields.Reminder.Record: recordID,
			util.Fields.Reminder.Kind:   util.ReminderKindDate,
		}).Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("data").Object().Value(util.Fields.Reminder.DueAt).Object().
			Value("code").String().IsEqual(util.Errors.ReminderDueRequired.ErrorCode)
	})

	now := time.Now().UTC()
	dueID := extractID(t, baseURL, util.Coll.Reminders, token, map[string]any{
		util.Fields.Reminder.User:   userID,
		util.Fields.Reminder.Record: recordID,
		util.Fields.Reminder.Kind:   util.ReminderKindDate,
		util.Fields.Reminder.DueAt:  now.Add(-time.Minute).Format("2006-01-02 15:04:05.000Z"),
	})
	laterID := extractID(t, baseURL, util.Coll.Reminders, token, map[string]any{
		util.Fields.Reminder.User:   userID,
		util.Fields.Reminder.Record: recordID,
		util.Fields.Reminder.Kind:   util.ReminderKindDate,
		util.Fields.Reminder.DueAt:  now.AddDate(0, 1, 0).Format("2006-01-02 15:04:05.000Z"),
	})

	t.Run("it fires when its time has come, and not before", func(t *testing.T) {
		api := api.T(t)
		services.FireDueReminders(app, now)
		services.FireDueReminders(app, now)
		if n := len(reminderNotifications(api, token, recordID)); n != 1 {
			t.Fatalf("%d notifications, want 1", n)
		}
		api.Get(util.Coll.Reminders, dueID, token).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Reminder.FiredAt).String().NotEmpty()
		api.Get(util.Coll.Reminders, laterID, token).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Reminder.FiredAt).String().IsEmpty()

		services.FireDueReminders(app, now.AddDate(0, 1, 1))
		if n := len(reminderNotifications(api, token, recordID)); n != 2 {
			t.Fatalf("%d notifications, want 2", n)
		}
	})

	t.Run("a date reminder does not fire on a change", func(t *testing.T) {
		api := api.T(t)
		before := len(reminderNotifications(api, token, recordID))
		api.Update(util.Coll.Records, recordID, token, map[string]any{
			util.Fields.Record.Value: "changed",
		}).Expect().Status(http.StatusOK)
		if n := len(reminderNotifications(api, token, recordID)); n != before {
			t.Fatalf("%d notifications, want %d", n, before)
		}
	})

	t.Run("deleting the entry deletes its reminders", func(t *testing.T) {
		api := api.T(t)
		api.Delete(util.Coll.Records, recordID, token).Expect().Status(http.StatusNoContent)
		api.Get(util.Coll.Reminders, laterID, token).Expect().Status(http.StatusNotFound)
	})
}
