package tests

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"io"
	"math/big"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/google/uuid"
)

// The suite runs one server, which plays the attester, the holder's server
// and the verifier at once. Where a second server matters — a credential
// issued elsewhere, an identity issued elsewhere — a fakePeer stands in for
// it over HTTP, with a root key of its own.

type attestationFixture struct {
	baseURL string
	api     *testutils.PBClient

	issuerID, issuerToken, issuerWs string
	holderID, holderToken, holderWs string

	identityID string
	kp         *testutils.IdentityKeyPair
}

func newAttestationFixture(t *testing.T) attestationFixture {
	t.Helper()
	baseURL, _ := testutils.SetupTestApp(t)
	t.Setenv(util.AllowAttestationsEnv, "true")
	enableLoopbackPeers(t, baseURL)
	api := testutils.NewPBClient(t, baseURL)

	issuerID, issuerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create issuer: %v", err)
	}
	holderID, holderToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create holder: %v", err)
	}
	f := attestationFixture{
		baseURL:     baseURL,
		api:         api,
		issuerID:    issuerID,
		issuerToken: issuerToken,
		issuerWs:    activeWorkspaceOf(t, api, issuerID, issuerToken),
		holderID:    holderID,
		holderToken: holderToken,
		holderWs:    activeWorkspaceOf(t, api, holderID, holderToken),
	}
	f.identityID, f.kp = newIdentity(t, baseURL, holderToken, "Ada", holderID, f.holderWs)
	return f
}

// offer creates an attestation and returns its id and one-time token.
func (f attestationFixture) offer(t *testing.T, fields map[string]any) (string, string) {
	t.Helper()
	body := map[string]any{
		util.Fields.Attestation.User:      f.issuerID,
		util.Fields.Attestation.Workspace: f.issuerWs,
		util.Fields.Attestation.Type:      "membership",
		util.Fields.Attestation.Label:     "Membership 2026",
		util.Fields.Attestation.Claims: map[string]any{
			"name": "Ada Lovelace", "age_over_18": true, "member_no": 42,
		},
	}
	for k, v := range fields {
		body[k] = v
	}
	resp := f.api.Create(util.Coll.Attestations, f.issuerToken, body).Expect().Status(http.StatusOK)
	token := resp.Header("X-Attestation-Token").Raw()
	if token == "" {
		t.Fatal("the offer carried no X-Attestation-Token header")
	}
	return resp.JSON().Object().Value("id").String().Raw(), token
}

func (f attestationFixture) challenge(t *testing.T, token, identityID string) string {
	t.Helper()
	return f.api.E.GET("/api/challenges/attestation/"+token).
		WithQuery("identityId", identityID).
		Expect().Status(http.StatusOK).JSON().Object().Value("nonce").String().Raw()
}

func postJSON(t *testing.T, target, auth string, body any) *http.Response {
	t.Helper()
	raw, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPost, target, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	if auth != "" {
		req.Header.Set("Authorization", auth)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST %s: %v", target, err)
	}
	return resp
}

// accept relays the holder's acceptance through their own server, as the app
// does: a challenge from the issuer, signed with the identity key.
func (f attestationFixture) accept(t *testing.T, origin, challengeBase, token string) *http.Response {
	t.Helper()
	var nonce string
	getJSON(t, challengeBase+"/api/challenges/attestation/"+token+"?identityId="+f.identityID, &struct {
		Nonce *string `json:"nonce"`
	}{&nonce})
	return postJSON(t, f.baseURL+"/api/credentials/claim", f.holderToken, map[string]any{
		"origin":             origin,
		"token":              token,
		"identityId":         f.identityID,
		"challengeNonce":     nonce,
		"challengeSignature": f.kp.SignChallenge(t, nonce),
	})
}

// acceptLocal accepts an offer made on the holder's own server.
func (f attestationFixture) acceptLocal(t *testing.T, token string) map[string]any {
	t.Helper()
	resp := f.accept(t, "", f.baseURL, token)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("claim refused: %d %v", resp.StatusCode, decode(t, resp))
	}
	return decode(t, resp)
}

// present makes a presentation with the holder's key, as the app does.
func (f attestationFixture) present(t *testing.T, credential string, disclose []string, audience, nonce string) string {
	t.Helper()
	presentation, err := server.PresentCredential(credential, disclose, audience, nonce, "RS256", time.Now(),
		func(input string) ([]byte, error) { return server.SignRS256(f.kp.PrivateKey, input) })
	if err != nil {
		t.Fatalf("PresentCredential: %v", err)
	}
	return presentation
}

func (f attestationFixture) verify(t *testing.T, presentation, audience, nonce string) map[string]any {
	t.Helper()
	resp := postJSON(t, f.baseURL+"/api/attestations/verify", "", map[string]any{
		"presentation": presentation, "audience": audience, "nonce": nonce,
	})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("verify answered %d: %v", resp.StatusCode, decode(t, resp))
	}
	return decode(t, resp)
}

func (f attestationFixture) credentials(t *testing.T, token string) []any {
	t.Helper()
	return f.api.E.GET("/api/collections/"+util.Coll.Credentials+"/records").
		WithHeader("Authorization", token).
		Expect().Status(http.StatusOK).JSON().Object().Value("items").Array().Raw()
}

func TestAttestationsAreOffUnlessTheOperatorAllowsThem(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	t.Setenv(util.AllowAttestationsEnv, "")
	api := testutils.NewPBClient(t, baseURL)
	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatal(err)
	}
	ws := activeWorkspaceOf(t, api, userID, token)

	api.Create(util.Coll.Attestations, token, map[string]any{
		util.Fields.Attestation.User:      userID,
		util.Fields.Attestation.Workspace: ws,
		util.Fields.Attestation.Type:      "membership",
	}).Expect().Status(http.StatusForbidden).JSON().Object().
		Value("data").Object().Value("attestations").Object().
		Value("code").String().IsEqual(util.Errors.AttestationsDisabled.ErrorCode)

	api.E.GET("/api/server").Expect().Status(http.StatusOK).JSON().Object().
		Value("attestations").Object().Value("issuing").Boolean().IsFalse()
}

