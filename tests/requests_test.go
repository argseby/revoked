package tests

import (
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"
	"time"

	"github.com/google/uuid"
)

// setupRequest bootstraps a request endpoint, overlaying fields on the defaults.
func setupRequest(t *testing.T, baseURL, token, userID, wsID, identityID string, fields map[string]any) (string, string) {
	t.Helper()
	slug := "rq-" + uuid.New().String()[:6]
	payload := map[string]any{
		util.Fields.Request.Slug:      slug,
		util.Fields.Request.Label:     "Test Request",
		util.Fields.Request.Status:    util.StatusActive,
		util.Fields.Request.User:      userID,
		util.Fields.Request.Workspace: wsID,
		util.Fields.Request.Identity:  identityID,
	}
	for k, v := range fields {
		payload[k] = v
	}
	id := extractID(t, baseURL, util.Coll.Requests, token, payload)
	return slug, id
}

func TestRequestsPasswordAndIdentifier(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "rq-id", userID, wsID)

	slug, _ := setupRequest(t, baseURL, token, userID, wsID, identityID, map[string]any{
		util.Fields.Request.Password:   "topsecret",
		util.Fields.Request.Identifier: "must-match-this",
	})

	pub := testutils.NewPBClient(t, baseURL)

	t.Run("Request collection cannot be scanned anonymously", func(t *testing.T) {
		body := pub.E.GET("/api/collections/" + util.Coll.Requests + "/records").
			Expect().Status(http.StatusOK).JSON().Object()
		body.Value("items").Array().Length().IsEqual(0)
	})

	t.Run("Missing password is unauthorized", func(t *testing.T) {
		pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
			"identifier": "must-match-this",
			"data":       map[string]any{"key": "value"},
		}).Expect().Status(http.StatusUnauthorized)
	})

	t.Run("Wrong identifier is rejected", func(t *testing.T) {
		pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
			"password":   "topsecret",
			"identifier": "wrong",
			"data":       map[string]any{"key": "value"},
		}).Expect().Status(http.StatusBadRequest)
	})

	t.Run("Correct password+identifier accepts submission", func(t *testing.T) {
		// Identifier mode requires a guest identity: an ephemeral keypair
		// signing a freshly fetched challenge.
		guest := testutils.NewTestIdentity(t, "guest")
		nonce := pub.E.GET("/api/challenges/request_guest/"+slug).
			WithQuery("guestFingerprint", guest.Fingerprint()).
			Expect().Status(http.StatusOK).
			JSON().Object().Value("nonce").String().Raw()
		sig := guest.SignChallenge(t, nonce)

		body := pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
			"password":           "topsecret",
			"identifier":         "must-match-this",
			"guestCertificate":   guest.CertificatePem,
			"challengeNonce":     nonce,
			"challengeSignature": sig,
			"data":               map[string]any{"x": 1},
		}).Expect().Status(http.StatusOK).JSON().Object()
		body.Value("ok").Boolean().IsTrue()
	})
}

func TestRequestsMaxResponses(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "rq-mr", userID, wsID)

	slug, _ := setupRequest(t, baseURL, token, userID, wsID, identityID, map[string]any{
		util.Fields.Request.MaxResponses: 1,
	})

	pub := testutils.NewPBClient(t, baseURL)
	body := pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
		"data": map[string]any{"first": true},
	}).Expect().Status(http.StatusOK).JSON().Object()
	body.Value("completed").Boolean().IsTrue()

	pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
		"data": map[string]any{"second": true},
	}).Expect().Status(http.StatusGone)
}

func TestRequestsAutoExpire(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "rq-exp", userID, wsID)

	slug, _ := setupRequest(t, baseURL, token, userID, wsID, identityID, map[string]any{
		util.Fields.Request.ExpiresAt: time.Now().Add(-2 * time.Hour).UTC().Format("2006-01-02 15:04:05.000Z"),
	})

	pub := testutils.NewPBClient(t, baseURL)
	resp := pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{}).
		Expect().Status(http.StatusGone).JSON().Object()
	resp.Value("code").String().IsEqual(util.Errors.RequestExpired.ErrorCode)
}

func TestRequestsHandshake(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, kp := newIdentity(t, baseURL, token, "rq-hs", userID, wsID)

	slug, _ := setupRequest(t, baseURL, token, userID, wsID, identityID, map[string]any{
		util.Fields.Request.RequireHandshake: true,
	})

	pub := testutils.NewPBClient(t, baseURL)

	pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
		"identityId": identityID,
		"data":       map[string]any{"first": true},
	}).Expect().Status(http.StatusUnauthorized)

	nonce := pub.E.GET("/api/challenges/request/"+slug).
		WithQuery("identityId", identityID).
		Expect().Status(http.StatusOK).
		JSON().Object().Value("nonce").String().Raw()
	signature := kp.SignChallenge(t, nonce)

	first := pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
		"identityId":         identityID,
		"challengeNonce":     nonce,
		"challengeSignature": signature,
		"data":               map[string]any{"first": true},
	}).Expect().Status(http.StatusOK)

	token1 := first.Header("X-Handshake-Token").Raw()
	if token1 == "" {
		t.Fatal("expected handshake token in response header")
	}

	pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
		"identityId": identityID,
		"data":       map[string]any{"second": true},
	}).Expect().Status(http.StatusUnauthorized)

	pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
		"identityId":     identityID,
		"handshakeToken": token1,
		"data":           map[string]any{"second": true},
	}).Expect().Status(http.StatusOK)

	pub.E.POST("/api/public/requests/" + slug).WithJSON(map[string]any{
		"identityId":     identityID,
		"handshakeToken": "garbage",
		"data":           map[string]any{"third": true},
	}).Expect().Status(http.StatusUnauthorized)
}

func TestCertificateRouteHidesPrivateKey(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "cert-test", userID, wsID)

	pub := testutils.NewPBClient(t, baseURL)
	body := pub.E.GET("/api/certificate/" + identityID).
		Expect().Status(http.StatusOK).JSON().Object()
	body.NotContainsKey(util.Fields.Identity.PrivateKey)
	body.Value("certificate").String().Contains("BEGIN CERTIFICATE")
	body.NotContainsValue("SHOULD_NEVER_LEAK")
}
