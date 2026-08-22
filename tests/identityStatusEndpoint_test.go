package tests

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/tests/testutils"
	"revoked/util"
)

// testDomain is what the harness boots the root key with.
const testDomain = "test.invalid"

func fetchStatusAssertion(t *testing.T, api *testutils.PBClient, fingerprint string) server.IdentityStatusAssertion {
	t.Helper()
	raw := api.E.GET("/api/identities/" + fingerprint + "/status").
		Expect().Status(http.StatusOK).Body().Raw()

	var assertion server.IdentityStatusAssertion
	if err := json.Unmarshal([]byte(raw), &assertion); err != nil {
		t.Fatalf("decoding the status answer: %v", err)
	}
	return assertion
}

func serverRootPublicKey(t *testing.T, api *testutils.PBClient) string {
	t.Helper()
	return api.E.GET("/api/server").Expect().Status(http.StatusOK).
		JSON().Object().Value("assertion").Object().
		Value("body").Object().Value("publicKey").String().Raw()
}

// The endpoint answers about an identity's standing, and the answer verifies
// under the same DNS-pinned root key that signed the identity in the first
// place — so a verifier needs no separate trust in the endpoint itself.
func TestIdentityStatusEndpointAnswersAndIsSigned(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "status-endpoint", userID, wsID)
	fingerprint := api.Get(util.Coll.Identities, identityID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Identity.Fingerprint).String().Raw()

	rootPub := serverRootPublicKey(t, api)

	// Read the clock at each verification, not once up front: a verifier checks
	// an answer when it receives it, and freezing time across two round trips
	// made this fail whenever the revoke crossed a second boundary.
	active := fetchStatusAssertion(t, api, fingerprint)
	activeBody, err := server.VerifyIdentityStatus(active, rootPub, testDomain, fingerprint, time.Now())
	if err != nil {
		t.Fatalf("the status answer did not verify under the server's root key: %v", err)
	}
	if activeBody.Status != server.IdentityStatusActive {
		t.Fatalf("a live identity reported %q", activeBody.Status)
	}

	revokeIdentity(t, api, identityID, token, util.RevocationMembershipEnded)

	revoked := fetchStatusAssertion(t, api, fingerprint)
	revokedBody, err := server.VerifyIdentityStatus(revoked, rootPub, testDomain, fingerprint, time.Now())
	if err != nil {
		t.Fatalf("the revoked answer did not verify: %v", err)
	}
	if revokedBody.Status != server.IdentityStatusRevoked {
		t.Fatalf("a revoked identity reported %q", revokedBody.Status)
	}
	if revokedBody.RevokedAt == 0 {
		t.Fatal("a revoked answer carried no revocation time")
	}
}

// Deleting the row must not turn a revocation into silence: the tombstone keeps
// the fingerprint answerable, which is what lets a verifier fail closed.
func TestIdentityStatusSurvivesDeletion(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "status-deleted", userID, wsID)
	fingerprint := api.Get(util.Coll.Identities, identityID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Identity.Fingerprint).String().Raw()

	api.Delete(util.Coll.Identities, identityID, token).Expect().Status(http.StatusNoContent)

	answer := fetchStatusAssertion(t, api, fingerprint)
	body, err := server.VerifyIdentityStatus(answer, serverRootPublicKey(t, api), testDomain, fingerprint, time.Now())
	if err != nil {
		t.Fatalf("the tombstone answer did not verify: %v", err)
	}
	if body.Status != server.IdentityStatusRevoked {
		t.Fatalf("a deleted identity answered %q, want revoked", body.Status)
	}
}

// A fingerprint this server never issued gets a signed "unknown" — distinct
// from revoked, and distinct from an unreachable server. Answering uniformly
// also keeps the endpoint from confirming which identities exist.
func TestIdentityStatusAnswersUnknownUniformly(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	stranger := strings.Repeat("9c", 32)
	answer := fetchStatusAssertion(t, api, stranger)
	body, err := server.VerifyIdentityStatus(answer, serverRootPublicKey(t, api), testDomain, stranger, time.Now())
	if err != nil {
		t.Fatalf("the unknown answer did not verify: %v", err)
	}
	if body.Status != server.IdentityStatusUnknown {
		t.Fatalf("an unheard-of fingerprint answered %q, want unknown", body.Status)
	}
}