func TestAttestationOfferBecomesACredential(t *testing.T) {
	f := newAttestationFixture(t)
	a := util.Fields.Attestation
	id, token := f.offer(t, nil)

	t.Run("the offer is stored without its token", func(t *testing.T) {
		row := f.api.Get(util.Coll.Attestations, id, f.issuerToken).Expect().Status(http.StatusOK).JSON().Object()
		row.Value(a.Status).String().IsEqual(util.StatusOffered)
		row.NotContainsKey(a.OfferTokenHash)
		row.Value(a.OfferExpiresAt).String().NotEmpty()
	})

	t.Run("the offer shows what would be stated, and by whom", func(t *testing.T) {
		probe := f.api.T(t).E.GET("/api/attestations/offers/" + token).
			Expect().Status(http.StatusOK).JSON().Object()
		probe.Value("type").String().IsEqual("membership")
		probe.Value("status").String().IsEqual(util.StatusOffered)
		probe.Value("claims").Object().Value("name").String().IsEqual("Ada Lovelace")
		probe.Value("server").Object().Value("domain").String().IsEqual(testDomain)
		f.api.T(t).E.GET("/api/attestations/offers/not-a-token").Expect().Status(http.StatusNotFound)
	})

	t.Run("accepting needs a signed challenge", func(t *testing.T) {
		resp := postJSON(t, f.baseURL+"/api/credentials/claim", f.holderToken, map[string]any{
			"token": token, "identityId": f.identityID,
		})
		if resp.StatusCode != http.StatusUnauthorized {
			t.Fatalf("status = %d", resp.StatusCode)
		}
		if code := decode(t, resp)["code"]; code != util.Errors.ChallengeRequired.ErrorCode {
			t.Fatalf("code = %v", code)
		}
	})

	t.Run("a challenge signed with another key is refused", func(t *testing.T) {
		nonce := f.challenge(t, token, f.identityID)
		stranger := testutils.NewTestIdentity(t, "stranger")
		resp := postJSON(t, f.baseURL+"/api/credentials/claim", f.holderToken, map[string]any{
			"token": token, "identityId": f.identityID,
			"challengeNonce": nonce, "challengeSignature": stranger.SignChallenge(t, nonce),
		})
		if resp.StatusCode != http.StatusUnauthorized {
			t.Fatalf("status = %d", resp.StatusCode)
		}
		if code := decode(t, resp)["code"]; code != util.Errors.SignatureInvalid.ErrorCode {
			t.Fatalf("code = %v", code)
		}
	})

	t.Run("a nonce this server did not issue is refused", func(t *testing.T) {
		const invented = "0000000000000000000000000000000000000000000000000000000000000000"
		resp := postJSON(t, f.baseURL+"/api/credentials/claim", f.holderToken, map[string]any{
			"token": token, "identityId": f.identityID,
			"challengeNonce": invented, "challengeSignature": f.kp.SignChallenge(t, invented),
		})
		if resp.StatusCode != http.StatusUnauthorized {
			t.Fatalf("status = %d", resp.StatusCode)
		}
		if code := decode(t, resp)["code"]; code != util.Errors.ChallengeInvalid.ErrorCode {
			t.Fatalf("code = %v", code)
		}
	})

	var credential string
	t.Run("the holder receives a credential bound to their identity", func(t *testing.T) {
		rec := f.acceptLocal(t, token)
		c := util.Fields.Credential
		if rec[c.Issuer] != testDomain || rec[c.Type] != "membership" || rec[c.Identity] != f.identityID {
			t.Fatalf("credential record: %v", rec)
		}
		claims, _ := rec[c.Claims].(map[string]any)
		if claims["name"] != "Ada Lovelace" || claims["age_over_18"] != true || claims["member_no"] != float64(42) {
			t.Fatalf("claims = %v", claims)
		}
		credential, _ = rec[c.Credential].(string)
		if !strings.HasSuffix(credential, "~") {
			t.Fatalf("not an issued SD-JWT: %q", credential)
		}
	})

	t.Run("the attestation is active and names its subject", func(t *testing.T) {
		row := f.api.Get(util.Coll.Attestations, id, f.issuerToken).Expect().Status(http.StatusOK).JSON().Object()
		row.Value(a.Status).String().IsEqual(util.StatusActive)
		row.Value(a.SubjectName).String().IsEqual("Ada")
		row.Value(a.SubjectDomain).String().IsEqual(testDomain)
		row.Value(a.SubjectFingerprint).String().Length().IsEqual(64)
		row.Value(a.IssuedAt).String().NotEmpty()

		notes := f.api.T(t).E.GET("/api/collections/"+util.Coll.Notifications+"/records").
			WithHeader("Authorization", f.issuerToken).
			WithQuery("filter", `type = "`+util.NotificationAttestationAccepted+`" && refId = "`+id+`"`).
			Expect().Status(http.StatusOK).JSON().Object()
		notes.Value("totalItems").Number().IsEqual(1)
	})

	t.Run("an accepted offer no longer shows what it states", func(t *testing.T) {
		probe := f.api.T(t).E.GET("/api/attestations/offers/" + token).
			Expect().Status(http.StatusOK).JSON().Object()
		probe.Value("status").String().IsEqual(util.StatusActive)
		probe.NotContainsKey("claims")
	})

	t.Run("another identity cannot accept it a second time", func(t *testing.T) {
		otherID, otherToken, err := testutils.CreateRandomUser(f.baseURL)
		if err != nil {
			t.Fatal(err)
		}
		otherWs := activeWorkspaceOf(t, f.api, otherID, otherToken)
		otherIdentity, otherKp := newIdentity(t, f.baseURL, otherToken, "Mallory", otherID, otherWs)
		nonce := f.challenge(t, token, otherIdentity)
		resp := postJSON(t, f.baseURL+"/api/credentials/claim", otherToken, map[string]any{
			"token": token, "identityId": otherIdentity,
			"challengeNonce": nonce, "challengeSignature": otherKp.SignChallenge(t, nonce),
		})
		if resp.StatusCode != http.StatusGone {
			t.Fatalf("status = %d", resp.StatusCode)
		}
		if code := decode(t, resp)["code"]; code != util.Errors.AttestationOfferClaimed.ErrorCode {
			t.Fatalf("code = %v", code)
		}
		if n := len(f.credentials(t, otherToken)); n != 0 {
			t.Fatalf("the other account holds %d credentials", n)
		}
	})

	t.Run("the same identity may fetch it again, and keeps one copy", func(t *testing.T) {
		again := f.acceptLocal(t, token)
		if again[util.Fields.Credential.Credential] == credential {
			t.Fatal("a reissued credential reused its salts")
		}
		if n := len(f.credentials(t, f.holderToken)); n != 1 {
			t.Fatalf("the holder keeps %d copies", n)
		}
	})

	t.Run("a challenge is spent once", func(t *testing.T) {
		nonce := f.challenge(t, token, f.identityID)
		body := map[string]any{
			"token": token, "identityId": f.identityID,
			"challengeNonce": nonce, "challengeSignature": f.kp.SignChallenge(t, nonce),
		}
		if resp := postJSON(t, f.baseURL+"/api/credentials/claim", f.holderToken, body); resp.StatusCode != http.StatusOK {
			t.Fatalf("first use: %d", resp.StatusCode)
		}
		resp := postJSON(t, f.baseURL+"/api/credentials/claim", f.holderToken, body)
		if resp.StatusCode != http.StatusUnauthorized {
			t.Fatalf("second use: %d", resp.StatusCode)
		}
	})

	t.Run("an identity of someone else cannot be used", func(t *testing.T) {
		_, token2 := f.offer(t, nil)
		nonce := f.challenge(t, token2, f.identityID)
		resp := postJSON(t, f.baseURL+"/api/credentials/claim", f.issuerToken, map[string]any{
			"token": token2, "identityId": f.identityID,
			"challengeNonce": nonce, "challengeSignature": f.kp.SignChallenge(t, nonce),
		})
		if resp.StatusCode != http.StatusForbidden {
			t.Fatalf("status = %d", resp.StatusCode)
		}
	})
}

