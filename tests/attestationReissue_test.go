package tests

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"fmt"
	"net/http"
	"net/url"
	"testing"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/tests/testutils"
	"revoked/util"
)

// Replacing an identity moves every credential bound to it: the key the
// credential names vouches for the new identity, the new identity proves its
// own key, and the issuer revokes the old credential as it issues the new one.

// identityCard is an identity's public half, as /api/certificate serves it.
type identityCard struct {
	Name            string `json:"name"`
	Certificate     string `json:"certificate"`
	Fingerprint     string `json:"fingerprint"`
	ParentSignature string `json:"parentSignature"`
	DomainAtIssue   string `json:"domainAtIssue"`
}

func certificateOf(t *testing.T, baseURL, identityID string) identityCard {
	t.Helper()
	var card identityCard
	getJSON(t, baseURL+"/api/certificate/"+identityID, &card)
	return card
}

// rsaVoucher signs a voucher with a test identity's RSA key, the way the app
// signs one with its own key: over the payload bytes, base64.
func rsaVoucher(t *testing.T, kp *testutils.IdentityKeyPair, issuer, oldFingerprint, newFingerprint, nonce string) server.ReissueVoucher {
	t.Helper()
	v, err := server.SignReissueVoucher(server.ReissueVoucherBody{
		Issuer: issuer, OldFingerprint: oldFingerprint, NewFingerprint: newFingerprint, Nonce: nonce,
	}, func(payload []byte) ([]byte, error) {
		digest := sha256.Sum256(payload)
		return rsa.SignPKCS1v15(rand.Reader, kp.PrivateKey, crypto.SHA256, digest[:])
	})
	if err != nil {
		t.Fatal(err)
	}
	return v
}

// ecVoucher is the same with a P-256 key, as the app's identities have.
func ecVoucher(t *testing.T, key *ecdsa.PrivateKey, issuer, oldFingerprint, newFingerprint, nonce string) server.ReissueVoucher {
	t.Helper()
	v, err := server.SignReissueVoucher(server.ReissueVoucherBody{
		Issuer: issuer, OldFingerprint: oldFingerprint, NewFingerprint: newFingerprint, Nonce: nonce,
	}, func(payload []byte) ([]byte, error) {
		digest := sha256.Sum256(payload)
		return ecdsa.SignASN1(rand.Reader, key, digest[:])
	})
	if err != nil {
		t.Fatal(err)
	}
	return v
}

func expectRefusal(t *testing.T, resp *http.Response, status int, code string) {
	t.Helper()
	body := decode(t, resp)
	if resp.StatusCode != status || body["code"] != code {
		t.Fatalf("got %d %v, want %d %s", resp.StatusCode, body, status, code)
	}
}

// successor is the identity another one is replaced with, in the holder's
// own account.
type successor struct {
	id   string
	kp   *testutils.IdentityKeyPair
	card identityCard
}

func (f attestationFixture) successor(t *testing.T, name string) successor {
	t.Helper()
	id, kp := newIdentity(t, f.baseURL, f.holderToken, name, f.holderID, f.holderWs)
	return successor{id: id, kp: kp, card: certificateOf(t, f.baseURL, id)}
}

// reissueChallenge asks the holder's server for the issuer's challenge.
func (f attestationFixture) reissueChallenge(t *testing.T, credentialID, identityID string) string {
	t.Helper()
	req, _ := http.NewRequest(http.MethodGet,
		f.baseURL+"/api/credentials/"+credentialID+"/reissue?identityId="+url.QueryEscape(identityID), nil)
	req.Header.Set("Authorization", f.holderToken)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body := decode(t, resp)
	nonce, _ := body["nonce"].(string)
	if resp.StatusCode != http.StatusOK || nonce == "" {
		t.Fatalf("challenge refused: %d %v", resp.StatusCode, body)
	}
	return nonce
}

// reissue moves a credential through the holder's server, as the app does:
// the old key signs the voucher, the new key the issuer's challenge.
func (f attestationFixture) reissue(t *testing.T, credentialID, issuer string, from *testutils.IdentityKeyPair, fromFingerprint string, to successor) *http.Response {
	t.Helper()
	nonce := f.reissueChallenge(t, credentialID, to.id)
	return postJSON(t, f.baseURL+"/api/credentials/"+credentialID+"/reissue", f.holderToken, map[string]any{
		"identityId":         to.id,
		"challengeNonce":     nonce,
		"challengeSignature": to.kp.SignChallenge(t, nonce),
		"voucher":            rsaVoucher(t, from, issuer, fromFingerprint, to.card.Fingerprint, nonce),
	})
}

