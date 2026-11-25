package tests

import (
	"html"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"testing"
	"time"

	"revoked/tests/testutils"
	"revoked/util"
)

// The flow pages (BROWSER.md §4) are server-rendered on the API's own origin
// so a passkey made there works on them, under a policy that lets their
// script reach nothing but that origin.
func TestFlowPagesRender(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	for _, path := range []string{"/r/rq-abc123", "/answers"} {
		page := api.E.GET(path).WithHeader("Accept", browserAccept).Expect().Status(http.StatusOK)
		page.Header("Content-Type").Contains("text/html")
		page.Header("Cache-Control").IsEqual("no-store")
		csp := page.Header("Content-Security-Policy")
		csp.Contains("connect-src 'self'")
		csp.Contains("script-src 'nonce-")
		csp.NotContains("dns.google")
		body := page.Body().Raw()
		nonce := regexp.MustCompile(`script-src 'nonce-([^']+)'`).FindStringSubmatch(page.Header("Content-Security-Policy").Raw())
		script := regexp.MustCompile(`<script nonce="([^"]+)">`).FindStringSubmatch(body)
		if len(nonce) != 2 || len(script) != 2 || html.UnescapeString(script[1]) != nonce[1] {
			t.Fatalf("%s: the page script does not carry the policy's nonce", path)
		}
	}

	page := api.E.GET("/r/rq-abc123").WithHeader("Accept", browserAccept).Expect().Body().Raw()
	if !strings.Contains(page, `revoked:\/\/r\/`) && !strings.Contains(page, `revoked://r/`) {
		t.Fatalf("the request page does not offer the app link")
	}

	// A slug the request collection could never hold is refused without a
	// lookup, and nothing of it is echoed into a script.
	api.E.GET("/r/"+url.PathEscape("x</script><b>")).WithHeader("Accept", browserAccept).
		Expect().Status(http.StatusNotFound).Body().NotContains("</script><b>")
}

// A browser session token is never persisted (BROWSER.md §7). The pages keep
// the theme, the language and the remembered server key in storage, and
// nothing else: a token written anywhere outlives the visit and is the
// easiest thing on the page to steal.
func TestFlowPagesNeverStoreTheSession(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	allowed := map[string]bool{"LANG_KEY": true, "'revoked_theme'": true, "TRUST_KEY": true}
	setItem := regexp.MustCompile(`localStorage\.setItem\(\s*([^,]+),`)
	_, challenge := testutils.PKCEPair()
	connect := url.Values{"client": {"https://tool.example"}, "redirect": {"https://tool.example/"}, "state": {"s"}, "challenge": {challenge}}
	signin := newOIDCService(t, baseURL, "https://game.example").params(nil)
	pages := map[string]string{"/r/rq-abc123": "", "/answers": "", "/s/abc123/identity": "", "/connect": connect.Encode(), "/oidc/authorize": signin.Encode()}
	for path, query := range pages {
		body := api.E.GET(path).WithQueryString(query).WithHeader("Accept", browserAccept).Expect().Status(http.StatusOK).Body().Raw()
		for _, forbidden := range []string{"sessionStorage", "document.cookie", "indexedDB"} {
			if strings.Contains(body, forbidden) {
				t.Errorf("%s uses %s", path, forbidden)
			}
		}
		for _, m := range setItem.FindAllStringSubmatch(body, -1) {
			if !allowed[strings.TrimSpace(m[1])] {
				t.Errorf("%s writes %s to localStorage", path, m[1])
			}
		}
	}
}

// The request page shows when a request stops taking answers, so the probe
// says so.
func TestRequestProbeReportsExpiry(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)
	identityID, _ := newIdentity(t, baseURL, token, "rq-flow", userID, wsID)

	expires := time.Now().Add(72 * time.Hour).UTC().Truncate(time.Second)
	slug, _ := setupRequest(t, baseURL, token, userID, wsID, identityID, map[string]any{
		util.Fields.Request.ExpiresAt: expires.Format("2006-01-02 15:04:05.000Z"),
	})
	api.E.GET("/api/public/requests/" + slug).Expect().Status(http.StatusOK).
		JSON().Object().Value("expiresAt").String().IsEqual(expires.Format(time.RFC3339))

	open, _ := setupRequest(t, baseURL, token, userID, wsID, identityID, nil)
	api.E.GET("/api/public/requests/" + open).Expect().Status(http.StatusOK).
		JSON().Object().Value("expiresAt").String().IsEqual("")
}

