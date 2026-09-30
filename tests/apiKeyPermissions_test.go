package tests

import (
	"fmt"
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"
	"time"
)

// An API key is granted by permission key, exactly as an invite is. The create
// hook once validated the submitted values against AllScopes alone, so every
// key the app's own picker produced came back as invalid_scope.
func TestApiKeyPermissions_GrantedByKeyNotRawScope(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	// CreateRandomUser provisions a workspace and makes the account its admin,
	// but does so after issuing the token — so the one to use is the refreshed
	// one, which is the state the key picker actually runs in.
	userID, token, _ := testutils.CreateRandomUser(baseURL)
	refreshed := api.AuthRefresh(util.Coll.Users, token).Expect().Status(http.StatusOK)
	token = testutils.ExtractString(refreshed, "token")
	workspaceID := refreshed.JSON().Object().Value("record").Object().
		Value(util.Fields.User.ActiveWorkspace).String().Raw()

	t.Run("permission keys are accepted and stored expanded", func(t *testing.T) {
		api := api.T(t)
		created := api.AssertStatus(api.Create(util.Coll.ApiKeys, token, map[string]any{
			"label":     fmt.Sprintf("picker-key-%d", time.Now().UnixNano()),
			"workspace": workspaceID,
			"user":      userID,
			"scopes":    []string{util.PermRequestsRead, util.PermSharesRead},
		}), http.StatusOK)

		scopes := created.JSON().Object().Value("scopes").Array()
		// The stored value is the expansion, never the keys the caller sent.
		scopes.ContainsAll(util.ScopeRequestRead, util.ScopeLinkRead)
		scopes.NotContainsAny(util.PermRequestsRead, util.PermSharesRead)
	})

	t.Run("raw scopes still work", func(t *testing.T) {
		api := api.T(t)
		created := api.AssertStatus(api.Create(util.Coll.ApiKeys, token, map[string]any{
			"label":     fmt.Sprintf("raw-key-%d", time.Now().UnixNano()),
			"workspace": workspaceID,
			"user":      userID,
			"scopes":    []string{util.ScopeLinkRead},
		}), http.StatusOK)

		created.JSON().Object().Value("scopes").Array().ContainsAll(util.ScopeLinkRead)
	})

	t.Run("no key opens the vault, by permission or by raw scope", func(t *testing.T) {
		api := api.T(t)
		for _, scopes := range [][]string{
			{util.PermVaultRead},
			{util.PermVaultWrite, util.PermSharesRead},
			{util.ScopeRecordRead},
			{util.ScopeSectionCreate},
		} {
			api.Create(util.Coll.ApiKeys, token, map[string]any{
				"label":     fmt.Sprintf("vault-key-%d", time.Now().UnixNano()),
				"workspace": workspaceID,
				"user":      userID,
				"scopes":    scopes,
			}).Expect().Status(http.StatusBadRequest).
				JSON().Object().Value("data").Object().Value(util.Fields.ApiKey.Scopes).Object().
				Value("code").String().IsEqual(util.Errors.ApiKeyVaultScope.ErrorCode)
		}
	})

	t.Run("an unknown permission is still refused", func(t *testing.T) {
		api := api.T(t)
		api.Create(util.Coll.ApiKeys, token, map[string]any{
			"label":     fmt.Sprintf("bogus-key-%d", time.Now().UnixNano()),
			"workspace": workspaceID,
			"user":      userID,
			"scopes":    []string{"vault:teleport"},
		}).Expect().Status(http.StatusBadRequest)
	})
}