func presentWith(t *testing.T, kp *testutils.IdentityKeyPair, credential, audience, nonce string) string {
	t.Helper()
	presentation, err := server.PresentCredential(credential, nil, audience, nonce, "RS256", time.Now(),
		func(input string) ([]byte, error) { return server.SignRS256(kp.PrivateKey, input) })
	if err != nil {
		t.Fatal(err)
	}
	return presentation
}

func TestReissueMovesACredentialToAnotherIdentity(t *testing.T) {
	f := newAttestationFixture(t)
	a, c := util.Fields.Attestation, util.Fields.Credential
	const audience, nonce = "https://shop.example", "n"

	attestationID, token := f.offer(t, nil)
	before := f.acceptLocal(t, token)
	credentialID := before["id"].(string)
	oldCredential := before[c.Credential].(string)
	oldPresentation := f.present(t, oldCredential, nil, audience, nonce)
	issuedAt := f.api.Get(util.Coll.Attestations, attestationID, f.issuerToken).
		Expect().Status(http.StatusOK).JSON().Object().Value(a.IssuedAt).String().Raw()
	old := certificateOf(t, f.baseURL, f.identityID)
	next := f.successor(t, "Ada, new laptop")

	resp := f.reissue(t, credentialID, testDomain, f.kp, old.Fingerprint, next)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("reissue refused: %d %v", resp.StatusCode, decode(t, resp))
	}
	after := decode(t, resp)
	newCredential := after[c.Credential].(string)

	t.Run("the holder keeps one copy, bound to the new identity", func(t *testing.T) {
		if after["id"] != credentialID || after[c.Identity] != next.id || after[c.Issuer] != testDomain {
			t.Fatalf("credential record: %v", after)
		}
		if newCredential == oldCredential {
			t.Fatal("the credential was not replaced")
		}
		claims, _ := after[c.Claims].(map[string]any)
		if after[c.Type] != "membership" || claims["name"] != "Ada Lovelace" || claims["member_no"] != float64(42) {
			t.Fatalf("what it states changed: %v", after)
		}
		if after[c.IssuedAt] != before[c.IssuedAt] || after[c.IssuedAt] == "" {
			t.Fatalf("issue date %v, was %v", after[c.IssuedAt], before[c.IssuedAt])
		}
		if n := len(f.credentials(t, f.holderToken)); n != 1 {
			t.Fatalf("the holder keeps %d copies", n)
		}
	})

	t.Run("the new key presents it, and the old one no longer can", func(t *testing.T) {
		verdict := f.verify(t, presentWith(t, next.kp, newCredential, audience, nonce), audience, nonce)
		if verdict["state"] != services.AttestationVerified || verdict["status"] != services.CredentialStatusValid {
			t.Fatalf("verdict = %v", verdict)
		}
		if holder := verdict["holder"].(map[string]any); holder["fingerprint"] != next.card.Fingerprint {
			t.Fatalf("holder = %v", holder)
		}
		if v := f.verify(t, presentWith(t, f.kp, newCredential, audience, nonce), audience, nonce); v["state"] != services.AttestationInvalid {
			t.Fatalf("presented with the old key: %v", v)
		}
	})

	t.Run("the credential it replaces is revoked", func(t *testing.T) {
		verdict := f.verify(t, oldPresentation, audience, nonce)
		if verdict["state"] != services.AttestationRevoked || verdict["status"] != services.CredentialStatusRevoked {
			t.Fatalf("verdict = %v", verdict)
		}
	})

	t.Run("the attestation names the new identity, from the same day", func(t *testing.T) {
		row := f.api.T(t).Get(util.Coll.Attestations, attestationID, f.issuerToken).
			Expect().Status(http.StatusOK).JSON().Object()
		row.Value(a.Status).String().IsEqual(util.StatusActive)
		row.Value(a.SubjectFingerprint).String().IsEqual(next.card.Fingerprint)
		row.Value(a.SubjectName).String().IsEqual("Ada, new laptop")
		row.Value(a.IssuedAt).String().IsEqual(issuedAt)
	})

	t.Run("the holder's server reads it as standing", func(t *testing.T) {
		f.api.T(t).E.GET("/api/credentials/"+credentialID+"/status").
			WithHeader("Authorization", f.holderToken).
			Expect().Status(http.StatusOK).JSON().Object().
			Value("state").String().IsEqual(services.AttestationVerified)
	})

	// Straight to the issuer, as the holder's server relays it.
	atIssuer := func(t *testing.T, to successor) *http.Response {
		t.Helper()
		challenge := f.api.T(t).E.GET("/api/challenges/reissue/"+old.Fingerprint).
			WithQuery("identityId", to.id).
			Expect().Status(http.StatusOK).JSON().Object().Value("nonce").String().Raw()
		return postJSON(t, f.baseURL+"/api/attestations/reissue", "", map[string]any{
			"credential": oldCredential,
			"identity": map[string]any{
				"id": to.id, "name": to.card.Name, "fingerprint": to.card.Fingerprint,
				"certificate": to.card.Certificate, "parentSignature": to.card.ParentSignature,
				"domainAtIssue": to.card.DomainAtIssue,
			},
			"challengeNonce":     challenge,
			"challengeSignature": to.kp.SignChallenge(t, challenge),
			"voucher":            rsaVoucher(t, f.kp, testDomain, old.Fingerprint, to.card.Fingerprint, challenge),
		})
	}

	t.Run("the credential it replaces cannot be moved to yet another identity", func(t *testing.T) {
		third := f.successor(t, "Ada, third")
		expectRefusal(t, atIssuer(t, third), http.StatusGone, util.Errors.ReissueCredentialRevoked.ErrorCode)
	})

	t.Run("asked for again, the move hands out the moved credential once more", func(t *testing.T) {
		resp := atIssuer(t, next)
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("asking again refused: %d %v", resp.StatusCode, decode(t, resp))
		}
		again := decode(t, resp)["credential"].(string)
		verdict := f.verify(t, presentWith(t, next.kp, again, audience, nonce), audience, nonce)
		if verdict["state"] != services.AttestationVerified || verdict["status"] != services.CredentialStatusValid {
			t.Fatalf("verdict = %v", verdict)
		}
		position := func(credential string) any {
			p, err := server.ParseCredential(credential)
			if err != nil {
				t.Fatal(err)
			}
			return p.Payload["status"]
		}
		if a, b := position(again), position(newCredential); a == nil || fmt.Sprint(a) != fmt.Sprint(b) {
			t.Fatalf("asked again at position %v, moved to %v", a, b)
		}
		f.api.T(t).Get(util.Coll.Attestations, attestationID, f.issuerToken).
			Expect().Status(http.StatusOK).JSON().Object().
			Value(a.SubjectFingerprint).String().IsEqual(next.card.Fingerprint)
	})

	t.Run("an offer accepted again is issued to the new identity, at its new position", func(t *testing.T) {
		var challenge string
		getJSON(t, f.baseURL+"/api/challenges/attestation/"+token+"?identityId="+next.id, &struct {
			Nonce *string `json:"nonce"`
		}{&challenge})
		resp := postJSON(t, f.baseURL+"/api/credentials/claim", f.holderToken, map[string]any{
			"token": token, "identityId": next.id,
			"challengeNonce": challenge, "challengeSignature": next.kp.SignChallenge(t, challenge),
		})
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("claim refused: %d %v", resp.StatusCode, decode(t, resp))
		}
		again := decode(t, resp)[c.Credential].(string)
		verdict := f.verify(t, presentWith(t, next.kp, again, audience, nonce), audience, nonce)
		if verdict["state"] != services.AttestationVerified {
			t.Fatalf("verdict = %v", verdict)
		}
		if n := len(f.credentials(t, f.holderToken)); n != 1 {
			t.Fatalf("the holder keeps %d copies", n)
		}
	})
}