// The endpoint signs statements about caller-supplied input, so it only accepts
// the one shape a fingerprint can take.
func TestIdentityStatusRejectsMalformedFingerprints(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	for _, bad := range []string{"nothex", strings.Repeat("ab", 40), strings.Repeat("ab", 20)} {
		body := api.E.GET("/api/identities/" + bad + "/status").
			Expect().Status(http.StatusBadRequest).JSON().Object()
		body.Value("code").String().IsEqual(util.Errors.IdentityFingerprintInvalid.ErrorCode)
	}

	// Case is normalized at the edge, and the signed body always carries the
	// canonical lowercase form — otherwise two spellings of one fingerprint
	// would produce two differently-signed statements about the same identity.
	upper := strings.Repeat("AB", 32)
	answer := fetchStatusAssertion(t, api, upper)
	body, err := server.VerifyIdentityStatus(answer, serverRootPublicKey(t, api), testDomain, upper, time.Now())
	if err != nil {
		t.Fatalf("an answer to an uppercase query did not verify: %v", err)
	}
	if body.Fingerprint != strings.ToLower(upper) {
		t.Fatalf("the signed body carried %q, want the canonical lowercase form", body.Fingerprint)
	}
}

// The probe staples the issuer's current word alongside the identity, so the
// single-server case costs no extra round-trip.
func TestPublicProbeStaplesTheIdentityStatus(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "stapled", userID, wsID)
	fingerprint := api.Get(util.Coll.Identities, identityID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.Identity.Fingerprint).String().Raw()

	slug, _ := setupRequest(t, baseURL, token, userID, wsID, identityID, nil)

	pub := testutils.NewPBClient(t, baseURL)
	probe := pub.E.GET("/api/public/requests/" + slug).
		Expect().Status(http.StatusOK).JSON().Object()

	requester := probe.Value("requester").Object()
	requester.Value("status").String().IsEqual(util.StatusActive)

	raw, err := json.Marshal(requester.Value("statusAssertion").Object().Raw())
	if err != nil {
		t.Fatalf("re-encoding the stapled assertion: %v", err)
	}
	var stapled server.IdentityStatusAssertion
	if err := json.Unmarshal(raw, &stapled); err != nil {
		t.Fatalf("decoding the stapled assertion: %v", err)
	}
	if _, err := server.VerifyIdentityStatus(stapled, serverRootPublicKey(t, api), testDomain, fingerprint, time.Now()); err != nil {
		t.Fatalf("the stapled assertion did not verify: %v", err)
	}

	revokeIdentity(t, api, identityID, token, util.RevocationManual)

	after := pub.E.GET("/api/public/requests/" + slug).
		Expect().Status(http.StatusOK).JSON().Object().Value("requester").Object()
	after.Value("status").String().IsEqual(util.StatusRevoked)

	rawAfter, err := json.Marshal(after.Value("statusAssertion").Object().Raw())
	if err != nil {
		t.Fatalf("re-encoding: %v", err)
	}
	var stapledAfter server.IdentityStatusAssertion
	if err := json.Unmarshal(rawAfter, &stapledAfter); err != nil {
		t.Fatalf("decoding: %v", err)
	}
	afterBody, err := server.VerifyIdentityStatus(
		stapledAfter, serverRootPublicKey(t, api), testDomain, fingerprint, time.Now())
	if err != nil {
		t.Fatalf("the re-stapled assertion did not verify: %v", err)
	}
	if afterBody.Status != server.IdentityStatusRevoked {
		t.Fatalf("the stapled assertion still says %q after revocation", afterBody.Status)
	}
}
