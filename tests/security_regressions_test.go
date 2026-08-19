package tests

import (
	"net/http"
	"revoked/cmd/revoked/routes"
	"revoked/tests/testutils"
	"revoked/util"
	"strings"
	"testing"

	"github.com/google/uuid"
)

// Regression tests for SEC-1..SEC-7: each one fails against the pre-fix code,
// so deleting it reopens the vulnerability it names.

// SEC-1: /api/certificate must never expose the CA private key that signs every
// identity certificate.
func TestCertificateEndpointNeverExposesPrivateKey(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	body := api.E.GET("/api/certificate").
		Expect().Status(http.StatusOK).JSON().Object()

	body.NotContainsKey("privateKey")
	body.ContainsKey("certificate")
	body.ContainsKey("publicKey")

	// Belt and braces: no PEM private-key block under any other field name.
	raw := body.Raw()
	for _, marker := range []string{"PRIVATE KEY", "RSA PRIVATE KEY"} {
		for k, v := range raw {
			if s, ok := v.(string); ok && strings.Contains(s, marker) {
				t.Fatalf("field %q leaks a private key block (%q)", k, marker)
			}
		}
	}
}

// SEC-2: a link slug must not be derivable from the request slug, or holding a
// request slug enumerates every responder's answers.
func TestGrantLinkSlugIsNotDerivableFromRequest(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().
		Status(http.StatusOK).JSON().Object().
		Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "grant-slug-id", userID, wsID)

	requestSlug := "collect" + strings.ReplaceAll(uuid.New().String()[:6], "-", "")
	extractID(t, baseURL, util.Coll.Requests, token, map[string]any{
		util.Fields.Request.Slug:      requestSlug,
		util.Fields.Request.Label:     "Collect data",
		util.Fields.Request.Status:    util.StatusActive,
		util.Fields.Request.Identity:  identityID,
		util.Fields.Request.User:      userID,
		util.Fields.Request.Workspace: wsID,
	})

	// Submit anonymously so a response link gets minted.
	api.E.POST("/api/public/requests/" + requestSlug).
		WithJSON(map[string]any{
			"data": map[string]any{"favourite_colour": "blue"},
		}).
		Expect().Status(http.StatusOK).JSON().Object().Value("ok").Boolean().IsTrue()

	// The old scheme put the first response at grant_<slug>_1.
	guessed := "grant_" + requestSlug + "_1"
	api.E.GET("/api/public/links/" + guessed).
		Expect().Status(http.StatusNotFound)
	api.E.GET("/s/" + guessed).
		Expect().Status(http.StatusNotFound)
}

// SEC-3: a link or request must not reference a foreign identity. Identity ids
// are public, so an attacker could otherwise borrow a victim's verified
// identity and pass the responder's DNS trust check.
func TestCannotAttachForeignIdentityToLinkOrRequest(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	victimID, victimToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create victim: %v", err)
	}
	victimWS := api.Get(util.Coll.Users, victimID, victimToken).Expect().
		Status(http.StatusOK).JSON().Object().
		Value(util.Fields.User.ActiveWorkspace).String().Raw()
	victimIdentity, _ := newIdentity(t, baseURL, victimToken, "victim-id", victimID, victimWS)

	attackerID, attackerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create attacker: %v", err)
	}
	attackerWS := api.Get(util.Coll.Users, attackerID, attackerToken).Expect().
		Status(http.StatusOK).JSON().Object().
		Value(util.Fields.User.ActiveWorkspace).String().Raw()

	t.Run("request cannot borrow another workspace's identity", func(t *testing.T) {
		api := api.T(t)
		api.AssertStatus(api.Create(util.Coll.Requests, attackerToken, map[string]any{
			util.Fields.Request.Slug:      "phish-" + uuid.New().String()[:6],
			util.Fields.Request.Label:     "Totally legitimate",
			util.Fields.Request.Status:    util.StatusActive,
			util.Fields.Request.Identity:  victimIdentity,
			util.Fields.Request.User:      attackerID,
			util.Fields.Request.Workspace: attackerWS,
		}), http.StatusForbidden)
	})

	t.Run("link cannot borrow another workspace's identity", func(t *testing.T) {
		api := api.T(t)
		api.AssertStatus(api.Create(util.Coll.Links, attackerToken, map[string]any{
			util.Fields.Link.Slug:      "phish-" + uuid.New().String()[:6],
			util.Fields.Link.Label:     "Totally legitimate",
			util.Fields.Link.Status:    util.StatusActive,
			util.Fields.Link.Identity:  victimIdentity,
			util.Fields.Link.User:      attackerID,
			util.Fields.Link.Workspace: attackerWS,
		}), http.StatusForbidden)
	})

	t.Run("link cannot be repointed at a foreign identity on update", func(t *testing.T) {
		api := api.T(t)
		ownIdentity, _ := newIdentity(t, baseURL, attackerToken, "attacker-id", attackerID, attackerWS)
		linkID := extractID(t, baseURL, util.Coll.Links, attackerToken, map[string]any{
			util.Fields.Link.Slug:      "ownlink-" + uuid.New().String()[:6],
			util.Fields.Link.Label:     "Own link",
			util.Fields.Link.Status:    util.StatusActive,
			util.Fields.Link.Identity:  ownIdentity,
			util.Fields.Link.User:      attackerID,
			util.Fields.Link.Workspace: attackerWS,
		})

		api.AssertStatus(api.Update(util.Coll.Links, linkID, attackerToken, map[string]any{
			util.Fields.Link.Identity: victimIdentity,
		}), http.StatusForbidden)
	})
}

