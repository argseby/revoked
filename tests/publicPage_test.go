package tests

import (
	"net/http"
	"strings"
	"testing"

	"revoked/cmd/revoked/routes"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/google/uuid"
)

const browserAccept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

func pageShare(t *testing.T, baseURL, token, userID, wsID string, extra map[string]any) (string, string) {
	t.Helper()
	recID := extractID(t, baseURL, util.Coll.Records, token, map[string]any{
		util.Fields.Record.Key:       "page-" + uuid.New().String()[:6],
		util.Fields.Record.Value:     "page-canary-value-7f31",
		util.Fields.Record.Label:     "Page canary",
		util.Fields.Record.Type:      util.TypeText,
		util.Fields.Record.Format:    util.FormatDefault,
		util.Fields.Record.User:      userID,
		util.Fields.Record.Workspace: wsID,
	})
	slug := "page-" + uuid.New().String()[:8]
	body := map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "Browser share",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
		util.Fields.Link.Records:   []string{recID},
	}
	for k, v := range extra {
		body[k] = v
	}
	linkID := extractID(t, baseURL, util.Coll.Links, token, body)
	return slug, linkID
}

// The page must not spend a view. Chat apps unfurl every link that passes
// through them, so a page that claimed on load would let a preview bot burn a
// one-view share before the recipient ever opened it.
func TestPublicPageRendersWithoutClaimingAView(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)
	slug, linkID := pageShare(t, baseURL, token, userID, wsID, map[string]any{
		util.Fields.Link.MaxViews: 1,
	})

	for i := 0; i < 3; i++ {
		page := api.E.GET("/s/"+slug).WithHeader("Accept", browserAccept).
			Expect().Status(http.StatusOK)
		page.Header("Content-Type").Contains("text/html")
		// The shell carries no values — only what it takes to ask for them.
		page.Body().NotContains("page-canary-value-7f31")
		// Only the server configured as util.OfficialDomain claims to be it.
		page.Body().NotContains("data-official hidden>")
	}

	api.Get(util.Coll.Links, linkID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Link.ViewCount).Number().IsEqual(0)

	// The reader's explicit request is what claims, and the cap still bites.
	api.E.POST("/api/public/links/" + slug).Expect().Status(http.StatusOK)
	if status := api.E.POST("/api/public/links/" + slug).Expect().Raw().StatusCode; status < 400 {
		t.Fatalf("expected the cap to refuse the second reveal, got %d", status)
	}
}

// A browser gets the page; every tool-shaped request keeps its data contract,
// including a browser that asks for a format explicitly.
func TestPublicPageDoesNotDisplaceTheDataContract(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)
	slug, _ := pageShare(t, baseURL, token, userID, wsID, nil)

	// curl and friends send no Accept, or */*.
	api.E.GET("/s/" + slug).Expect().Status(http.StatusOK).
		Header("Content-Type").Contains("application/json")

	for _, c := range []struct{ suffix, mime string }{
		{".json", "application/json"},
		{".txt", "text/plain"},
		{".csv", "text/csv"},
	} {
		api.E.GET("/s/"+slug+c.suffix).WithHeader("Accept", browserAccept).
			Expect().Status(http.StatusOK).Header("Content-Type").Contains(c.mime)
	}

	api.E.GET("/s/"+slug).WithHeader("Accept", browserAccept).
		WithQuery("key", "nope").Expect().Status(http.StatusNotFound).
		Header("Content-Type").Contains("application/json")
}