func TestCredentialsArePersonal(t *testing.T) {
	f := newAttestationFixture(t)
	_, token := f.offer(t, nil)
	rec := f.acceptLocal(t, token)
	credentialID := rec["id"].(string)

	if n := len(f.credentials(t, f.issuerToken)); n != 0 {
		t.Fatalf("the issuer reads %d of the holder's credentials", n)
	}
	f.api.Get(util.Coll.Credentials, credentialID, f.issuerToken).Expect().Status(http.StatusNotFound)

	// Written by the claim route alone: not created or edited through the
	// collection API, not even by their holder.
	f.api.Create(util.Coll.Credentials, f.holderToken, map[string]any{
		util.Fields.Credential.User:       f.holderID,
		util.Fields.Credential.Identity:   f.identityID,
		util.Fields.Credential.Issuer:     "forged.example",
		util.Fields.Credential.Type:       "membership",
		util.Fields.Credential.Credential: "x~",
	}).Expect().Status(http.StatusForbidden)
	f.api.Update(util.Coll.Credentials, credentialID, f.holderToken, map[string]any{
		util.Fields.Credential.Issuer: "forged.example",
	}).Expect().Status(http.StatusForbidden)

	f.api.E.GET("/api/credentials/"+credentialID+"/status").
		WithHeader("Authorization", f.issuerToken).Expect().Status(http.StatusNotFound)
	status := f.api.E.GET("/api/credentials/"+credentialID+"/status").
		WithHeader("Authorization", f.holderToken).Expect().Status(http.StatusOK).JSON().Object()
	status.Value("state").String().IsEqual(services.AttestationVerified)
	status.Value("status").String().IsEqual(services.CredentialStatusValid)
	status.Value("keyBound").Boolean().IsFalse()

	f.api.Delete(util.Coll.Credentials, credentialID, f.holderToken).Expect().Status(http.StatusNoContent)
	if n := len(f.credentials(t, f.holderToken)); n != 0 {
		t.Fatalf("%d credentials left after deleting the only one", n)
	}
}

func TestPresentationIsVerifiedAlongBothChains(t *testing.T) {
	f := newAttestationFixture(t)
	id, token := f.offer(t, nil)
	credential := f.acceptLocal(t, token)[util.Fields.Credential.Credential].(string)
	const audience, nonce = "https://shop.example", "nonce-1"

	t.Run("only what was disclosed is reported, with who attested it", func(t *testing.T) {
		verdict := f.verify(t, f.present(t, credential, []string{"age_over_18"}, audience, nonce), audience, nonce)
		if verdict["state"] != services.AttestationVerified {
			t.Fatalf("verdict = %v", verdict)
		}
		if verdict["issuer"] != testDomain || verdict["type"] != "membership" || verdict["keyBound"] != true {
			t.Fatalf("verdict = %v", verdict)
		}
		claims := verdict["claims"].(map[string]any)
		if len(claims) != 1 || claims["age_over_18"] != true || verdict["withheld"] != float64(2) {
			t.Fatalf("claims = %v, withheld = %v", claims, verdict["withheld"])
		}
		if verdict["status"] != services.CredentialStatusValid {
			t.Fatalf("status = %v", verdict["status"])
		}
		holder := verdict["holder"].(map[string]any)
		if holder["domain"] != testDomain || holder["state"] != services.AttestationVerified {
			t.Fatalf("holder = %v", holder)
		}
	})

	t.Run("without an audience and nonce nothing is called verified", func(t *testing.T) {
		verdict := f.verify(t, f.present(t, credential, nil, audience, nonce), "", "")
		if verdict["state"] != services.AttestationUnverified || verdict["keyBound"] != false {
			t.Fatalf("verdict = %v", verdict)
		}
		// The credential as issued, with no key binding at all.
		verdict = f.verify(t, credential, audience, nonce)
		if verdict["state"] != services.AttestationInvalid || verdict["keyBound"] != false {
			t.Fatalf("verdict = %v", verdict)
		}
	})

	t.Run("a presentation made for another verifier or occasion is refused", func(t *testing.T) {
		presentation := f.present(t, credential, nil, audience, nonce)
		if v := f.verify(t, presentation, "https://other.example", nonce); v["state"] != services.AttestationInvalid {
			t.Fatalf("another audience: %v", v)
		}
		if v := f.verify(t, presentation, audience, "nonce-2"); v["state"] != services.AttestationInvalid {
			t.Fatalf("another nonce: %v", v)
		}
	})

	t.Run("a presentation signed by someone holding a copy is refused", func(t *testing.T) {
		thief := testutils.NewTestIdentity(t, "thief")
		stolen, err := server.PresentCredential(credential, nil, audience, nonce, "RS256", time.Now(),
			func(input string) ([]byte, error) { return server.SignRS256(thief.PrivateKey, input) })
		if err != nil {
			t.Fatal(err)
		}
		if v := f.verify(t, stolen, audience, nonce); v["state"] != services.AttestationInvalid {
			t.Fatalf("verdict = %v", v)
		}
	})

	t.Run("garbage is invalid, not an error", func(t *testing.T) {
		if v := f.verify(t, "not-a-credential", audience, nonce); v["state"] != services.AttestationInvalid {
			t.Fatalf("verdict = %v", v)
		}
	})

	t.Run("the issuer revokes it, and cannot take that back", func(t *testing.T) {
		a := util.Fields.Attestation
		f.api.T(t).Update(util.Coll.Attestations, id, f.issuerToken, map[string]any{
			a.Status: util.StatusRevoked,
		}).Expect().Status(http.StatusOK).JSON().Object().
			Value(a.RevokedAt).String().NotEmpty()

		verdict := f.verify(t, f.present(t, credential, nil, audience, nonce), audience, nonce)
		if verdict["state"] != services.AttestationRevoked || verdict["status"] != services.CredentialStatusRevoked {
			t.Fatalf("verdict = %v", verdict)
		}

		f.api.T(t).Update(util.Coll.Attestations, id, f.issuerToken, map[string]any{
			a.Status: util.StatusActive,
		}).Expect().Status(http.StatusOK).JSON().Object().
			Value(a.Status).String().IsEqual(util.StatusRevoked)
		verdict = f.verify(t, f.present(t, credential, nil, audience, nonce), audience, nonce)
		if verdict["state"] != services.AttestationRevoked {
			t.Fatalf("after reinstating: %v", verdict)
		}

		// A revoked offer is gone for its subject as well.
		f.api.T(t).E.GET("/api/attestations/offers/" + token).Expect().Status(http.StatusGone)
	})
}

// The row can go, with its workspace or by hand; the credential it issued is
// still out there, and must not read as valid because nothing contradicts it.
func TestDeletedAttestationStaysRevoked(t *testing.T) {
	f := newAttestationFixture(t)
	id, token := f.offer(t, nil)
	credential := f.acceptLocal(t, token)[util.Fields.Credential.Credential].(string)
	const audience, nonce = "https://shop.example", "n"

	f.api.Delete(util.Coll.Attestations, id, f.issuerToken).Expect().Status(http.StatusNoContent)
	verdict := f.verify(t, f.present(t, credential, nil, audience, nonce), audience, nonce)
	if verdict["state"] != services.AttestationRevoked {
		t.Fatalf("verdict = %v", verdict)
	}
}