// SEC-4 / SRV-1: a record attached to an active link must not become readable
// by id — that bypasses the link's own password gate.
func TestRecordsAreNotReadableByIdThroughAnActiveLink(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().
		Status(http.StatusOK).JSON().Object().
		Value(util.Fields.User.ActiveWorkspace).String().Raw()

	recordID := extractID(t, baseURL, util.Coll.Records, token, map[string]any{
		util.Fields.Record.Key:       "secret_key",
		util.Fields.Record.Value:     "s3cret-value",
		util.Fields.Record.Label:     "Secret",
		util.Fields.Record.Type:      util.TypeText,
		util.Fields.Record.Format:    util.FormatDefault,
		util.Fields.Record.User:      userID,
		util.Fields.Record.Workspace: wsID,
	})

	extractID(t, baseURL, util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      "gated-" + uuid.New().String()[:6],
		util.Fields.Link.Label:     "Gated link",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.Password:  "correct horse battery staple",
		util.Fields.Link.Records:   []string{recordID},
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
	})

	api.E.GET("/api/collections/" + util.Coll.Records + "/records/" + recordID).
		Expect().Status(http.StatusNotFound)

	api.Get(util.Coll.Records, recordID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Record.Value).String().IsEqual("s3cret-value")
}

// SEC-5: the server fetches callbackUrl itself, so loopback and link-local
// (cloud metadata) targets must be refused.
func TestCallbackURLRejectsInternalTargets(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().
		Status(http.StatusOK).JSON().Object().
		Value(util.Fields.User.ActiveWorkspace).String().Raw()
	identityID, _ := newIdentity(t, baseURL, token, "cb-id", userID, wsID)

	blocked := []string{
		"http://127.0.0.1:8090/admin",
		"http://169.254.169.254/latest/meta-data/",
		"file:///etc/passwd",
		"gopher://127.0.0.1:11211/_stats",
	}

	for _, target := range blocked {
		t.Run(target, func(t *testing.T) {
			api := api.T(t)
			api.AssertStatus(api.Create(util.Coll.Requests, token, map[string]any{
				util.Fields.Request.Slug:        "cb" + strings.ReplaceAll(uuid.New().String()[:8], "-", ""),
				util.Fields.Request.Label:       "Callback test",
				util.Fields.Request.Status:      util.StatusActive,
				util.Fields.Request.Identity:    identityID,
				util.Fields.Request.CallbackUrl: target,
				util.Fields.Request.User:        userID,
				util.Fields.Request.Workspace:   wsID,
			}), http.StatusBadRequest)
		})
	}
}

// SEC-6: the maxViews cap must be consumed atomically, or a maxViews=1 link can
// be read more than once.
func TestMaxViewsIsEnforcedExactlyOnce(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().
		Status(http.StatusOK).JSON().Object().
		Value(util.Fields.User.ActiveWorkspace).String().Raw()

	recordID := extractID(t, baseURL, util.Coll.Records, token, map[string]any{
		util.Fields.Record.Key:       "once_key",
		util.Fields.Record.Value:     "read-once",
		util.Fields.Record.Label:     "Once",
		util.Fields.Record.Type:      util.TypeText,
		util.Fields.Record.Format:    util.FormatDefault,
		util.Fields.Record.User:      userID,
		util.Fields.Record.Workspace: wsID,
	})

	slug := "once-" + uuid.New().String()[:6]
	extractID(t, baseURL, util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "Read once",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.MaxViews:  1,
		util.Fields.Link.Records:   []string{recordID},
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
	})

	api.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{}).
		Expect().Status(http.StatusOK)

	for i := 0; i < 3; i++ {
		resp := api.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{}).Expect()
		if code := resp.Raw().StatusCode; code == http.StatusOK {
			t.Fatalf("read %d of a maxViews=1 link succeeded; the cap was not enforced", i+2)
		}
	}
}

// SEC-7: the password gate must be throttled, or a link password can be ground
// down over HTTP. The suite disables rate limiting globally (one shared loopback
// bucket), so this test re-enables a small budget for its duration.
func TestPasswordGateIsRateLimited(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	const attempts = 3
	routes.ConfigureRateLimits(attempts, 0, 0)
	t.Cleanup(func() { routes.ConfigureRateLimits(0, 0, 0) })

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().
		Status(http.StatusOK).JSON().Object().
		Value(util.Fields.User.ActiveWorkspace).String().Raw()

	slug := "brute-" + uuid.New().String()[:6]
	extractID(t, baseURL, util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "Brute force me",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.Password:  "correct horse battery staple",
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
	})

	for i := 0; i < attempts; i++ {
		api.E.POST("/api/public/links/" + slug).
			WithJSON(map[string]any{"password": "wrong-guess"}).
			Expect().Status(http.StatusUnauthorized)
	}

	api.E.POST("/api/public/links/" + slug).
		WithJSON(map[string]any{"password": "wrong-guess"}).
		Expect().Status(http.StatusTooManyRequests).
		JSON().Object().Value("code").String().IsEqual(util.Errors.RateLimited.ErrorCode)
}
