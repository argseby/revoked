package tests

import (
	"fmt"
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"
	"time"
)

func TestApiKeySecurity_Rigorous_Refactored(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userA_ID, userA_Token, _ := testutils.CreateRandomUser(baseURL)
	userB_ID, userB_Token, _ := testutils.CreateRandomUser(baseURL)

	var workspaceID string

	t.Run("Setup: Admin creates a business workspace", func(t *testing.T) {
		api := api.T(t)
		slug := fmt.Sprintf("admin-workspace-%d", time.Now().UnixNano())

		ws := api.Create(util.Coll.Workspaces, userA_Token, map[string]any{
			"name": "Admin Workspace",
			"slug": slug,
		}).Expect().Status(http.StatusOK)

		workspaceID = testutils.ExtractString(ws, "id")

		api.Update(util.Coll.Users, userA_ID, userA_Token, map[string]any{
			"activeWorkspace": workspaceID,
			"activeRole":      util.RoleAdmin,
		}).Expect().Status(http.StatusOK)

		refreshA := api.AuthRefresh(util.Coll.Users, userA_Token).Expect().Status(http.StatusOK)
		userA_Token = testutils.ExtractString(refreshA, "token")

		api.Create(util.Coll.WorkspaceMembers, userA_Token, map[string]any{
			"user":      userB_ID,
			"workspace": workspaceID,
			"role":      util.RoleMember,
		}).Expect().Status(http.StatusOK)

		api.Update(util.Coll.Users, userB_ID, userB_Token, map[string]any{
			"activeWorkspace": workspaceID,
			"activeRole":      util.RoleMember,
		}).Expect().Status(http.StatusOK)

		refreshB := api.AuthRefresh(util.Coll.Users, userB_Token).Expect().Status(http.StatusOK)
		userB_Token = testutils.ExtractString(refreshB, "token")
	})

	t.Run("Security: Admin can create an API Key for themselves", func(t *testing.T) {
		api := api.T(t)
		ts := time.Now().UnixNano()
		api.AssertStatus(api.Create(util.Coll.ApiKeys, userA_Token, map[string]any{
			"label":     fmt.Sprintf("admin-key-%d", ts),
			"workspace": workspaceID,
			"user":      userA_ID,
			"scopes":    []string{util.ScopeRecordRead},
		}), http.StatusOK)
	})

	t.Run("Security: Regular member cannot create an API Key", func(t *testing.T) {
		api := api.T(t)
		ts := time.Now().UnixNano()
		api.AssertStatus(api.Create(util.Coll.ApiKeys, userB_Token, map[string]any{
			"label":     fmt.Sprintf("member-key-%d", ts),
			"workspace": workspaceID,
			"user":      userB_ID,
			"scopes":    []string{util.ScopeRecordRead},
		}), http.StatusForbidden)
	})

	t.Run("Security: Admin cannot create an API Key for another user (SelfOnly check)", func(t *testing.T) {
		api := api.T(t)
		ts := time.Now().UnixNano()
		api.AssertStatus(api.Create(util.Coll.ApiKeys, userA_Token, map[string]any{
			"label":     fmt.Sprintf("spoofed-key-%d", ts),
			"workspace": workspaceID,
			"user":      userB_ID,
			"scopes":    []string{util.ScopeRecordRead},
		}), http.StatusForbidden)
	})

	t.Run("Security: API Key cannot create another API Key (Scope-less check)", func(t *testing.T) {
		api := api.T(t)
		ts := time.Now().UnixNano()

		res := api.Create(util.Coll.ApiKeys, userA_Token, map[string]any{
			"label":     fmt.Sprintf("escalation-base-%d", ts),
			"workspace": workspaceID,
			"user":      userA_ID,
			"scopes":    []string{util.ScopeRecordRead},
		}).Expect().Status(http.StatusOK)

		apiKeyToken := res.Header("X-Plain-Token").Raw()

		api.AssertStatus(api.Create(util.Coll.ApiKeys, apiKeyToken, map[string]any{
			"label":     fmt.Sprintf("escalated-key-%d", ts),
			"workspace": workspaceID,
			"user":      userA_ID,
			"scopes":    []string{util.ScopeRecordRead},
		}), http.StatusForbidden)
	})

	t.Run("Security: API Key is immutable (No Updates)", func(t *testing.T) {
		api := api.T(t)
		ts := time.Now().UnixNano()

		res := api.Create(util.Coll.ApiKeys, userA_Token, map[string]any{
			"label":     fmt.Sprintf("immutable-%d", ts),
			"workspace": workspaceID,
			"user":      userA_ID,
			"scopes":    []string{util.ScopeRecordRead},
		}).Expect().Status(http.StatusOK)

		actualID := testutils.ExtractString(res, "id")
		token := res.Header("X-Plain-Token").Raw()

		api.AssertStatus(api.Update(util.Coll.ApiKeys, actualID, userA_Token, map[string]any{
			"scopes": []string{util.ScopeRecordRead, util.ScopeRecordCreate},
		}), http.StatusForbidden)

		api.AssertStatus(api.Update(util.Coll.ApiKeys, actualID, token, map[string]any{
			"scopes": []string{util.ScopeRecordRead, util.ScopeRecordCreate},
		}), http.StatusForbidden)
	})

	t.Run("Security: API Key cannot be deleted by anyone except the owner", func(t *testing.T) {
		api := api.T(t)
		ts := time.Now().UnixNano()

		res := api.Create(util.Coll.ApiKeys, userA_Token, map[string]any{
			"label":     fmt.Sprintf("deletion-%d", ts),
			"workspace": workspaceID,
			"user":      userA_ID,
			"scopes":    []string{util.ScopeRecordRead},
		}).Expect().Status(http.StatusOK)

		keyID := testutils.ExtractString(res, "id")

		api.AssertStatus(api.Delete(util.Coll.ApiKeys, keyID, userB_Token), http.StatusForbidden)
		api.AssertStatus(api.Delete(util.Coll.ApiKeys, keyID, userA_Token), http.StatusNoContent)
	})

	t.Run("Integrity: Cannot create an API Key with an invalid scope", func(t *testing.T) {
		api := api.T(t)
		ts := time.Now().UnixNano()
		api.AssertStatus(api.Create(util.Coll.ApiKeys, userA_Token, map[string]any{
			"label":     fmt.Sprintf("invalid-scope-%d", ts),
			"workspace": workspaceID,
			"user":      userA_ID,
			"scopes":    []string{"invalid:scope:name"},
		}), http.StatusBadRequest)
	})

	t.Run("Integrity: Cannot create an API Key with duplicate scopes", func(t *testing.T) {
		api := api.T(t)
		ts := time.Now().UnixNano()
		api.AssertStatus(api.Create(util.Coll.ApiKeys, userA_Token, map[string]any{
			"label":     fmt.Sprintf("duplicate-scope-%d", ts),
			"workspace": workspaceID,
			"user":      userA_ID,
			"scopes":    []string{util.ScopeRecordRead, util.ScopeRecordRead},
		}), http.StatusBadRequest)
	})
}