func TestWorkspaceDeletionRevokesItsAttestations(t *testing.T) {
	f := newAttestationFixture(t)
	_, token := f.offer(t, nil)
	credential := f.acceptLocal(t, token)[util.Fields.Credential.Credential].(string)
	const audience, nonce = "https://shop.example", "n"

	f.api.Delete(util.Coll.Workspaces, f.issuerWs, f.issuerToken).Expect().Status(http.StatusNoContent)
	verdict := f.verify(t, f.present(t, credential, nil, audience, nonce), audience, nonce)
	if verdict["state"] != services.AttestationRevoked {
		t.Fatalf("verdict = %v", verdict)
	}
}

// A credential is only as good as the identity it was issued to: when the
// holder's server withdraws that identity, the credential stops verifying.
func TestRevokedHolderIdentityReachesTheVerdict(t *testing.T) {
	f := newAttestationFixture(t)
	_, token := f.offer(t, nil)
	credential := f.acceptLocal(t, token)[util.Fields.Credential.Credential].(string)
	const audience, nonce = "https://shop.example", "n"
	presentation := f.present(t, credential, nil, audience, nonce)

	f.api.Update(util.Coll.Identities, f.identityID, f.holderToken, map[string]any{
		util.Fields.Identity.Status: util.StatusRevoked,
	}).Expect().Status(http.StatusOK)

	verdict := f.verify(t, presentation, audience, nonce)
	if verdict["state"] != services.AttestationRevoked {
		t.Fatalf("verdict = %v", verdict)
	}
	// The credential itself was not revoked; the identity was.
	if verdict["status"] != services.CredentialStatusValid {
		t.Fatalf("status = %v", verdict["status"])
	}
	if holder := verdict["holder"].(map[string]any); holder["state"] != services.AttestationRevoked {
		t.Fatalf("holder = %v", holder)
	}
}

func TestExpiredCredential(t *testing.T) {
	f := newAttestationFixture(t)
	_, token := f.offer(t, map[string]any{
		util.Fields.Attestation.ExpiresAt: time.Now().Add(2 * time.Second).UTC().Format("2006-01-02 15:04:05.000Z"),
	})
	credential := f.acceptLocal(t, token)[util.Fields.Credential.Credential].(string)
	const audience, nonce = "https://shop.example", "n"

	time.Sleep(3 * time.Second)
	verdict := f.verify(t, f.present(t, credential, nil, audience, nonce), audience, nonce)
	if verdict["state"] != services.AttestationExpired || verdict["type"] != "membership" {
		t.Fatalf("verdict = %v", verdict)
	}
	// Past its date, an offer hands out nothing more.
	f.api.E.GET("/api/attestations/offers/" + token).Expect().Status(http.StatusGone)
}

func TestWhatAnAttestationStatesIsFixed(t *testing.T) {
	f := newAttestationFixture(t)
	a := util.Fields.Attestation
	id, _ := f.offer(t, nil)

	for field, value := range map[string]any{
		a.Claims:             map[string]any{"name": "Someone Else"},
		a.Type:               "admin",
		a.SubjectFingerprint: strings.Repeat("a", 64),
		a.ExpiresAt:          "2099-01-01 00:00:00.000Z",
	} {
		f.api.Update(util.Coll.Attestations, id, f.issuerToken, map[string]any{field: value}).
			Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("data").Object().Value(field).Object().
			Value("code").String().IsEqual(util.Errors.AttestationImmutable.ErrorCode)
	}

	f.api.Update(util.Coll.Attestations, id, f.issuerToken, map[string]any{a.Label: "Renamed"}).
		Expect().Status(http.StatusOK).JSON().Object().Value(a.Label).String().IsEqual("Renamed")

	// Only accepting an offer makes it active.
	f.api.Update(util.Coll.Attestations, id, f.issuerToken, map[string]any{a.Status: util.StatusActive}).
		Expect().Status(http.StatusOK).JSON().Object().Value(a.Status).String().IsEqual(util.StatusOffered)
}

func TestAttestationValidation(t *testing.T) {
	f := newAttestationFixture(t)
	a := util.Fields.Attestation
	base := func(fields map[string]any) map[string]any {
		body := map[string]any{a.User: f.issuerID, a.Workspace: f.issuerWs, a.Type: "membership"}
		for k, v := range fields {
			body[k] = v
		}
		return body
	}
	for name, tc := range map[string]struct {
		fields map[string]any
		field  string
		code   string
	}{
		"a type with spaces":    {map[string]any{a.Type: "two words"}, a.Type, util.Errors.AttestationTypeInvalid.ErrorCode},
		"a nested claim":        {map[string]any{a.Claims: map[string]any{"address": map[string]any{"city": "x"}}}, a.Claims, util.Errors.AttestationClaimsInvalid.ErrorCode},
		"a reserved claim":      {map[string]any{a.Claims: map[string]any{"iss": "https://evil.example"}}, a.Claims, util.Errors.AttestationClaimReserved.ErrorCode},
		"the holder claim":      {map[string]any{a.Claims: map[string]any{util.ClaimHolder: "x"}}, a.Claims, util.Errors.AttestationClaimReserved.ErrorCode},
		"a bad claim name":      {map[string]any{a.Claims: map[string]any{"has space": "x"}}, a.Claims, util.Errors.AttestationClaimsInvalid.ErrorCode},
		"a bad fingerprint":     {map[string]any{a.SubjectFingerprint: "abc"}, a.SubjectFingerprint, util.Errors.AttestationSubjectInvalid.ErrorCode},
		"an expiry in the past": {map[string]any{a.ExpiresAt: "2001-01-01 00:00:00.000Z"}, a.ExpiresAt, util.Errors.AttestationExpiryInvalid.ErrorCode},
	} {
		t.Run(name, func(t *testing.T) {
			f.api.T(t).Create(util.Coll.Attestations, f.issuerToken, base(tc.fields)).
				Expect().Status(http.StatusBadRequest).JSON().Object().
				Value("data").Object().Value(tc.field).Object().
				Value("code").String().IsEqual(tc.code)
		})
	}

	// The server's holder claim and the one reserved against attesters are
	// the same name, kept in two packages that cannot import each other.
	if util.ClaimHolder != server.ClaimHolder {
		t.Fatalf("holder claim names differ: %q and %q", util.ClaimHolder, server.ClaimHolder)
	}

	t.Run("what the server decides is not taken from the request", func(t *testing.T) {
		row := f.api.T(t).Create(util.Coll.Attestations, f.issuerToken, base(map[string]any{
			a.Status:        util.StatusActive,
			a.SubjectDomain: "forged.example",
			a.SubjectName:   "Forged",
			a.IssuedAt:      "2020-01-01 00:00:00.000Z",
		})).Expect().Status(http.StatusOK).JSON().Object()
		row.Value(a.Status).String().IsEqual(util.StatusOffered)
		row.Value(a.SubjectDomain).String().IsEmpty()
		row.Value(a.SubjectName).String().IsEmpty()
		row.Value(a.IssuedAt).String().IsEmpty()
	})
}

