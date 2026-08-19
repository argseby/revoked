package tests

import (
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"

	"github.com/google/uuid"
	"github.com/pocketbase/pocketbase/core"
)

func TestApiKeyScopes_Permissions(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	userA, _ := app.FindCollectionByNameOrId(util.Coll.Users)
	recordA := core.NewRecord(userA)
	recordA.Set("email", "userA@test.com")
	recordA.Set("verified", true)
	recordA.SetPassword("password12345")
	if err := app.Save(recordA); err != nil {
		t.Fatalf("Failed to save User A: %v", err)
	}

	workspaces, _ := app.FindCollectionByNameOrId(util.Coll.Workspaces)
	wsA := core.NewRecord(workspaces)
	wsA.Set("name", "Workspace A")
	wsA.Set("slug", "ws-a-"+uuid.New().String()[:8])
	if err := app.Save(wsA); err != nil {
		t.Fatalf("Failed to save Workspace A: %v", err)
	}

	apiKeys, _ := app.FindCollectionByNameOrId(util.Coll.ApiKeys)
	apiKeyAToken := uuid.New().String()
	akA := core.NewRecord(apiKeys)
	akA.Set("label", "Key A")
	akA.Set("token", util.HashToken(apiKeyAToken))
	akA.Set("user", recordA.Id)
	akA.Set("workspace", wsA.Id)
	akA.Set("scopes", []string{util.ScopeRecordCreate, util.ScopeRecordRead})
	if err := app.Save(akA); err != nil {
		t.Fatalf("Failed to save API Key A: %v", err)
	}

	recordB := core.NewRecord(userA)
	recordB.Set("email", "userB@test.com")
	recordB.Set("verified", true)
	recordB.SetPassword("password12345")
	if err := app.Save(recordB); err != nil {
		t.Fatalf("Failed to save User B: %v", err)
	}

	wsB := core.NewRecord(workspaces)
	wsB.Set("name", "Workspace B")
	wsB.Set("slug", "ws-b-"+uuid.New().String()[:8])
	if err := app.Save(wsB); err != nil {
		t.Fatalf("Failed to save Workspace B: %v", err)
	}

	apiKeyBToken := uuid.New().String()
	akB := core.NewRecord(apiKeys)
	akB.Set("label", "Key B")
	akB.Set("token", util.HashToken(apiKeyBToken))
	akB.Set("user", recordB.Id)
	akB.Set("workspace", wsB.Id)
	akB.Set("scopes", []string{util.ScopeRecordRead})
	if err := app.Save(akB); err != nil {
		t.Fatalf("Failed to save API Key B: %v", err)
	}

	api := testutils.NewPBClient(t, baseURL)

	t.Run("User A creates record successfully", func(t *testing.T) {
		api := api.T(t)
		res := api.AssertStatus(api.Create(util.Coll.Records, apiKeyAToken, map[string]any{
			"workspace": wsA.Id,
			"key":       "test_key",
			"value":     "test-value",
			"label":     "test-label",
			"type":      util.TypeText,
			"format":    util.FormatDefault,
		}), http.StatusOK)

		res.JSON().Object().Value("key").String().IsEqual("test_key")
	})

	// Authorization failures answer 403 with the reason, not the bare 400
	// PocketBase produces when a collection rule denies.
	t.Run("User B fails to create record (missing scope)", func(t *testing.T) {
		api := api.T(t)
		api.Create(util.Coll.Records, apiKeyBToken, map[string]any{
			"workspace": wsB.Id,
			"key":       "should-fail",
			"value":     "fail",
			"label":     "fail",
			"type":      util.TypeText,
			"format":    util.FormatDefault,
		}).Expect().Status(http.StatusForbidden).
			JSON().Object().Value("data").Object().Value(util.Fields.ApiKey.Scopes).Object().
			Value("message").String().Contains(util.ScopeRecordCreate)
	})
	t.Run("User A fails to create record in Workspace B (workspace mismatch)", func(t *testing.T) {
		api := api.T(t)
		api.Create(util.Coll.Records, apiKeyAToken, map[string]any{
			"workspace": wsB.Id,
			"key":       "ws-mismatch",
			"label":     "mismatch",
			"type":      util.TypeText,
			"format":    util.FormatDefault,
		}).Expect().Status(http.StatusForbidden).
			JSON().Object().Value("data").Object().Value(util.FieldWorkspace).Object().
			Value("code").String().IsEqual(util.Errors.ActiveWorkspaceMismatch.ErrorCode)
	})
}
