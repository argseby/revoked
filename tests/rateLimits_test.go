package tests

import (
	"net/http"
	"revoked/cmd/revoked/routes"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"
)

// The superuser login guards the root key. PocketBase's limiter is off until a
// migration switches it on, and nothing else stands in front of this endpoint.
func TestSuperuserLoginIsRateLimited(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	login := func() int {
		return api.E.POST("/api/collections/_superusers/auth-with-password").
			WithJSON(map[string]any{"identity": "nobody@test.invalid", "password": "guess"}).
			Expect().Raw().StatusCode
	}
	for i := 0; i < 5; i++ {
		if status := login(); status != http.StatusBadRequest {
			t.Fatalf("attempt %d: got %d, want 400 for a wrong password", i+1, status)
		}
	}
	if status := login(); status != http.StatusTooManyRequests {
		t.Fatalf("sixth attempt: got %d, want 429", status)
	}
}

// Routes reachable without an account share or own a per-IP probe budget.
func TestUnauthenticatedRoutesAreRateLimited(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	routes.ConfigureRateLimits(0, 1, 0)
	t.Cleanup(func() { routes.ConfigureRateLimits(0, 0, 0) })

	// A slug lookup through any door spends the one enumeration budget.
	api.E.POST("/api/public/links/no-such-slug").WithJSON(map[string]any{}).
		Expect().Status(http.StatusNotFound)
	api.E.Request("PROPFIND", "/dav/s/no-such-slug").
		Expect().Status(http.StatusTooManyRequests).
		JSON().Object().Value("code").String().IsEqual(util.Errors.RateLimited.ErrorCode)

	for _, path := range []string{"/api/server", "/api/certificate/no-such-id", "/oidc/authorize"} {
		if status := api.E.GET(path).Expect().Raw().StatusCode; status == http.StatusTooManyRequests {
			t.Fatalf("%s: first request refused", path)
		}
		api.E.GET(path).Expect().Status(http.StatusTooManyRequests)
	}
}

// One account must not be able to flood a request's owner with answers, each
// of which notifies them and may call their callback.
func TestRequestAnswersAreRateLimitedPerAccount(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	routes.ConfigureSubmissionRateLimit(1)
	t.Cleanup(func() { routes.ConfigureSubmissionRateLimit(0) })

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()
	identityID, _ := newIdentity(t, baseURL, token, "rl-id", userID, wsID)
	slug, _ := setupRequest(t, baseURL, token, userID, wsID, identityID, map[string]any{})

	_, responderToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed: %v", err)
	}
	for i, want := range []int{http.StatusOK, http.StatusTooManyRequests} {
		status := api.E.POST("/api/public/requests/"+slug).
			WithHeader("Authorization", responderToken).
			WithJSON(map[string]any{"data": map[string]any{"hello": "world"}}).
			Expect().Raw().StatusCode
		if status != want {
			t.Fatalf("answer %d: got %d, want %d", i+1, status, want)
		}
	}
}