func TestOfferMadeForOneIdentity(t *testing.T) {
	f := newAttestationFixture(t)
	fingerprint := f.api.E.GET("/api/certificate/" + f.identityID).
		Expect().Status(http.StatusOK).JSON().Object().Value("fingerprint").String().Raw()
	_, token := f.offer(t, map[string]any{util.Fields.Attestation.SubjectFingerprint: fingerprint})

	otherID, otherToken, err := testutils.CreateRandomUser(f.baseURL)
	if err != nil {
		t.Fatal(err)
	}
	otherWs := activeWorkspaceOf(t, f.api, otherID, otherToken)
	otherIdentity, otherKp := newIdentity(t, f.baseURL, otherToken, "Mallory", otherID, otherWs)
	nonce := f.challenge(t, token, otherIdentity)
	resp := postJSON(t, f.baseURL+"/api/credentials/claim", otherToken, map[string]any{
		"token": token, "identityId": otherIdentity,
		"challengeNonce": nonce, "challengeSignature": otherKp.SignChallenge(t, nonce),
	})
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("status = %d", resp.StatusCode)
	}
	if code := decode(t, resp)["code"]; code != util.Errors.AttestationIdentityMismatch.ErrorCode {
		t.Fatalf("code = %v", code)
	}

	f.acceptLocal(t, token)
}

func TestIssuingNeedsThePermission(t *testing.T) {
	inv := newInviteFixture(t)
	t.Setenv(util.AllowAttestationsEnv, "true")
	a := util.Fields.Attestation
	body := func(user string) map[string]any {
		return map[string]any{a.User: user, a.Workspace: inv.workspaceID, a.Type: "membership"}
	}

	// The workspace's own administrator holds every permission.
	id := inv.api.Create(util.Coll.Attestations, inv.adminToken, body(inv.adminID)).
		Expect().Status(http.StatusOK).JSON().Object().Value("id").String().Raw()

	join := func(permissions []string) (string, string) {
		token, _ := inv.createInvite(t, map[string]any{util.Fields.Invite.Permissions: permissions})
		memberID, memberToken, err := testutils.CreateRandomUser(inv.baseURL)
		if err != nil {
			t.Fatal(err)
		}
		inv.api.E.POST("/api/public/invites/"+token).
			WithHeader("Authorization", memberToken).Expect().Status(http.StatusOK)
		inv.api.Update(util.Coll.Users, memberID, memberToken, map[string]any{
			"activeWorkspace": inv.workspaceID, "activeRole": util.RoleMember,
		}).Expect().Status(http.StatusOK)
		return memberID, memberToken
	}

	t.Run("a member without it neither issues nor reads", func(t *testing.T) {
		memberID, memberToken := join([]string{util.PermSharesRead})
		api := inv.api.T(t)
		api.Create(util.Coll.Attestations, memberToken, body(memberID)).
			Expect().Status(http.StatusForbidden).JSON().Object().
			Value("data").Object().Value(util.Fields.WorkspaceMember.Permissions).Object().
			Value("code").String().IsEqual(util.Errors.MissingPermission.ErrorCode)
		api.E.GET("/api/collections/"+util.Coll.Attestations+"/records").
			WithHeader("Authorization", memberToken).Expect().Status(http.StatusForbidden)
		api.Get(util.Coll.Attestations, id, memberToken).Expect().Status(http.StatusForbidden)
		api.Update(util.Coll.Attestations, id, memberToken, map[string]any{a.Status: util.StatusRevoked}).
			Expect().Status(http.StatusForbidden)
	})

	t.Run("a member who may read sees them and changes nothing", func(t *testing.T) {
		_, memberToken := join([]string{util.PermAttestationsRead})
		api := inv.api.T(t)
		api.E.GET("/api/collections/"+util.Coll.Attestations+"/records").
			WithHeader("Authorization", memberToken).
			Expect().Status(http.StatusOK).JSON().Object().Value("totalItems").Number().Ge(1)
		api.Update(util.Coll.Attestations, id, memberToken, map[string]any{a.Label: "x"}).
			Expect().Status(http.StatusForbidden)
	})

	t.Run("a member granted it issues, and revokes a colleague's", func(t *testing.T) {
		memberID, memberToken := join([]string{util.PermAttestationsIssue})
		api := inv.api.T(t)
		api.Create(util.Coll.Attestations, memberToken, body(memberID)).Expect().Status(http.StatusOK)
		api.Update(util.Coll.Attestations, id, memberToken, map[string]any{a.Status: util.StatusRevoked}).
			Expect().Status(http.StatusOK).JSON().Object().Value(a.Status).String().IsEqual(util.StatusRevoked)
	})

	t.Run("an API key issues with the permission and not without", func(t *testing.T) {
		api := inv.api.T(t)
		key := func(scopes []string) string {
			return api.Create(util.Coll.ApiKeys, inv.adminToken, map[string]any{
				"label": "k-" + uuid.New().String()[:8], "workspace": inv.workspaceID,
				"user": inv.adminID, "scopes": scopes,
			}).Expect().Status(http.StatusOK).Header("X-Plain-Token").Raw()
		}
		issuing := key([]string{util.PermAttestationsIssue})
		api.Create(util.Coll.Attestations, issuing, body(inv.adminID)).
			Expect().Status(http.StatusOK).Header("X-Attestation-Token").NotEmpty()
		api.E.GET("/api/collections/"+util.Coll.Attestations+"/records").
			WithHeader("X-API-Key", issuing).Expect().Status(http.StatusOK)

		other := key([]string{util.PermSharesRead})
		api.Create(util.Coll.Attestations, other, body(inv.adminID)).Expect().StatusRange(400)
		api.E.GET("/api/collections/"+util.Coll.Attestations+"/records").
			WithHeader("X-API-Key", other).Expect().Status(http.StatusForbidden)
		// A key holds no credentials: they are a person's.
		api.E.GET("/api/collections/"+util.Coll.Credentials+"/records").
			WithHeader("X-API-Key", issuing).
			Expect().Status(http.StatusOK).JSON().Object().Value("totalItems").Number().IsEqual(0)
	})
}

// What is stated about a person is that person's data. The audit trail
// records that an attestation was issued, not what it says.
func TestAuditTrailDoesNotKeepWhatAnAttestationStates(t *testing.T) {
	f := newAttestationFixture(t)
	_, app := testutils.SetupTestApp(t)
	id, token := f.offer(t, nil)
	f.acceptLocal(t, token)

	rows, err := app.FindRecordsByFilter(util.Coll.AuditLogs,
		util.Fields.AuditLog.RecordId+" = {:id}", "", 0, 0, map[string]any{"id": id})
	if err != nil || len(rows) == 0 {
		t.Fatalf("no audit row for the attestation: %v", err)
	}
	for _, row := range rows {
		snapshot := row.GetString(util.Fields.AuditLog.NewData) + row.GetString(util.Fields.AuditLog.OldData)
		if strings.Contains(snapshot, "Ada Lovelace") || strings.Contains(snapshot, "member_no") {
			t.Fatalf("an audit row keeps what the attestation states: %s", snapshot)
		}
		if !strings.Contains(snapshot, util.AuditRedacted) {
			t.Fatalf("the claims are not marked as redacted: %s", snapshot)
		}
	}

	// The same holds for the holder's side: a credential is not logged.
	credentialRows, _ := app.FindAllRecords(util.Coll.AuditLogs)
	for _, row := range credentialRows {
		if row.GetString(util.Fields.AuditLog.Collection) != util.Coll.Credentials {
			continue
		}
		if strings.Contains(row.GetString(util.Fields.AuditLog.OldData), "Ada Lovelace") {
			t.Fatal("an audit row keeps a credential's claims")
		}
	}
}