func TestReissueRefusals(t *testing.T) {
	f := newAttestationFixture(t)
	old := certificateOf(t, f.baseURL, f.identityID)
	next := f.successor(t, "Ada, new")
	accepted := func(t *testing.T) (string, string) {
		t.Helper()
		id, token := f.offer(t, nil)
		return id, f.acceptLocal(t, token)["id"].(string)
	}
	stillOnTheOldIdentity := func(t *testing.T, credentialID string) {
		t.Helper()
		row := f.api.Get(util.Coll.Credentials, credentialID, f.holderToken).
			Expect().Status(http.StatusOK).JSON().Object()
		row.Value(util.Fields.Credential.Identity).String().IsEqual(f.identityID)
		f.api.E.GET("/api/credentials/"+credentialID+"/status").
			WithHeader("Authorization", f.holderToken).
			Expect().Status(http.StatusOK).JSON().Object().
			Value("status").String().IsEqual(services.CredentialStatusValid)
	}
	send := func(t *testing.T, credentialID, nonce string, voucher server.ReissueVoucher) *http.Response {
		t.Helper()
		return postJSON(t, f.baseURL+"/api/credentials/"+credentialID+"/reissue", f.holderToken, map[string]any{
			"identityId": next.id, "challengeNonce": nonce,
			"challengeSignature": next.kp.SignChallenge(t, nonce), "voucher": voucher,
		})
	}

	t.Run("a voucher signed by another key", func(t *testing.T) {
		_, credentialID := accepted(t)
		nonce := f.reissueChallenge(t, credentialID, next.id)
		stranger := testutils.NewTestIdentity(t, "stranger")
		resp := send(t, credentialID, nonce, rsaVoucher(t, stranger, testDomain, old.Fingerprint, next.card.Fingerprint, nonce))
		expectRefusal(t, resp, http.StatusUnauthorized, util.Errors.ReissueVoucherInvalid.ErrorCode)
		stillOnTheOldIdentity(t, credentialID)
	})

	t.Run("a voucher for another identity, issuer or occasion", func(t *testing.T) {
		_, credentialID := accepted(t)
		third := f.successor(t, "Ada, third")
		for name, voucher := range map[string]func(nonce string) server.ReissueVoucher{
			"another identity": func(nonce string) server.ReissueVoucher {
				return rsaVoucher(t, f.kp, testDomain, old.Fingerprint, third.card.Fingerprint, nonce)
			},
			"another issuer": func(nonce string) server.ReissueVoucher {
				return rsaVoucher(t, f.kp, "other.example", old.Fingerprint, next.card.Fingerprint, nonce)
			},
			"another occasion": func(string) server.ReissueVoucher {
				return rsaVoucher(t, f.kp, testDomain, old.Fingerprint, next.card.Fingerprint, "an-earlier-nonce-0000")
			},
		} {
			t.Run(name, func(t *testing.T) {
				nonce := f.reissueChallenge(t, credentialID, next.id)
				expectRefusal(t, send(t, credentialID, nonce, voucher(nonce)),
					http.StatusUnauthorized, util.Errors.ReissueVoucherInvalid.ErrorCode)
			})
		}
		stillOnTheOldIdentity(t, credentialID)
	})

	t.Run("a challenge is spent once", func(t *testing.T) {
		_, first := accepted(t)
		_, second := accepted(t)
		nonce := f.reissueChallenge(t, first, next.id)
		voucher := rsaVoucher(t, f.kp, testDomain, old.Fingerprint, next.card.Fingerprint, nonce)
		if resp := send(t, first, nonce, voucher); resp.StatusCode != http.StatusOK {
			t.Fatalf("first use: %d %v", resp.StatusCode, decode(t, resp))
		}
		// The voucher names the two identities and the nonce, all of which a
		// second credential of the same identity shares: only the spent
		// challenge stops it from moving that one too.
		expectRefusal(t, send(t, second, nonce, voucher), http.StatusUnauthorized, util.Errors.ChallengeInvalid.ErrorCode)
		stillOnTheOldIdentity(t, second)
	})

	t.Run("a credential its issuer revoked", func(t *testing.T) {
		attestationID, credentialID := accepted(t)
		f.api.T(t).Update(util.Coll.Attestations, attestationID, f.issuerToken, map[string]any{
			util.Fields.Attestation.Status: util.StatusRevoked,
		}).Expect().Status(http.StatusOK)
		resp := f.reissue(t, credentialID, testDomain, f.kp, old.Fingerprint, next)
		expectRefusal(t, resp, http.StatusGone, util.Errors.ReissueCredentialRevoked.ErrorCode)
	})

	t.Run("an identity of someone else, or the same one", func(t *testing.T) {
		_, credentialID := accepted(t)
		otherID, otherToken, err := testutils.CreateRandomUser(f.baseURL)
		if err != nil {
			t.Fatal(err)
		}
		otherIdentity, _ := newIdentity(t, f.baseURL, otherToken, "Mallory", otherID, activeWorkspaceOf(t, f.api, otherID, otherToken))
		for identityID, code := range map[string]string{
			otherIdentity: util.Errors.IdentityNotOwned.ErrorCode,
			f.identityID:  util.Errors.ReissueIdentityMismatch.ErrorCode,
		} {
			f.api.T(t).E.GET("/api/credentials/"+credentialID+"/reissue").
				WithQuery("identityId", identityID).WithHeader("Authorization", f.holderToken).
				Expect().Status(http.StatusForbidden).JSON().Object().Value("code").String().IsEqual(code)
		}
		// Someone else's credential is not theirs to move.
		f.api.T(t).E.GET("/api/credentials/"+credentialID+"/reissue").
			WithQuery("identityId", otherIdentity).WithHeader("Authorization", otherToken).
			Expect().Status(http.StatusNotFound)
	})

	// Last: it revokes the fixture's identity.
	t.Run("revoking the old identity ends its say", func(t *testing.T) {
		_, credentialID := accepted(t)
		nonce := f.reissueChallenge(t, credentialID, next.id)
		f.api.T(t).Update(util.Coll.Identities, f.identityID, f.holderToken, map[string]any{
			util.Fields.Identity.Status: util.StatusRevoked,
		}).Expect().Status(http.StatusOK)
		resp := send(t, credentialID, nonce, rsaVoucher(t, f.kp, testDomain, old.Fingerprint, next.card.Fingerprint, nonce))
		expectRefusal(t, resp, http.StatusForbidden, util.Errors.ReissueHolderRevoked.ErrorCode)
	})
}

