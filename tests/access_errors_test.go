package tests

import (
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/pocketbase/pocketbase/core"
)

// Every declared access spec must render exactly the rule the collection
// enforces, or the preflight diagnostics explain a requirement the server does
// not apply.
func TestAccessRegistryMatchesRules(t *testing.T) {
	_, app := testutils.SetupTestApp(t)

	ruleFor := func(c *core.Collection, action string) *string {
		switch action {
		case util.ActionCreate:
			return c.CreateRule
		case util.ActionUpdate:
			return c.UpdateRule
		case util.ActionDelete:
			return c.DeleteRule
		}
		return nil
	}

	for collName, actions := range util.CollectionAccess {
		coll, err := app.FindCollectionByNameOrId(collName)
		if err != nil {
			t.Fatalf("collection %q in the access registry does not exist: %v", collName, err)
		}
		for action, spec := range actions {
			deployed := ruleFor(coll, action)
			if deployed == nil {
				t.Errorf("%s.%s: registry declares a spec but the deployed rule is nil (superuser-only)", collName, action)
				continue
			}
			if got := spec.Rule(); got != *deployed {
				t.Errorf("%s.%s rule drift:\n  registry: %s\n  deployed: %s", collName, action, got, *deployed)
			}
		}
	}
}

// The richer denial errors must not become a cross-tenant existence oracle:
// outsiders keep PocketBase's indistinguishable 404.
func TestOutsidersCannotProbeRecordExistence(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	ownerID, ownerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create owner: %v", err)
	}
	ownerWs := api.Get(util.Coll.Users, ownerID, ownerToken).Expect().
		Status(http.StatusOK).JSON().Object().
		Value(util.Fields.User.ActiveWorkspace).String().Raw()

	linkID := extractID(t, baseURL, util.Coll.Links, ownerToken, map[string]any{
		util.Fields.Link.Slug:      "prv" + uuid.New().String()[:6],
		util.Fields.Link.Label:     "Private",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      ownerID,
		util.Fields.Link.Workspace: ownerWs,
	})

	_, outsiderToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create outsider: %v", err)
	}

	real := api.Update(util.Coll.Links, linkID, outsiderToken, map[string]any{
		util.Fields.Link.Label: "Hijacked",
	}).Expect().Raw().StatusCode
	fake := api.Update(util.Coll.Links, "doesnotexist000", outsiderToken, map[string]any{
		util.Fields.Link.Label: "Hijacked",
	}).Expect().Raw().StatusCode

	if real != fake {
		t.Fatalf("existence oracle: real id returned %d but unknown id returned %d", real, fake)
	}
	if real != http.StatusNotFound {
		t.Fatalf("expected 404 for an outsider, got %d", real)
	}
}

// setupKeyFixture returns a user, two workspaces, and a scoped key minter.
func setupKeyFixture(t *testing.T, app core.App) (userID, wsID, otherWsID string, mkKey func(...string) string) {
	t.Helper()

	users, _ := app.FindCollectionByNameOrId(util.Coll.Users)
	u := core.NewRecord(users)
	u.Set("email", "acc-"+uuid.New().String()[:8]+"@test.com")
	u.Set("verified", true)
	u.SetPassword("password12345")
	if err := app.Save(u); err != nil {
		t.Fatal(err)
	}

	workspaces, _ := app.FindCollectionByNameOrId(util.Coll.Workspaces)
	mkWs := func(name string) *core.Record {
		ws := core.NewRecord(workspaces)
		ws.Set("name", name)
		ws.Set("slug", "acc-"+uuid.New().String()[:8])
		if err := app.Save(ws); err != nil {
			t.Fatal(err)
		}
		return ws
	}
	ws := mkWs("Access WS")
	other := mkWs("Other WS")

	apiKeys, _ := app.FindCollectionByNameOrId(util.Coll.ApiKeys)
	mkKey = func(scopes ...string) string {
		tok := uuid.New().String()
		k := core.NewRecord(apiKeys)
		k.Set("label", "key")
		k.Set("token", util.HashToken(tok))
		k.Set("user", u.Id)
		k.Set("workspace", ws.Id)
		k.Set("scopes", scopes)
		if err := app.Save(k); err != nil {
			t.Fatal(err)
		}
		return tok
	}

	return u.Id, ws.Id, other.Id, mkKey
}