// What this server publishes for other servers to verify its credentials
// with: a key the root key certifies, and a status list that key signs.
func TestCredentialKeyAndStatusListArePublished(t *testing.T) {
	f := newAttestationFixture(t)

	var info struct {
		PublicKey string `json:"publicKey"`
	}
	getJSON(t, f.baseURL+"/api/server", &info)
	var metadata struct {
		Issuer string `json:"issuer"`
		JWKS   struct {
			Keys []server.PublicJWK `json:"keys"`
		} `json:"jwks"`
	}
	getJSON(t, f.baseURL+util.CredentialIssuerMetadataPath, &metadata)
	if metadata.Issuer != "https://"+testDomain || len(metadata.JWKS.Keys) != 1 {
		t.Fatalf("metadata = %+v", metadata)
	}
	key, err := server.VerifyCredentialKey(metadata.JWKS.Keys[0], info.PublicKey, testDomain)
	if err != nil {
		t.Fatalf("the published key is not certified by the root key: %v", err)
	}

	resp, err := http.Get(f.baseURL + util.CredentialStatusListPath)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if ct := resp.Header.Get("Content-Type"); ct != "application/statuslist+jwt" {
		t.Fatalf("content type = %q", ct)
	}
	token, _ := io.ReadAll(resp.Body)
	list, _, err := server.VerifyStatusList(string(token), key, "https://"+testDomain+util.CredentialStatusListPath, time.Now())
	if err != nil {
		t.Fatalf("the status list does not verify: %v", err)
	}
	if list.Len() < 1024 {
		t.Fatalf("a status list of %d positions gives its credentials away", list.Len())
	}
}

// fakePeer is another Revoked server, as far as attestations are concerned:
// a root key of its own, a certified credential key, a status list, signed
// answers about identities, and an endpoint that hands out credentials.
type fakePeer struct {
	domain string
	root   *server.RootKey
	keys   *server.CredentialKeys
	srv    *httptest.Server

	mu         sync.Mutex
	revoked    map[int]bool
	identities map[string]string
	published  []server.PublicJWK
	// issue decides what the claim endpoint hands out.
	issue func(holderKey server.PublicJWK, holder server.HolderRef) string
}

func (p *fakePeer) issuer() string    { return "https://" + p.domain }
func (p *fakePeer) statusURI() string { return p.issuer() + util.CredentialStatusListPath }

func newFakePeer(t *testing.T) *fakePeer {
	t.Helper()
	domain := "peer-" + uuid.New().String()[:8] + ".invalid"
	root, err := server.Load(domain, filepath.Join(t.TempDir(), "server_root.pem"))
	if err != nil {
		t.Fatal(err)
	}
	keys, err := root.Credentials()
	if err != nil {
		t.Fatal(err)
	}
	p := &fakePeer{
		domain: domain, root: root, keys: keys,
		revoked: map[int]bool{}, identities: map[string]string{},
		published: []server.PublicJWK{keys.JWK()},
	}
	p.issue = func(holderKey server.PublicJWK, holder server.HolderRef) string {
		return p.credential(t, p.keys, holderKey, holder, 3)
	}

	mux := http.NewServeMux()
	writeJSON := func(w http.ResponseWriter, v any) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(v)
	}
	mux.HandleFunc("GET /api/server", func(w http.ResponseWriter, _ *http.Request) {
		assertion, _ := root.IssueAssertion(time.Now())
		writeJSON(w, map[string]any{"assertion": assertion})
	})
	mux.HandleFunc("GET "+util.CredentialIssuerMetadataPath, func(w http.ResponseWriter, _ *http.Request) {
		p.mu.Lock()
		defer p.mu.Unlock()
		writeJSON(w, map[string]any{"issuer": p.issuer(), "jwks": map[string]any{"keys": p.published}})
	})
	mux.HandleFunc("GET "+util.CredentialStatusListPath, func(w http.ResponseWriter, _ *http.Request) {
		p.mu.Lock()
		defer p.mu.Unlock()
		list := server.NewStatusList(1024)
		for idx := range p.revoked {
			list.Revoke(idx)
		}
		token, _ := keys.SignStatusList(p.statusURI(), list, time.Now())
		_, _ = w.Write([]byte(token))
	})
	mux.HandleFunc("GET /api/identities/{fingerprint}/status", func(w http.ResponseWriter, r *http.Request) {
		p.mu.Lock()
		word, known := p.identities[r.PathValue("fingerprint")]
		p.mu.Unlock()
		if !known {
			word = server.IdentityStatusUnknown
		}
		assertion, _ := root.IssueIdentityStatus(r.PathValue("fingerprint"), word, "", time.Time{}, time.Now())
		writeJSON(w, assertion)
	})
	mux.HandleFunc("POST /api/attestations/offers/{token}/claim", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Identity struct {
				Fingerprint   string `json:"fingerprint"`
				Certificate   string `json:"certificate"`
				DomainAtIssue string `json:"domainAtIssue"`
			} `json:"identity"`
		}
		_ = json.NewDecoder(r.Body).Decode(&body)
		pub, err := util.PublicKeyFromPEM(body.Identity.Certificate)
		if err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		holderKey, _ := server.JWKFromPublicKey(pub)
		writeJSON(w, map[string]any{"credential": p.issue(holderKey, server.HolderRef{
			Fingerprint: body.Identity.Fingerprint, Domain: body.Identity.DomainAtIssue,
		})})
	})
	p.srv = httptest.NewServer(mux)
	t.Cleanup(p.srv.Close)
	return p
}

func (p *fakePeer) credential(t *testing.T, keys *server.CredentialKeys, holderKey server.PublicJWK, holder server.HolderRef, idx int) string {
	t.Helper()
	credential, err := keys.IssueCredential(server.CredentialSpec{
		Issuer:    p.issuer(),
		Type:      "verified_adult",
		Holder:    holder,
		HolderKey: holderKey,
		Claims:    map[string]any{"age_over_18": true},
		IssuedAt:  time.Now(),
		Status:    &server.StatusRef{Idx: idx, URI: p.statusURI()},
	})
	if err != nil {
		t.Fatal(err)
	}
	return credential
}

// trust makes the test server reach the peer at its address, as two
// development instances reach each other.
func (p *fakePeer) trust(t *testing.T, baseURL string) {
	t.Helper()
	t.Setenv(util.PeerOverridesEnv, testDomain+"="+baseURL+","+p.domain+"="+p.srv.URL)
}