// An open share collects nothing. A password-protected one asks for the
// password and nothing else (BROWSER.md §4.4); an identity-protected one hands
// off to the app, which is the only client that can prove an identity.
func TestPublicPageAsksOnlyForASharePassword(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)

	gated, _ := pageShare(t, baseURL, token, userID, wsID, map[string]any{
		util.Fields.Link.Password: "gate-pass-page-9911",
	})
	handshake, _ := pageShare(t, baseURL, token, userID, wsID, map[string]any{
		util.Fields.Link.RequireHandshake: true,
	})
	open, _ := pageShare(t, baseURL, token, userID, wsID, nil)

	page := func(slug string) string {
		return strings.ToLower(api.E.GET("/s/"+slug).WithHeader("Accept", browserAccept).
			Expect().Status(http.StatusOK).Body().Raw())
	}

	for _, slug := range []string{open, handshake} {
		body := page(slug)
		for _, forbidden := range []string{"<input", "<form", "<textarea", `type="password"`} {
			if strings.Contains(body, forbidden) {
				t.Fatalf("a share without a password gate must collect nothing, found %q", forbidden)
			}
		}
	}

	body := page(gated)
	if n := strings.Count(body, "<input"); n != 1 || !strings.Contains(body, `<input id="pw" type="password"`) {
		t.Fatalf("a password-protected share asks for exactly one password, found %d inputs", n)
	}
	for _, forbidden := range []string{"<form", "<textarea", "page-canary-value-7f31"} {
		if strings.Contains(body, forbidden) {
			t.Fatalf("the password page holds %q", forbidden)
		}
	}
	// The password travels in the POST body, never in an address.
	if strings.Contains(body, "?password=") {
		t.Fatalf("the password page puts the password in a URL")
	}
	if !strings.Contains(body, "revoked://s/") {
		t.Fatalf("the password page still offers the app")
	}

	hs := page(handshake)
	if !strings.Contains(hs, "revoked://s/") || strings.Contains(hs, `id="remember"`) {
		t.Fatalf("an identity-protected share must hand off to the app and offer nothing to skip")
	}

	if !strings.Contains(page(open), `role="checkbox"`) {
		t.Fatalf("an open share offers to remember the server")
	}
}

// A password typed on the page unlocks through the endpoint the app uses,
// under its rate limit: a wrong one is refused with the same code as for the
// app, and a right one spends one view.
func TestSharePasswordUnlocksThroughTheAppEndpoint(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)
	slug, linkID := pageShare(t, baseURL, token, userID, wsID, map[string]any{
		util.Fields.Link.Password: "gate-pass-page-9911",
	})

	api.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{"password": "wrong"}).
		Expect().Status(http.StatusUnauthorized).JSON().Object().
		Value("code").String().IsEqual(util.Errors.LinkPasswordInvalid.ErrorCode)
	api.Get(util.Coll.Links, linkID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Link.ViewCount).Number().IsEqual(0)

	api.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{"password": "gate-pass-page-9911"}).
		Expect().Status(http.StatusOK).Body().Contains("page-canary-value-7f31")
	api.Get(util.Coll.Links, linkID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Link.ViewCount).Number().IsEqual(1)

	// The budget the app's attempts spend is the page's too.
	routes.ConfigureRateLimits(2, 0, 0)
	t.Cleanup(func() { routes.ConfigureRateLimits(0, 0, 0) })
	for i := 0; i < 2; i++ {
		api.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{"password": "wrong"}).
			Expect().Status(http.StatusUnauthorized)
	}
	api.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{"password": "wrong"}).
		Expect().Status(http.StatusTooManyRequests)
}

// The page is a capability URL rendered as HTML: it must not be cached, must
// not leak the slug in a referrer, and must not be framed or indexed.
func TestPublicPageCarriesCapabilityHeaders(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)
	slug, _ := pageShare(t, baseURL, token, userID, wsID, nil)

	page := api.E.GET("/s/"+slug).WithHeader("Accept", browserAccept).Expect().Status(http.StatusOK)
	page.Header("Cache-Control").Contains("no-store")
	page.Header("Referrer-Policy").IsEqual("no-referrer")
	page.Header("X-Content-Type-Options").IsEqual("nosniff")
	csp := page.Header("Content-Security-Policy").Raw()
	for _, want := range []string{"default-src 'none'", "frame-ancestors 'none'", "form-action 'none'", "nonce-"} {
		if !strings.Contains(csp, want) {
			t.Fatalf("CSP missing %q: %s", want, csp)
		}
	}
	page.Body().Contains("noindex")
}