// The issuer is another server: the holder's server relays the challenge and
// the move, and checks what comes back.
func TestReissueThroughTheHolderServerToAnotherIssuer(t *testing.T) {
	f := newAttestationFixture(t)
	peer := newFakePeer(t)
	peer.trust(t, f.baseURL)
	c := util.Fields.Credential
	const audience, nonce = "https://shop.example", "n"

	resp := f.accept(t, peer.srv.URL, f.baseURL, "offer-token")
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("relay refused: %d %v", resp.StatusCode, decode(t, resp))
	}
	before := decode(t, resp)
	credentialID := before["id"].(string)
	oldPresentation := f.present(t, before[c.Credential].(string), nil, audience, nonce)
	old := certificateOf(t, f.baseURL, f.identityID)
	next := f.successor(t, "Ada, new")

	t.Run("the issuer's refusal is passed on with its code", func(t *testing.T) {
		challenge := f.reissueChallenge(t, credentialID, next.id)
		resp := postJSON(t, f.baseURL+"/api/credentials/"+credentialID+"/reissue", f.holderToken, map[string]any{
			"identityId": next.id, "challengeNonce": challenge,
			"challengeSignature": next.kp.SignChallenge(t, challenge),
			// Made for this server rather than the issuer.
			"voucher": rsaVoucher(t, f.kp, testDomain, old.Fingerprint, next.card.Fingerprint, challenge),
		})
		expectRefusal(t, resp, http.StatusUnauthorized, util.Errors.ReissueVoucherInvalid.ErrorCode)
	})

	resp = f.reissue(t, credentialID, peer.domain, f.kp, old.Fingerprint, next)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("reissue refused: %d %v", resp.StatusCode, decode(t, resp))
	}
	after := decode(t, resp)
	if after["id"] != credentialID || after[c.Identity] != next.id || after[c.Issuer] != peer.domain {
		t.Fatalf("credential record: %v", after)
	}

	verdict := f.verify(t, presentWith(t, next.kp, after[c.Credential].(string), audience, nonce), audience, nonce)
	if verdict["state"] != services.AttestationVerified || verdict["issuer"] != peer.domain {
		t.Fatalf("verdict = %v", verdict)
	}
	services.ForgetPeerStatusList(peer.statusURI())
	if v := f.verify(t, oldPresentation, audience, nonce); v["state"] != services.AttestationRevoked {
		t.Fatalf("the replaced credential: %v", v)
	}
}

