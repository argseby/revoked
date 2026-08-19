package tests

import (
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestSectionsLifecycle(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	// Creating a user also creates a personal workspace, activated on login.
	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}

	var section1ID string
	var record1ID, record2ID string

	t.Run("Create a section and then another one with the same key to verify duplicate key error", func(t *testing.T) {
		api := api.T(t)

		userRes := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).JSON().Object()
		activeWS := userRes.Value(util.Fields.User.ActiveWorkspace).String().Raw()
		t.Logf("User %s: activeWorkspace=%s, activeRole=%s",
			userID,
			activeWS,
			userRes.Value(util.Fields.User.ActiveRole).String().Raw(),
		)

		req := api.Create(util.Coll.Sections, token, map[string]any{
			util.Fields.Section.Key:       "test_section",
			util.Fields.Section.Name:      "Test Section",
			util.Fields.Section.Workspace: activeWS,
			util.Fields.Section.User:      userID,
		})
		resp := req.Expect()
		if resp.Raw().StatusCode != http.StatusOK {
			t.Logf("Create section failed: %s", resp.Body().Raw())
		}
		resp.Status(http.StatusOK)

		section1ID = testutils.ExtractString(resp, "id")
		assert.NotEmpty(t, section1ID)

		// idxSectionsKeyUserWorkspace is unique on (workspace, key, user).
		api.Create(util.Coll.Sections, token, map[string]any{
			util.Fields.Section.Key:       "test_section",
			util.Fields.Section.Name:      "Duplicate Test Section",
			util.Fields.Section.Workspace: activeWS,
			util.Fields.Section.User:      userID,
		}).Expect().Status(http.StatusBadRequest)
	})

	t.Run("Create records and add them to the section", func(t *testing.T) {
		api := api.T(t)

		userRes := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).JSON().Object()
		activeWS := userRes.Value(util.Fields.User.ActiveWorkspace).String().Raw()

		rec1 := api.Create(util.Coll.Records, token, map[string]any{
			util.Fields.Record.Key:       "rec_1",
			util.Fields.Record.Value:     "val_1",
			util.Fields.Record.Label:     "Record 1",
			util.Fields.Record.Type:      "text",
			util.Fields.Record.Format:    "default",
			util.Fields.Record.Workspace: activeWS,
			util.Fields.Record.User:      userID,
		}).Expect().Status(http.StatusOK)

		record1ID = testutils.ExtractString(rec1, "id")
		assert.NotEmpty(t, record1ID)

		rec2 := api.Create(util.Coll.Records, token, map[string]any{
			util.Fields.Record.Key:       "rec_2",
			util.Fields.Record.Value:     "val_2",
			util.Fields.Record.Label:     "Record 2",
			util.Fields.Record.Type:      "text",
			util.Fields.Record.Format:    "default",
			util.Fields.Record.Workspace: activeWS,
			util.Fields.Record.User:      userID,
		}).Expect().Status(http.StatusOK)

		record2ID = testutils.ExtractString(rec2, "id")
		assert.NotEmpty(t, record2ID)

		api.Update(util.Coll.Sections, section1ID, token, map[string]any{
			util.Fields.Section.Records: []string{record1ID, record2ID},
		}).Expect().Status(http.StatusOK)

		getSec := api.Get(util.Coll.Sections, section1ID, token).Expect().Status(http.StatusOK).JSON().Object()
		recordsArr := getSec.Value(util.Fields.Section.Records).Array()
		recordsArr.Length().IsEqual(2)
		recordsArr.Contains(record1ID, record2ID)
	})

	t.Run("Delete the section and verify that records are not deleted", func(t *testing.T) {
		api := api.T(t)

		api.Delete(util.Coll.Sections, section1ID, token).Expect().Status(http.StatusNoContent)

		api.Get(util.Coll.Records, record1ID, token).Expect().Status(http.StatusOK)
		api.Get(util.Coll.Records, record2ID, token).Expect().Status(http.StatusOK)
	})
}
