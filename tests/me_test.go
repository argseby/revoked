package tests

import (
	"fmt"
	"net/http"
	"sort"
	"testing"
	"time"

	"revoked/tests/testutils"
	"revoked/util"
)

type meFixture struct {
	api    *testutils.PBClient
	userID string
	token  string
	wsID   string
}

func newMeFixture(t *testing.T) meFixture {
	t.Helper()
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	refreshed := api.AuthRefresh(util.Coll.Users, token).Expect().Status(http.StatusOK)
	return meFixture{
		api:    api,
		userID: userID,
		token:  testutils.ExtractString(refreshed, "token"),
		wsID: refreshed.JSON().Object().Value("record").Object().
			Value(util.Fields.User.ActiveWorkspace).String().Raw(),
	}
}

// apiKey creates a key with the given permissions and returns its id and the
// plain token.
func (f meFixture) apiKey(t *testing.T, scopes ...string) (id, plain string) {
	t.Helper()
	resp := f.api.Create(util.Coll.ApiKeys, f.token, map[string]any{
		"label":     fmt.Sprintf("me-key-%d", time.Now().UnixNano()),
		"workspace": f.wsID,
		"user":      f.userID,
		"scopes":    scopes,
	}).Expect().Status(http.StatusOK)
	return resp.JSON().Object().Value("id").String().Raw(), resp.Header("X-Plain-Token").Raw()
}

func keysOf(m map[string]any) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func TestMeNamesTheCredential(t *testing.T) {
	f := newMeFixture(t)

	t.Run("an anonymous caller is refused", func(t *testing.T) {
		f.api.T(t).E.GET("/api/me").Expect().Status(http.StatusUnauthorized).
			JSON().Object().Value("code").IsEqual(util.Errors.NotAuthenticated.ErrorCode)
	})

	t.Run("a session acts as its user in the active workspace", func(t *testing.T) {
		body := f.api.T(t).E.GET("/api/me").WithHeader("Authorization", f.token).
			Expect().Status(http.StatusOK).JSON().Object()
		body.Value("kind").IsEqual("user")
		body.Value("user").IsEqual(f.userID)
		body.Value("workspace").IsEqual(f.wsID)
		body.Value("role").IsEqual(util.RoleAdmin)
	})

	t.Run("a key learns its workspace, never its token", func(t *testing.T) {
		id, plain := f.apiKey(t, util.PermRequestsRead)
		resp := f.api.T(t).E.GET("/api/me").WithHeader("X-API-Key", plain).Expect().Status(http.StatusOK)
		body := resp.JSON().Object()
		body.Value("kind").IsEqual("apiKey")
		body.Value("id").IsEqual(id)
		body.Value("user").IsEqual(f.userID)
		body.Value("workspace").IsEqual(f.wsID)
		body.Value("scopes").Array().ContainsAll(util.ScopeRequestRead)
		body.Value("sections").Array().IsEmpty()
		body.Value("expiresAt").String()
		want := []string{"expiresAt", "id", "kind", "scopes", "sections", "user", "vaultAccess", "workspace"}
		if got := keysOf(body.Raw()); fmt.Sprint(got) != fmt.Sprint(want) {
			t.Errorf("fields = %v, want %v", got, want)
		}
		resp.Body().NotContains(plain)
	})

	t.Run("a connected tool learns its connection and workspace", func(t *testing.T) {
		connID, toolToken := connectTool(t, f.api.T(t), f.token)
		resp := f.api.T(t).E.GET("/api/me").WithHeader(util.ConnectionHeader, toolToken).
			Expect().Status(http.StatusOK)
		body := resp.JSON().Object()
		body.Value("kind").IsEqual("connection")
		body.Value("id").IsEqual(connID)
		body.Value("workspace").IsEqual(f.wsID)
		body.Value("clientId").IsEqual(toolOrigin)
		body.Value("expiresAt").String().NotEmpty()
		want := []string{"clientId", "expiresAt", "id", "kind", "workspace"}
		if got := keysOf(body.Raw()); fmt.Sprint(got) != fmt.Sprint(want) {
			t.Errorf("fields = %v, want %v", got, want)
		}
		resp.Body().NotContains(toolToken)
	})

	t.Run("a forged tool token is refused", func(t *testing.T) {
		f.api.T(t).E.GET("/api/me").WithHeader(util.ConnectionHeader, "not-a-token").
			Expect().Status(http.StatusUnauthorized).
			JSON().Object().Value("code").IsEqual(util.Errors.ConnectionUnauthorized.ErrorCode)
	})
}

// A key reads a request's answers the way the member who made it would: inside
// its own workspace, and only with the permissions it was given.
func TestRequestAnswersAcceptApiKeys(t *testing.T) {
	f := newMeFixture(t)
	baseURL, _ := testutils.SetupTestApp(t)
	identityID, _ := newIdentity(t, baseURL, f.token, "rq-key", f.userID, f.wsID)
	slug, requestID := setupRequest(t, baseURL, f.token, f.userID, f.wsID, identityID, nil)

	_, responderToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create responder: %v", err)
	}
	f.api.E.POST("/api/public/requests/"+slug).WithHeader("Authorization", responderToken).
		WithJSON(map[string]any{"data": map[string]any{"city": "Berlin"}}).
		Expect().Status(http.StatusOK)

	answers := func(t *testing.T, key string, status int) {
		t.Helper()
		f.api.T(t).E.GET("/api/requests/"+requestID+"/links").WithHeader("X-API-Key", key).
			Expect().Status(status)
	}

	t.Run("with requests and answers readable", func(t *testing.T) {
		_, key := f.apiKey(t, util.PermRequestsRead, util.PermResponsesRead)
		f.api.T(t).E.GET("/api/requests/"+requestID+"/links").WithHeader("X-API-Key", key).
			Expect().Status(http.StatusOK).JSON().Object().Value("items").Array().Length().IsEqual(1)
	})

	t.Run("the owner's own key needs only requests readable", func(t *testing.T) {
		_, key := f.apiKey(t, util.PermRequestsRead)
		answers(t, key, http.StatusOK)
	})

	t.Run("without requests readable", func(t *testing.T) {
		_, key := f.apiKey(t, util.PermSharesRead)
		f.api.T(t).E.GET("/api/requests/"+requestID+"/links").WithHeader("X-API-Key", key).
			Expect().Status(http.StatusForbidden).
			JSON().Object().Value("code").IsEqual(util.Errors.MissingPermission.ErrorCode)
	})

	t.Run("from another workspace", func(t *testing.T) {
		other := newMeFixture(t)
		_, key := other.apiKey(t, util.PermRequestsRead, util.PermResponsesRead)
		f.api.T(t).E.GET("/api/requests/"+requestID+"/links").WithHeader("X-API-Key", key).
			Expect().Status(http.StatusNotFound).
			JSON().Object().Value("code").IsEqual(util.Errors.RequestNotFound.ErrorCode)
	})
}