func TestCredentialIssuedByAnotherServer(t *testing.T) {
	f := newAttestationFixture(t)
	peer := newFakePeer(t)
	peer.trust(t, f.baseURL)
	const audience, nonce = "https://shop.example", "n"

	resp := f.accept(t, peer.srv.URL, f.baseURL, "offer-token")
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("relay refused: %d %v", resp.StatusCode, decode(t, resp))
	}
	rec := decode(t, resp)
	if rec[util.Fields.Credential.Issuer] != peer.domain {
		t.Fatalf("issuer = %v", rec[util.Fields.Credential.Issuer])
	}
	credential := rec[util.Fields.Credential.Credential].(string)

	t.Run("it verifies through the issuer's DNS-anchored key", func(t *testing.T) {
		verdict := f.verify(t, f.present(t, credential, []string{"age_over_18"}, audience, nonce), audience, nonce)
		if verdict["state"] != services.AttestationVerified || verdict["issuer"] != peer.domain {
			t.Fatalf("verdict = %v", verdict)
		}
		if verdict["issuerState"] != services.AttestationVerified || verdict["status"] != services.CredentialStatusValid {
			t.Fatalf("verdict = %v", verdict)
		}
	})

	t.Run("the issuer's revocation is read from its status list", func(t *testing.T) {
		peer.mu.Lock()
		peer.revoked[3] = true
		peer.mu.Unlock()
		services.ForgetPeerStatusList(peer.statusURI())
		verdict := f.verify(t, f.present(t, credential, nil, audience, nonce), audience, nonce)
		if verdict["state"] != services.AttestationRevoked {
			t.Fatalf("verdict = %v", verdict)
		}
		status := f.api.T(t).E.GET("/api/credentials/"+rec["id"].(string)+"/status").
			WithHeader("Authorization", f.holderToken).Expect().Status(http.StatusOK).JSON().Object()
		status.Value("state").String().IsEqual(services.AttestationRevoked)
	})

	t.Run("a status list that does not reach the credential says nothing", func(t *testing.T) {
		holderKey, holder := f.holderKeyAndRef(t)
		far := peer.credential(t, peer.keys, holderKey, holder, 5000)
		verdict := f.verify(t, f.present(t, far, nil, audience, nonce), audience, nonce)
		if verdict["state"] != services.AttestationUnverified || verdict["status"] != services.CredentialStatusUnknown {
			t.Fatalf("verdict = %v", verdict)
		}
	})
}

// holderKeyAndRef reads the holder's identity as the issuer would see it.
func (f attestationFixture) holderKeyAndRef(t *testing.T) (server.PublicJWK, server.HolderRef) {
	t.Helper()
	var cert struct {
		Certificate   string `json:"certificate"`
		Fingerprint   string `json:"fingerprint"`
		DomainAtIssue string `json:"domainAtIssue"`
	}
	getJSON(t, f.baseURL+"/api/certificate/"+f.identityID, &cert)
	pub, err := util.PublicKeyFromPEM(cert.Certificate)
	if err != nil {
		t.Fatal(err)
	}
	jwk, err := server.JWKFromPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	return jwk, server.HolderRef{Fingerprint: cert.Fingerprint, Domain: cert.DomainAtIssue}
}

// The holder's server looks at what an issuer hands back before keeping it.
func TestRelayRefusesACredentialItCannotStandBehind(t *testing.T) {
	f := newAttestationFixture(t)
	peer := newFakePeer(t)
	peer.trust(t, f.baseURL)

	stranger, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	strangerKey, _ := server.JWKFromPublicKey(&stranger.PublicKey)
	rogueRoot, err := server.Load("rogue.invalid", filepath.Join(t.TempDir(), "server_root.pem"))
	if err != nil {
		t.Fatal(err)
	}
	rogueKeys, _ := rogueRoot.Credentials()

	for name, issue := range map[string]func(server.PublicJWK, server.HolderRef) string{
		"bound to another key": func(_ server.PublicJWK, holder server.HolderRef) string {
			return peer.credential(t, peer.keys, strangerKey, holder, 1)
		},
		"about another identity": func(key server.PublicJWK, holder server.HolderRef) string {
			holder.Fingerprint = strings.Repeat("0", 64)
			return peer.credential(t, peer.keys, key, holder, 1)
		},
		"signed by a key the issuer does not publish": func(key server.PublicJWK, holder server.HolderRef) string {
			return peer.credential(t, rogueKeys, key, holder, 1)
		},
		"not a credential": func(server.PublicJWK, server.HolderRef) string { return "nonsense" },
	} {
		t.Run(name, func(t *testing.T) {
			peer.issue = issue
			resp := f.accept(t, peer.srv.URL, f.baseURL, "offer-token")
			if resp.StatusCode != http.StatusBadGateway {
				t.Fatalf("status = %d %v", resp.StatusCode, decode(t, resp))
			}
			if code := decode(t, resp)["code"]; code != util.Errors.CredentialInvalid.ErrorCode {
				t.Fatalf("code = %v", code)
			}
			if n := len(f.credentials(t, f.holderToken)); n != 0 {
				t.Fatalf("%d credentials were kept", n)
			}
		})
	}

	t.Run("a server that is not a known peer is not asked", func(t *testing.T) {
		resp := f.accept(t, "http://203.0.113.9:1", f.baseURL, "offer-token")
		if resp.StatusCode != http.StatusBadRequest {
			t.Fatalf("status = %d", resp.StatusCode)
		}
		if code := decode(t, resp)["code"]; code != util.Errors.RemoteOriginInvalid.ErrorCode {
			t.Fatalf("code = %v", code)
		}
	})
}

// A key served by a domain proves nothing unless that domain's root key —
// the one DNS pins — certified it.
func TestForgedCredentialKeyIsSpoofed(t *testing.T) {
	f := newAttestationFixture(t)
	peer := newFakePeer(t)
	peer.trust(t, f.baseURL)
	const audience, nonce = "https://shop.example", "n"
	holderKey, holder := f.holderKeyAndRef(t)

	rogueRoot, err := server.Load("rogue.invalid", filepath.Join(t.TempDir(), "server_root.pem"))
	if err != nil {
		t.Fatal(err)
	}
	rogueKeys, _ := rogueRoot.Credentials()
	forged := peer.credential(t, rogueKeys, holderKey, holder, 1)

	t.Run("a key the domain does not publish", func(t *testing.T) {
		verdict := f.verify(t, f.present(t, forged, nil, audience, nonce), audience, nonce)
		if verdict["state"] != services.AttestationUnverified {
			t.Fatalf("verdict = %v", verdict)
		}
		if _, stated := verdict["claims"]; stated {
			t.Fatal("claims of an unverified credential were reported")
		}
	})

	t.Run("a key the domain serves without its root key's certification", func(t *testing.T) {
		peer.mu.Lock()
		peer.published = append(peer.published, rogueKeys.JWK())
		peer.mu.Unlock()
		verdict := f.verify(t, f.present(t, forged, nil, audience, nonce), audience, nonce)
		if verdict["state"] != services.AttestationSpoofed {
			t.Fatalf("verdict = %v", verdict)
		}
		if _, stated := verdict["claims"]; stated {
			t.Fatal("claims of a spoofed credential were reported")
		}
	})

	t.Run("a credential altered after it was signed", func(t *testing.T) {
		genuine := peer.credential(t, peer.keys, holderKey, holder, 2)
		parts := strings.SplitN(genuine, ".", 3)
		payload, _ := base64.RawURLEncoding.DecodeString(parts[1])
		altered := strings.Replace(string(payload), `"verified_adult"`, `"verified_admin"`, 1)
		tampered := parts[0] + "." + base64.RawURLEncoding.EncodeToString([]byte(altered)) + "." + parts[2]
		verdict := f.verify(t, f.present(t, tampered, nil, audience, nonce), audience, nonce)
		if verdict["state"] != services.AttestationSpoofed {
			t.Fatalf("verdict = %v", verdict)
		}
	})
}