// A revoked link reads as a page, not as a JSON error, for the same audience.
func TestPublicPageRendersTerminalStates(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)
	slug, linkID := pageShare(t, baseURL, token, userID, wsID, nil)

	api.Update(util.Coll.Links, linkID, token, map[string]any{
		util.Fields.Link.Status: util.StatusRevoked,
	}).Expect().Status(http.StatusOK)

	gone := api.E.GET("/s/"+slug).WithHeader("Accept", browserAccept).Expect().Status(http.StatusGone)
	gone.Header("Content-Type").Contains("text/html")
	gone.Body().NotContains("page-canary-value-7f31")

	missing := api.E.GET("/s/no-such-slug-here").WithHeader("Accept", browserAccept).
		Expect().Status(http.StatusNotFound)
	missing.Header("Content-Type").Contains("text/html")
}

// The handoff link is the page's only way back to a verifying client, and
// html/template blocks unknown schemes in href unless told otherwise — so a
// plain string here silently renders as "#ZgotmplZ" and the link goes dead.
func TestPublicPageHandoffLinkIsUsable(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)
	slug, _ := pageShare(t, baseURL, token, userID, wsID, nil)

	body := api.E.GET("/s/"+slug).WithHeader("Accept", browserAccept).
		Expect().Status(http.StatusOK).Body()
	body.Contains("revoked://s/")
	body.Contains(slug)
	body.NotContains("ZgotmplZ")
}

func TestPublicPageHandoffPointsWhereTheReaderIs(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)
	slug, _ := pageShare(t, baseURL, token, userID, wsID, nil)

	cases := []struct {
		name, host, wantOrigin string
	}{
		// The harness is the exact shape of the bug: DOMAIN is test.invalid
		// while the data lives on a loopback port.
		{"loopback keeps its port", "localhost:3000", "localhost:3000"},
		{"loopback ip keeps its port", "127.0.0.1:8090", "127.0.0.1:8090"},
		{"the configured domain is kept", "test.invalid", "test.invalid"},
		// A forged Host must not redirect the app at another server, and a
		// lookalike is the whole point of forging one.
		{"foreign host falls back", "evil.example.com", "test.invalid"},
		{"loopback lookalike falls back", "localhost.evil.com", "test.invalid"},
		{"loopback ip lookalike falls back", "127.0.0.1.evil.com", "test.invalid"},
		// The authority reaches a template.URL, which is exempt from the URL
		// sanitizer, so a port that is not a port disqualifies the whole host.
		{"non-numeric port falls back", "localhost:abc", "test.invalid"},
		{"out-of-range port falls back", "localhost:99999", "test.invalid"},
	}
	for _, c := range cases {
		body := api.E.GET("/s/"+slug).
			WithHeader("Accept", browserAccept).
			WithHost(c.host).
			Expect().Status(http.StatusOK).Body().Raw()
		want := "revoked://s/" + c.wantOrigin + "/" + slug
		if !strings.Contains(body, want) {
			t.Fatalf("%s: expected handoff %q in the page", c.name, want)
		}
	}
}

// An end-to-end encrypted entry is opened by the page itself, with the key
// from the part of the address no server is sent. The shell carries the
// reader for that, and the reader needs nothing the policy did not already
// allow: no new host to reach, and no way to run text as code.
func TestPublicPageCarriesTheReaderWithinItsPolicy(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)
	slug, _ := pageShare(t, baseURL, token, userID, wsID, nil)

	page := api.E.GET("/s/"+slug).WithHeader("Accept", browserAccept).Expect().Status(http.StatusOK)
	page.Body().Contains("function sealOpenShare(")
	page.Body().Contains("sealLinkKeyFrom(location.hash)")

	csp := page.Header("Content-Security-Policy").Raw()
	if !strings.Contains(csp, "connect-src 'self' https://cloudflare-dns.com https://dns.google;") {
		t.Fatalf("the page may reach somewhere new: %s", csp)
	}
	for _, widened := range []string{"unsafe-eval", "script-src 'self'", "script-src *", "connect-src *"} {
		if strings.Contains(csp, widened) {
			t.Fatalf("CSP allows %q: %s", widened, csp)
		}
	}
}
