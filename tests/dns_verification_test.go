package tests

import (
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"revoked/cmd/revoked/server"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"
	"time"
)

// /api/server must return a shape clients can use end-to-end: the assertion has
// to round-trip through the canonical VerifyAssertion helper.
func TestServerInfoEndpoint(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	pub := testutils.NewPBClient(t, baseURL)

	resp := pub.E.GET("/api/server").Expect().Status(http.StatusOK).JSON().Object()
	resp.Value("domain").String().IsEqual("test.invalid")
	fp := resp.Value("fingerprint").String().NotEmpty().Raw()
	resp.Value("publicKey").String().Contains("BEGIN PUBLIC KEY")

	txt := resp.Value("txt").Object()
	txt.Value("host").String().IsEqual("_revoked.test.invalid")
	txt.Value("value").String().IsEqual("v=revoked1; k=sha256/" + fp)

	rawAssertion := resp.Value("assertion").Object().Raw()
	b, err := json.Marshal(rawAssertion)
	if err != nil {
		t.Fatalf("marshal assertion: %v", err)
	}
	var a server.Assertion
	if err := json.Unmarshal(b, &a); err != nil {
		t.Fatalf("unmarshal assertion: %v", err)
	}
	if err := server.VerifyAssertion(a, time.Now()); err != nil {
		t.Fatalf("assertion failed verification: %v", err)
	}
	if a.Body.Domain != "test.invalid" {
		t.Errorf("assertion domain = %q", a.Body.Domain)
	}
}

// The create hook must stamp parentSignature + domainAtIssue and the signature
// must verify under the root key from /api/server — the same check clients run
// before showing an identity as domain-verified.
func TestIdentitySigning(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "dns-id", userID, wsID)

	id := api.Get(util.Coll.Identities, identityID, token).Expect().
		Status(http.StatusOK).JSON().Object()
	fp := id.Value(util.Fields.Identity.Fingerprint).String().NotEmpty().Raw()
	sigHex := id.Value(util.Fields.Identity.ParentSignature).String().NotEmpty().Raw()
	id.Value(util.Fields.Identity.DomainAtIssue).String().IsEqual("test.invalid")

	pub := testutils.NewPBClient(t, baseURL)
	info := pub.E.GET("/api/server").Expect().Status(http.StatusOK).JSON().Object()
	pubPEM := info.Value("publicKey").String().Raw()

	block, _ := pem.Decode([]byte(pubPEM))
	if block == nil {
		t.Fatal("publicKey is not PEM")
	}
	pubAny, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		t.Fatalf("parse pubkey: %v", err)
	}
	rsaPub, ok := pubAny.(*rsa.PublicKey)
	if !ok {
		t.Fatal("pubkey is not RSA")
	}
	sig, err := hex.DecodeString(sigHex)
	if err != nil {
		t.Fatalf("decode signature: %v", err)
	}
	digest := sha256.Sum256([]byte(fp))
	if err := rsa.VerifyPKCS1v15(rsaPub, crypto.SHA256, digest[:], sig); err != nil {
		t.Fatalf("identity signature does not verify under server root key: %v", err)
	}
}

// The probe must carry everything a receiving client needs to verify the
// requester domain without an extra round-trip.
func TestPublicRequestProbeIncludesServerClaim(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	identityID, _ := newIdentity(t, baseURL, token, "probe-id", userID, wsID)

	slug, _ := setupRequest(t, baseURL, token, userID, wsID, identityID, map[string]any{})

	pub := testutils.NewPBClient(t, baseURL)
	probe := pub.E.GET("/api/public/requests/" + slug).Expect().
		Status(http.StatusOK).JSON().Object()

	srv := probe.Value("server").Object()
	srv.Value("domain").String().IsEqual("test.invalid")
	srv.Value("rootFingerprint").String().NotEmpty()

	requester := probe.Value("requester").Object()
	requester.Value("identityId").String().IsEqual(identityID)
	requester.Value("fingerprint").String().NotEmpty()
	requester.Value("parentSignature").String().NotEmpty()
	requester.Value("domainAtIssue").String().IsEqual("test.invalid")
}