// remoteHolder is an identity issued by another server, with a P-256 key on
// the "device", as the app makes them.
type remoteHolder struct {
	key         *ecdsa.PrivateKey
	certificate string
	fingerprint string
	parentSig   string
}

func newRemoteHolder(t *testing.T, peer *fakePeer) remoteHolder {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{
		SerialNumber: big.NewInt(time.Now().UnixNano()),
		Subject:      pkix.Name{CommonName: "Grace"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	certificate := string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}))
	sum := sha256.Sum256([]byte(certificate))
	fingerprint := hex.EncodeToString(sum[:])
	sig, err := peer.root.Sign([]byte(fingerprint))
	if err != nil {
		t.Fatal(err)
	}
	return remoteHolder{key: key, certificate: certificate, fingerprint: fingerprint, parentSig: hex.EncodeToString(sig)}
}

// signChallenge signs the way the app does: ECDSA over SHA-256, ASN.1, base64.
func (h remoteHolder) signChallenge(t *testing.T, nonce string) string {
	t.Helper()
	digest := sha256.Sum256([]byte(nonce))
	sig, err := ecdsa.SignASN1(rand.Reader, h.key, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	return base64.StdEncoding.EncodeToString(sig)
}

// claim accepts an offer the way the holder's own server would relay it.
func (h remoteHolder) claim(t *testing.T, f attestationFixture, peer *fakePeer, token, parentSig string) *http.Response {
	t.Helper()
	const id = "remote-identity-1"
	nonce := f.challenge(t, token, id)
	return postJSON(t, f.baseURL+"/api/attestations/offers/"+token+"/claim", "", map[string]any{
		"identity": map[string]any{
			"id": id, "name": "Grace", "fingerprint": h.fingerprint, "certificate": h.certificate,
			"parentSignature": parentSig, "domainAtIssue": peer.domain,
		},
		"challengeNonce":     nonce,
		"challengeSignature": h.signChallenge(t, nonce),
	})
}

// The identity an attestation is about usually lives on another server. The
// attester checks it there before signing, and a verifier asks there again.
func TestAttestationAboutAnIdentityFromAnotherServer(t *testing.T) {
	f := newAttestationFixture(t)
	peer := newFakePeer(t)
	peer.trust(t, f.baseURL)
	holder := newRemoteHolder(t, peer)
	const audience, nonce = "https://shop.example", "n"

	t.Run("an identity its server does not know is refused", func(t *testing.T) {
		_, token := f.offer(t, nil)
		resp := holder.claim(t, f, peer, token, holder.parentSig)
		if resp.StatusCode != http.StatusForbidden {
			t.Fatalf("status = %d %v", resp.StatusCode, decode(t, resp))
		}
	})

	peer.mu.Lock()
	peer.identities[holder.fingerprint] = server.IdentityStatusActive
	peer.mu.Unlock()

	t.Run("an identity its server's root key did not sign is refused", func(t *testing.T) {
		_, token := f.offer(t, nil)
		other := newFakePeer(t)
		forged, _ := other.root.Sign([]byte(holder.fingerprint))
		resp := holder.claim(t, f, peer, token, hex.EncodeToString(forged))
		if resp.StatusCode != http.StatusForbidden {
			t.Fatalf("status = %d", resp.StatusCode)
		}
		if code := decode(t, resp)["code"]; code != util.Errors.RemoteIdentityInvalid.ErrorCode {
			t.Fatalf("code = %v", code)
		}
	})

	id, token := f.offer(t, nil)
	resp := holder.claim(t, f, peer, token, holder.parentSig)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("claim refused: %d %v", resp.StatusCode, decode(t, resp))
	}
	credential := decode(t, resp)["credential"].(string)

	row := f.api.Get(util.Coll.Attestations, id, f.issuerToken).Expect().Status(http.StatusOK).JSON().Object()
	row.Value(util.Fields.Attestation.SubjectDomain).String().IsEqual(peer.domain)
	row.Value(util.Fields.Attestation.SubjectFingerprint).String().IsEqual(holder.fingerprint)

	present := func() string {
		presentation, err := server.PresentCredential(credential, []string{"name"}, audience, nonce, "ES256", time.Now(),
			func(input string) ([]byte, error) { return server.SignES256(holder.key, input) })
		if err != nil {
			t.Fatal(err)
		}
		return presentation
	}

	t.Run("both chains hold", func(t *testing.T) {
		verdict := f.verify(t, present(), audience, nonce)
		if verdict["state"] != services.AttestationVerified || verdict["keyBound"] != true {
			t.Fatalf("verdict = %v", verdict)
		}
		holderVerdict := verdict["holder"].(map[string]any)
		if holderVerdict["domain"] != peer.domain || holderVerdict["state"] != services.AttestationVerified {
			t.Fatalf("holder = %v", holderVerdict)
		}
	})

	t.Run("the identity's server withdraws it", func(t *testing.T) {
		peer.mu.Lock()
		peer.identities[holder.fingerprint] = server.IdentityStatusRevoked
		peer.mu.Unlock()
		verdict := f.verify(t, present(), audience, nonce)
		if verdict["state"] != services.AttestationRevoked {
			t.Fatalf("verdict = %v", verdict)
		}
	})

	t.Run("the identity's server disclaims it", func(t *testing.T) {
		peer.mu.Lock()
		delete(peer.identities, holder.fingerprint)
		peer.mu.Unlock()
		verdict := f.verify(t, present(), audience, nonce)
		if verdict["state"] != services.AttestationUnverified {
			t.Fatalf("verdict = %v", verdict)
		}
	})
}

// An account that goes takes its credentials with it; the attestations it
// issued in a workspace of its own are revoked with that workspace.
func TestAccountDeletionAndAttestations(t *testing.T) {
	f := newAttestationFixture(t)
	_, token := f.offer(t, nil)
	credential := f.acceptLocal(t, token)[util.Fields.Credential.Credential].(string)
	const audience, nonce = "https://shop.example", "n"
	presentation := f.present(t, credential, nil, audience, nonce)

	req, _ := http.NewRequest(http.MethodDelete, f.baseURL+"/api/account", nil)
	req.Header.Set("Authorization", f.issuerToken)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("deleting the issuer's account: %d", resp.StatusCode)
	}
	if verdict := f.verify(t, presentation, audience, nonce); verdict["state"] != services.AttestationRevoked {
		t.Fatalf("verdict = %v", verdict)
	}

	req, _ = http.NewRequest(http.MethodDelete, f.baseURL+"/api/account", nil)
	req.Header.Set("Authorization", f.holderToken)
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("deleting the holder's account: %d", resp.StatusCode)
	}
}
