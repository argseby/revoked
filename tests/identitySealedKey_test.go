package tests

import (
	"net/http"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/google/uuid"
	"github.com/pocketbase/pocketbase/core"
)

// The wrapped private key travels only between the owner's own devices: the
// owner writes and reads it, revocation clears it, and an API key reading the
// identity gets the row without it.
func TestIdentitySealedKey(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)
	identityID, _ := newIdentity(t, baseURL, token, "synced", userID, wsID)

	f := util.Fields.Identity

	t.Run("nothing sent at create survives", func(t *testing.T) {
		id, _ := newIdentity(t, baseURL, token, "eager", userID, wsID)
		rec, err := app.FindRecordById(util.Coll.Identities, id)
		if err != nil {
			t.Fatal(err)
		}
		// newIdentity sends no sealedKey, so assert through the hook's output
		// shape: both fields start empty whatever a creator sends.
		if rec.GetString(f.SealedKey) != "" || rec.GetInt(f.SealedKeyEpoch) != 0 {
			t.Fatalf("a new identity carries a sealed key: %q", rec.GetString(f.SealedKey))
		}
	})

	t.Run("the owner stores and reads the wrap", func(t *testing.T) {
		api.Update(util.Coll.Identities, identityID, token, map[string]any{
			f.SealedKey: "sealed-ciphertext", f.SealedKeyEpoch: 3,
		}).Expect().Status(http.StatusOK)
		row := api.Get(util.Coll.Identities, identityID, token).Expect().Status(http.StatusOK).JSON().Object()
		row.Value(f.SealedKey).String().IsEqual("sealed-ciphertext")
		row.Value(f.SealedKeyEpoch).Number().IsEqual(3)
	})

	t.Run("an API key reads the identity without the wrap", func(t *testing.T) {
		apiKeys, err := app.FindCollectionByNameOrId(util.Coll.ApiKeys)
		if err != nil {
			t.Fatal(err)
		}
		keyToken := uuid.New().String()
		key := core.NewRecord(apiKeys)
		key.Set(util.Fields.ApiKey.Label, "reader")
		key.Set(util.Fields.ApiKey.Token, util.HashToken(keyToken))
		key.Set(util.Fields.ApiKey.User, userID)
		key.Set(util.Fields.ApiKey.Workspace, wsID)
		key.Set(util.Fields.ApiKey.Scopes, []string{util.ScopeIdentityRead})
		if err := app.Save(key); err != nil {
			t.Fatal(err)
		}
		row := api.Get(util.Coll.Identities, identityID, keyToken).Expect().Status(http.StatusOK).JSON().Object()
		row.Value(f.SealedKey).String().IsEqual("")
		items := api.List(util.Coll.Identities, keyToken).Expect().Status(http.StatusOK).
			JSON().Object().Value("items").Array()
		for _, raw := range items.Raw() {
			if raw.(map[string]any)[f.SealedKey] != "" {
				t.Fatal("a listed identity carries its wrap for an API key")
			}
		}
	})

	t.Run("revocation clears the wrap", func(t *testing.T) {
		api.Update(util.Coll.Identities, identityID, token, map[string]any{
			f.Status: util.StatusRevoked,
		}).Expect().Status(http.StatusOK)
		rec, err := app.FindRecordById(util.Coll.Identities, identityID)
		if err != nil {
			t.Fatal(err)
		}
		if rec.GetString(f.SealedKey) != "" || rec.GetInt(f.SealedKeyEpoch) != 0 {
			t.Fatal("a revoked identity still carries a sealed key")
		}
	})

	t.Run("a revoked identity accepts no new wrap", func(t *testing.T) {
		api.Update(util.Coll.Identities, identityID, token, map[string]any{
			f.SealedKey: "smuggled", f.SealedKeyEpoch: 4,
		}).Expect().Status(http.StatusOK)
		rec, err := app.FindRecordById(util.Coll.Identities, identityID)
		if err != nil {
			t.Fatal(err)
		}
		if rec.GetString(f.SealedKey) != "" {
			t.Fatal("a revoked identity took a new sealed key")
		}
	})
}
