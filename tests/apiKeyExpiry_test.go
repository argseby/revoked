package tests

import (
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// An expired key must be refused as expired, not as a permissions failure, so
// the holder can tell the difference between "aged out" and "not allowed".
func TestExpiredApiKeyIsRejected(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	users, _ := app.FindCollectionByNameOrId(util.Coll.Users)
	u := core.NewRecord(users)
	u.Set("email", "exp-"+uuid.New().String()[:8]+"@test.com")
	u.Set("verified", true)
	u.SetPassword("password12345")
	if err := app.Save(u); err != nil {
		t.Fatal(err)
	}

	workspaces, _ := app.FindCollectionByNameOrId(util.Coll.Workspaces)
	ws := core.NewRecord(workspaces)
	ws.Set("name", "Expiry WS")
	ws.Set("slug", "exp-"+uuid.New().String()[:8])
	if err := app.Save(ws); err != nil {
		t.Fatal(err)
	}

	apiKeys, _ := app.FindCollectionByNameOrId(util.Coll.ApiKeys)
	mkKey := func(expiresAt any) string {
		tok := uuid.New().String()
		k := core.NewRecord(apiKeys)
		k.Set("label", "key")
		k.Set("token", util.HashToken(tok))
		k.Set("user", u.Id)
		k.Set("workspace", ws.Id)
		k.Set("scopes", []string{util.ScopeLinkCreate})
		if expiresAt != nil {
			k.Set(util.Fields.ApiKey.ExpiresAt, expiresAt)
		}
		if err := app.Save(k); err != nil {
			t.Fatal(err)
		}
		return tok
	}

	payload := func() map[string]any {
		return map[string]any{
			util.Fields.Link.Slug:      "exp" + uuid.New().String()[:6],
			util.Fields.Link.Label:     "Expiry probe",
			util.Fields.Link.Status:    util.StatusActive,
			util.Fields.Link.Workspace: ws.Id,
		}
	}

	t.Run("an expired key is refused as expired", func(t *testing.T) {
		api := api.T(t)
		expired := mkKey(types.NowDateTime().Add(-24 * time.Hour))
		api.Create(util.Coll.Links, expired, payload()).
			Expect().Status(http.StatusUnauthorized).JSON().Object().
			Value("data").Object().Value("apiKey").Object().
			Value("code").String().IsEqual(util.Errors.ApiKeyExpired.ErrorCode)
	})

	t.Run("a key expiring later still works", func(t *testing.T) {
		api := api.T(t)
		future := mkKey(types.NowDateTime().Add(24 * time.Hour))
		api.Create(util.Coll.Links, future, payload()).Expect().Status(http.StatusOK)
	})

	t.Run("a key with no expiry never expires", func(t *testing.T) {
		api := api.T(t)
		never := mkKey(nil)
		api.Create(util.Coll.Links, never, payload()).Expect().Status(http.StatusOK)
	})
}
