package tests

import (
	"net/http"
	"revoked/cmd/revoked/routes"
	"revoked/tests/testutils"
	"revoked/util"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/pocketbase/dbx"
)

// Regression tests for SEC-1..SEC-9 (excluding SEC-8, a rule-precedence bug
// covered by TestAccessRegistryMatchesRules): each one fails against the pre-fix code,
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

// SEC-8: audit snapshots must never retain secret material. The hook stores
// each write's record as JSON, so without redaction a vault value or a
// submitted gate password persists in plaintext under auditLogs — readable
// long after the secret itself was rotated or revoked.
func TestAuditLogsNeverRetainSecrets(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)

	// Canaries: unique enough that finding one in a snapshot is proof of a leak.
	const (
		valueV1    = "sk-audit-canary-original-77f1"
		valueV2    = "sk-audit-canary-rotated-b3c9"
		passwordV1 = "gate-audit-canary-original-4d20"
		passwordV2 = "gate-audit-canary-rotated-9e57"
	)

	recID := extractID(t, baseURL, util.Coll.Records, token, map[string]any{
		util.Fields.Record.Key:       "audit-canary",
		util.Fields.Record.Value:     valueV1,
		util.Fields.Record.Label:     "Audit canary",
		util.Fields.Record.Type:      "text",
		util.Fields.Record.Format:    "default",
		util.Fields.Record.User:      userID,
		util.Fields.Record.Workspace: wsID,
	})
	api.Update(util.Coll.Records, recID, token, map[string]any{
		util.Fields.Record.Value: valueV2,
	}).Expect().Status(http.StatusOK)

	identityID, _ := newIdentity(t, baseURL, token, "audit-canary-id", userID, wsID)
	linkID := extractID(t, baseURL, util.Coll.Links, token, map[string]any{
		util.Fields.Link.Slug:      "audit-canary-" + uuid.New().String()[:8],
		util.Fields.Link.Label:     "Audit canary link",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      userID,
		util.Fields.Link.Workspace: wsID,
		util.Fields.Link.Identity:  identityID,
		util.Fields.Link.Password:  passwordV1,
		util.Fields.Link.Records:   []string{recID},
	})
	api.Update(util.Coll.Links, linkID, token, map[string]any{
		util.Fields.Link.Password: passwordV2,
	}).Expect().Status(http.StatusOK)

	rows, err := app.FindAllRecords(util.Coll.AuditLogs,
		dbx.HashExp{util.Fields.AuditLog.Workspace: wsID})
	if err != nil {
		t.Fatalf("Failed to read audit logs: %v", err)
	}
	if len(rows) < 4 {
		t.Fatalf("expected audit rows for 2 creates + 2 updates, found %d", len(rows))
	}

	for _, row := range rows {
		snapshot := row.GetString(util.Fields.AuditLog.OldData) +
			row.GetString(util.Fields.AuditLog.NewData)
		for _, canary := range []string{valueV1, valueV2, passwordV1, passwordV2} {
			if strings.Contains(snapshot, canary) {
				t.Fatalf("audit row %s (%s %s) retained a secret: %s",
					row.Id,
					row.GetString(util.Fields.AuditLog.Action),
					row.GetString(util.Fields.AuditLog.Collection),
					canary)
			}
		}
	}

	// Redaction must not blank the trail: the record's create row still names
	// what changed, with the secret replaced by the marker.
	for _, row := range rows {
		if row.GetString(util.Fields.AuditLog.Collection) != util.Coll.Records ||
			row.GetString(util.Fields.AuditLog.Action) != "create" {
			continue
		}
		newData := row.GetString(util.Fields.AuditLog.NewData)
		if !strings.Contains(newData, util.AuditRedacted) {
			t.Fatalf("record create snapshot lacks the redaction marker: %s", newData)
		}
		if !strings.Contains(newData, "Audit canary") {
			t.Fatalf("record create snapshot lost its non-secret fields: %s", newData)
		}
		return
	}
	t.Fatal("no audit row found for the record create")
}

// SEC-9: a refused gate must actually stop the submission, not merely describe the
// refusal. The gate helpers write their own response and report a bool, because
// re.JSON reports success as a nil error: a gate that returned what it wrote
// told its caller the check had passed, and every handshake refusal — missing
// signature, wrong signature, spent nonce — was answered with the right status
// code while the submission went through and the identity was attributed.
func TestRefusedHandshakeDoesNotRecordTheSubmission(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, kp := newIdentity(t, baseURL, token, "gate-holds", userID, wsID)
	slug, requestID := setupRequest(t, baseURL, token, userID, wsID, identityID, map[string]any{
		util.Fields.Request.RequireHandshake: true,
	})

	pub := testutils.NewPBClient(t, baseURL)

	submissionCount := func() int {
		t.Helper()
		links, err := app.FindRecordsByFilter(util.Coll.Links,
			util.Fields.Link.Request+" = {:request}", "", 0, 0,
			map[string]any{"request": requestID})
		if err != nil {
			t.Fatalf("counting submissions: %v", err)
		}
		return len(links)
	}

	// No proof at all.
	pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
		"identityId": identityID,
		"data":       map[string]any{"unsigned": true},
	}).Expect().Status(http.StatusUnauthorized)
	if n := submissionCount(); n != 0 {
		t.Fatalf("an unsigned submission was recorded (%d)", n)
	}

	// A real nonce, signed by the wrong key.
	nonce := pub.E.GET("/api/challenges/request/"+slug).
		WithQuery("identityId", identityID).
		Expect().Status(http.StatusOK).
		JSON().Object().Value("nonce").String().Raw()
	impostor := testutils.NewTestIdentity(t, "impostor")

	pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
		"identityId":         identityID,
		"challengeNonce":     nonce,
		"challengeSignature": impostor.SignChallenge(t, nonce),
		"data":               map[string]any{"forged": true},
	}).Expect().Status(http.StatusUnauthorized)
	if n := submissionCount(); n != 0 {
		t.Fatalf("a forged signature was recorded (%d)", n)
	}

	// A garbage handshake token.
	pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
		"identityId":     identityID,
		"handshakeToken": "garbage",
		"data":           map[string]any{"stolen-token": true},
	}).Expect().Status(http.StatusUnauthorized)
	if n := submissionCount(); n != 0 {
		t.Fatalf("a bogus handshake token was recorded (%d)", n)
	}

	// The genuine holder still gets through, so the gate is refusing on proof
	// rather than refusing everything.
	good := pub.E.GET("/api/challenges/request/"+slug).
		WithQuery("identityId", identityID).
		Expect().Status(http.StatusOK).
		JSON().Object().Value("nonce").String().Raw()
	pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
		"identityId":         identityID,
		"challengeNonce":     good,
		"challengeSignature": kp.SignChallenge(t, good),
		"data":               map[string]any{"genuine": true},
	}).Expect().Status(http.StatusOK)
	if n := submissionCount(); n != 1 {
		t.Fatalf("the genuine submission was not recorded (%d)", n)
	}
}