// The identities live on another server: the issuer checks both there, and
// the move is refused once that server has withdrawn the old one.
func TestReissueOfAnIdentityFromAnotherServer(t *testing.T) {
	f := newAttestationFixture(t)
	peer := newFakePeer(t)
	peer.trust(t, f.baseURL)
	const audience, nonce = "https://shop.example", "n"
	from, to := newRemoteHolder(t, peer), newRemoteHolder(t, peer)
	peer.mu.Lock()
	peer.identities[from.fingerprint] = server.IdentityStatusActive
	peer.identities[to.fingerprint] = server.IdentityStatusActive
	peer.mu.Unlock()

	claim := func(t *testing.T) (string, string) {
		t.Helper()
		id, token := f.offer(t, nil)
		resp := from.claim(t, f, peer, token, from.parentSig)
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("claim refused: %d %v", resp.StatusCode, decode(t, resp))
		}
		return id, decode(t, resp)["credential"].(string)
	}
	move := func(t *testing.T, credential string, target remoteHolder, targetDomain, targetID string) *http.Response {
		t.Helper()
		challenge := f.api.T(t).E.GET("/api/challenges/reissue/"+from.fingerprint).
			WithQuery("identityId", targetID).
			Expect().Status(http.StatusOK).JSON().Object().Value("nonce").String().Raw()
		return postJSON(t, f.baseURL+"/api/attestations/reissue", "", map[string]any{
			"credential": credential,
			"identity": map[string]any{
				"id": targetID, "name": "Grace", "fingerprint": target.fingerprint,
				"certificate": target.certificate, "parentSignature": target.parentSig,
				"domainAtIssue": targetDomain,
			},
			"challengeNonce":     challenge,
			"challengeSignature": target.signChallenge(t, challenge),
			"voucher":            ecVoucher(t, from.key, testDomain, from.fingerprint, target.fingerprint, challenge),
		})
	}
	present := func(t *testing.T, holder remoteHolder, credential string) string {
		t.Helper()
		presentation, err := server.PresentCredential(credential, nil, audience, nonce, "ES256", time.Now(),
			func(input string) ([]byte, error) { return server.SignES256(holder.key, input) })
		if err != nil {
			t.Fatal(err)
		}
		return presentation
	}

	attestationID, credential := claim(t)

	t.Run("not to an identity from another server", func(t *testing.T) {
		elsewhere := newFakePeer(t)
		stranger := newRemoteHolder(t, elsewhere)
		expectRefusal(t, move(t, credential, stranger, elsewhere.domain, "remote-identity-3"),
			http.StatusForbidden, util.Errors.ReissueIdentityMismatch.ErrorCode)
	})

	resp := move(t, credential, to, peer.domain, "remote-identity-2")
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("reissue refused: %d %v", resp.StatusCode, decode(t, resp))
	}
	moved := decode(t, resp)["credential"].(string)

	t.Run("it stands for the new identity, checked at its server", func(t *testing.T) {
		verdict := f.verify(t, present(t, to, moved), audience, nonce)
		if verdict["state"] != services.AttestationVerified {
			t.Fatalf("verdict = %v", verdict)
		}
		holder := verdict["holder"].(map[string]any)
		if holder["fingerprint"] != to.fingerprint || holder["domain"] != peer.domain {
			t.Fatalf("holder = %v", holder)
		}
		row := f.api.T(t).Get(util.Coll.Attestations, attestationID, f.issuerToken).
			Expect().Status(http.StatusOK).JSON().Object()
		row.Value(util.Fields.Attestation.SubjectFingerprint).String().IsEqual(to.fingerprint)
		row.Value(util.Fields.Attestation.SubjectDomain).String().IsEqual(peer.domain)
	})

	t.Run("the credential it replaces is revoked", func(t *testing.T) {
		if v := f.verify(t, present(t, from, credential), audience, nonce); v["state"] != services.AttestationRevoked {
			t.Fatalf("verdict = %v", v)
		}
	})

	t.Run("not once the old identity's server has withdrawn it", func(t *testing.T) {
		_, second := claim(t)
		peer.mu.Lock()
		peer.identities[from.fingerprint] = server.IdentityStatusRevoked
		peer.mu.Unlock()
		expectRefusal(t, move(t, second, to, peer.domain, "remote-identity-2"),
			http.StatusForbidden, util.Errors.ReissueHolderRevoked.ErrorCode)
	})
}