// Everything /answers offers runs on the collection endpoints with the
// responder's own session: pausing, resuming and revoking an answer, and
// changing a value it grants. Without these, an answer given in a browser
// would be a frozen snapshot (invariant 12).
func TestResponderManagesAnswerWithoutTheApp(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	ownerID, ownerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, ownerID, ownerToken)
	identityID, _ := newIdentity(t, baseURL, ownerToken, "rq-manage", ownerID, wsID)
	slug, requestID := setupRequest(t, baseURL, ownerToken, ownerID, wsID, identityID, nil)

	responderID, responderToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed: %v", err)
	}
	api.E.POST("/api/public/requests/"+slug).WithHeader("Authorization", responderToken).
		WithJSON(map[string]any{"data": map[string]any{"phone": "+49 30 1234"}}).
		Expect().Status(http.StatusOK)

	// The listing the page makes.
	filter := `user = "` + responderID + `" && request != ""`
	items := api.E.GET("/api/collections/"+util.Coll.Links+"/records").
		WithQuery("filter", filter).WithQuery("perPage", 500).WithQuery("skipTotal", 1).
		WithHeader("Authorization", responderToken).
		Expect().Status(http.StatusOK).JSON().Object().Value("items").Array()
	items.Length().IsEqual(1)
	answer := items.Value(0).Object()
	answer.Value(util.Fields.Link.Request).String().IsEqual(requestID)
	linkID := answer.Value("id").String().Raw()
	recordID := answer.Value(util.Fields.Link.Grants).Object().Value("phone").String().Raw()

	for _, status := range []string{util.StatusPaused, util.StatusActive} {
		api.Update(util.Coll.Links, linkID, responderToken, map[string]any{util.Fields.Link.Status: status}).
			Expect().Status(http.StatusOK).JSON().Object().Value(util.Fields.Link.Status).String().IsEqual(status)
	}

	api.Update(util.Coll.Records, recordID, responderToken, map[string]any{util.Fields.Record.Value: "+49 30 9876"}).
		Expect().Status(http.StatusOK)
	api.Get(util.Coll.Records, recordID, responderToken).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Record.Value).String().IsEqual("+49 30 9876")

	api.Update(util.Coll.Links, linkID, responderToken, map[string]any{util.Fields.Link.Status: util.StatusRevoked}).
		Expect().Status(http.StatusOK)

	// Someone else's session reaches none of it.
	_, strangerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed: %v", err)
	}
	if status := api.Update(util.Coll.Records, recordID, strangerToken, map[string]any{util.Fields.Record.Value: "x"}).
		Expect().Raw().StatusCode; status < 400 {
		t.Fatalf("a stranger changed the responder's value: %d", status)
	}
}

// An account made on the request page has no workspace yet. The page creates
// one and makes it active before answering, as the app's first run does;
// without that step the answer would hold no records of the responder's own
// and its link would sit in the requester's workspace.
func TestBrowserAccountAnswersIntoItsOwnWorkspace(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	ownerID, ownerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed: %v", err)
	}
	ownerWS := activeWorkspaceOf(t, api, ownerID, ownerToken)
	identityID, _ := newIdentity(t, baseURL, ownerToken, "rq-fresh", ownerID, ownerWS)
	slug, _ := setupRequest(t, baseURL, ownerToken, ownerID, ownerWS, identityID, nil)

	device := testutils.NewPasskeyDevice(baseURL)
	fresh, err := device.Register(map[string]any{"email": "fresh-" + slug + "@example.com"})
	if err != nil {
		t.Fatalf("Failed to register: %v", err)
	}
	api.Get(util.Coll.Users, fresh.UserID, fresh.Token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().IsEmpty()

	wsID := api.Create(util.Coll.Workspaces, fresh.Token, map[string]any{
		util.Fields.Workspace.Name: "Personal", util.Fields.Workspace.Slug: "ws-" + slug[3:],
	}).Expect().Status(http.StatusOK).JSON().Object().Value("id").String().Raw()
	api.Update(util.Coll.Users, fresh.UserID, fresh.Token, map[string]any{
		util.Fields.User.ActiveWorkspace: wsID, util.Fields.User.ActiveRole: util.RoleAdmin,
	}).Expect().Status(http.StatusOK)

	api.E.POST("/api/public/requests/"+slug).WithHeader("Authorization", fresh.Token).
		WithJSON(map[string]any{"data": map[string]any{"phone": "+49 30 1234"}}).
		Expect().Status(http.StatusOK)

	link := api.E.GET("/api/collections/"+util.Coll.Links+"/records").
		WithQuery("filter", `user = "`+fresh.UserID+`"`).WithHeader("Authorization", fresh.Token).
		Expect().Status(http.StatusOK).JSON().Object().Value("items").Array().Value(0).Object()
	link.Value(util.Fields.Link.Workspace).String().IsEqual(wsID)
	recordID := link.Value(util.Fields.Link.Grants).Object().Value("phone").String().Raw()
	api.Get(util.Coll.Records, recordID, fresh.Token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Record.Workspace).String().IsEqual(wsID)
}