// A denied write must name its actual reason instead of a reasonless 400.
func TestWriteDenialsExplainThemselves(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, wsID, otherWsID, mkKey := setupKeyFixture(t, app)

	linkPayload := func(workspace string) map[string]any {
		return map[string]any{
			util.Fields.Link.Slug:      "acc" + uuid.New().String()[:6],
			util.Fields.Link.Label:     "This label is required",
			util.Fields.Link.User:      userID,
			util.Fields.Link.Workspace: workspace,
			util.Fields.Link.Status:    util.StatusActive,
		}
	}

	t.Run("missing scope names the scope", func(t *testing.T) {
		api := api.T(t)
		key := mkKey(util.ScopeRecordRead)
		body := api.Create(util.Coll.Links, key, linkPayload(wsID)).
			Expect().Status(http.StatusForbidden).JSON().Object()

		body.Value("data").Object().Value(util.Fields.ApiKey.Scopes).Object().
			Value("code").String().IsEqual(util.Errors.InvalidScope.ErrorCode)
		body.Value("data").Object().Value(util.Fields.ApiKey.Scopes).Object().
			Value("message").String().Contains(util.ScopeLinkCreate)
	})

	t.Run("wrong workspace is reported without disclosing the key's workspace", func(t *testing.T) {
		api := api.T(t)
		key := mkKey(util.ScopeLinkCreate)
		resp := api.Create(util.Coll.Links, key, linkPayload(otherWsID)).
			Expect().Status(http.StatusForbidden)

		resp.JSON().Object().Value("data").Object().Value(util.FieldWorkspace).Object().
			Value("code").String().IsEqual(util.Errors.ActiveWorkspaceMismatch.ErrorCode)

		// Errors end up in logs and tickets, so they must not disclose the
		// workspace the key is bound to — a value the caller never supplied.
		if raw := resp.Body().Raw(); strings.Contains(raw, wsID) {
			t.Fatalf("response discloses the API key's workspace id %q:\n%s", wsID, raw)
		}
	})

	t.Run("both failures are reported together", func(t *testing.T) {
		api := api.T(t)
		key := mkKey(util.ScopeRecordRead)
		resp := api.Create(util.Coll.Links, key, linkPayload(otherWsID)).
			Expect().Status(http.StatusForbidden)

		data := resp.JSON().Object().Value("data").Object()
		data.ContainsKey(util.Fields.ApiKey.Scopes)
		data.ContainsKey(util.FieldWorkspace)

		if raw := resp.Body().Raw(); strings.Contains(raw, wsID) {
			t.Fatalf("response discloses the API key's workspace id %q:\n%s", wsID, raw)
		}
	})

	t.Run("unknown api key is 401 not a rule denial", func(t *testing.T) {
		api := api.T(t)
		body := api.Create(util.Coll.Links, "totally-bogus-key", linkPayload(wsID)).
			Expect().Status(http.StatusUnauthorized).JSON().Object()

		body.Value("data").Object().Value("apiKey").Object().
			Value("code").String().IsEqual(util.Errors.InvalidApiKey.ErrorCode)
	})

	t.Run("anonymous write is unauthenticated", func(t *testing.T) {
		api := api.T(t)
		body := api.Create(util.Coll.Links, "", linkPayload(wsID)).
			Expect().Status(http.StatusForbidden).JSON().Object()

		body.Value("data").Object().Value("auth").Object().
			Value("code").String().IsEqual(util.Errors.NotAuthenticated.ErrorCode)
	})

	t.Run("user-auth mismatch does not disclose the active workspace", func(t *testing.T) {
		api := api.T(t)
		otherUserID, otherToken, err := testutils.CreateRandomUser(baseURL)
		if err != nil {
			t.Fatalf("Failed to create user: %v", err)
		}
		activeWs := api.Get(util.Coll.Users, otherUserID, otherToken).Expect().
			Status(http.StatusOK).JSON().Object().
			Value(util.Fields.User.ActiveWorkspace).String().Raw()

		resp := api.Create(util.Coll.Links, otherToken, linkPayload(wsID)).
			Expect().Status(http.StatusForbidden)

		if raw := resp.Body().Raw(); strings.Contains(raw, activeWs) {
			t.Fatalf("response discloses the caller's active workspace id %q:\n%s", activeWs, raw)
		}
	})

	t.Run("a correct request still succeeds", func(t *testing.T) {
		api := api.T(t)
		key := mkKey(util.ScopeLinkCreate)
		api.Create(util.Coll.Links, key, linkPayload(wsID)).
			Expect().Status(http.StatusOK).JSON().Object().
			Value(util.Fields.Link.Slug).String().NotEmpty()
	})

	t.Run("field validation still reports per-field codes", func(t *testing.T) {
		api := api.T(t)
		key := mkKey(util.ScopeLinkCreate)
		api.Create(util.Coll.Links, key, map[string]any{
			util.Fields.Link.Slug:      "acc" + uuid.New().String()[:6],
			util.Fields.Link.Workspace: wsID,
			util.Fields.Link.Status:    util.StatusActive,
		}).Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("data").Object().Value(util.Fields.Link.Label).Object().
			Value("code").String().IsEqual("validation_required")
	})
}

// Update and delete are diagnosed against the stored record, not the payload.
func TestUpdateAndDeleteDenialsExplainThemselves(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, wsID, _, mkKey := setupKeyFixture(t, app)
	createKey := mkKey(util.ScopeLinkCreate)

	linkID := api.Create(util.Coll.Links, createKey, map[string]any{
		util.Fields.Link.Slug:      "upd" + uuid.New().String()[:6],
		util.Fields.Link.Label:     "Editable",
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
		util.Fields.Link.Status:    util.StatusActive,
	}).Expect().Status(http.StatusOK).JSON().Object().Value("id").String().Raw()

	t.Run("update without link:update names the scope", func(t *testing.T) {
		api := api.T(t)
		api.Update(util.Coll.Links, linkID, createKey, map[string]any{
			util.Fields.Link.Label: "Renamed",
		}).Expect().Status(http.StatusForbidden).JSON().Object().
			Value("data").Object().Value(util.Fields.ApiKey.Scopes).Object().
			Value("message").String().Contains(util.ScopeLinkUpdate)
	})

	t.Run("delete without link:delete names the scope", func(t *testing.T) {
		api := api.T(t)
		api.Delete(util.Coll.Links, linkID, createKey).
			Expect().Status(http.StatusForbidden).JSON().Object().
			Value("data").Object().Value(util.Fields.ApiKey.Scopes).Object().
			Value("message").String().Contains(util.ScopeLinkDelete)
	})

	t.Run("scoped key can update", func(t *testing.T) {
		api := api.T(t)
		key := mkKey(util.ScopeLinkUpdate)
		api.Update(util.Coll.Links, linkID, key, map[string]any{
			util.Fields.Link.Label: "Renamed",
		}).Expect().Status(http.StatusOK)
	})
}
