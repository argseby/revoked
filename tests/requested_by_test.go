package tests

import (
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"

	"github.com/google/uuid"
)

// Records and sections accept an optional `requestedBy` field, set by
// integrations when the data arrived through a request.
func TestRecordsAcceptRequestedBy(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	recID := extractID(t, baseURL, util.Coll.Records, token, map[string]any{
		util.Fields.Record.Key:         "rb-" + uuid.New().String()[:6],
		util.Fields.Record.Value:       "value",
		util.Fields.Record.Label:       "label",
		util.Fields.Record.Type:        util.TypeText,
		util.Fields.Record.Format:      util.FormatDefault,
		util.Fields.Record.Workspace:   wsID,
		util.Fields.Record.User:        userID,
		util.Fields.Record.RequestedBy: "Alice <alice@example.com>",
	})

	body := api.Get(util.Coll.Records, recID, token).Expect().Status(http.StatusOK).JSON().Object()
	body.Value(util.Fields.Record.RequestedBy).String().IsEqual("Alice <alice@example.com>")
}

func TestSectionsAcceptRequestedBy(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	secID := extractID(t, baseURL, util.Coll.Sections, token, map[string]any{
		util.Fields.Section.Key:         "sb_" + uuid.New().String()[:6],
		util.Fields.Section.Name:        "Section with requestedBy",
		util.Fields.Section.Workspace:   wsID,
		util.Fields.Section.User:        userID,
		util.Fields.Section.RequestedBy: "Bob via webhook",
	})

	body := api.Get(util.Coll.Sections, secID, token).Expect().Status(http.StatusOK).JSON().Object()
	body.Value(util.Fields.Section.RequestedBy).String().IsEqual("Bob via webhook")
}
