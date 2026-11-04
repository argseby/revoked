package tests

import (
	"io"
	"net/http"
	"strings"
	"testing"

	"revoked/cmd/revoked/services"
	"revoked/util"
)

// A holder makes a link that shows one attestation to whoever opens it. The
// link holds a presentation the holder signed for it; its status is checked
// again on every view, and the holder can end it.

type shareFixture struct {
	attestationFixture
	attestationID string
	credentialID  string
	credential    string
}

func newShareFixture(t *testing.T) shareFixture {
	t.Helper()
	f := newAttestationFixture(t)
	id, token := f.offer(t, nil)
	row := f.acceptLocal(t, token)
	return shareFixture{
		attestationFixture: f,
		attestationID:      id,
		credentialID:       row["id"].(string),
		credential:         row[util.Fields.Credential.Credential].(string),
	}
}

// start begins a link as the holder and returns what the presentation must
// be bound to.
func (f shareFixture) start(t *testing.T, days int) (id, audience, nonce string) {
	t.Helper()
	resp := postJSON(t, f.baseURL+"/api/attestation-shares", f.holderToken, map[string]any{
		"credential": f.credentialID, "days": days,
	})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("starting a link answered %d: %v", resp.StatusCode, decode(t, resp))
	}
	out := decode(t, resp)
	return out["id"].(string), out["audience"].(string), out["nonce"].(string)
}

func (f shareFixture) activate(t *testing.T, id, presentation string) *http.Response {
	t.Helper()
	return postJSON(t, f.baseURL+"/api/attestation-shares/"+id+"/activate", f.holderToken,
		map[string]any{"presentation": presentation})
}

// open makes a link showing [disclose] and returns its token.
func (f shareFixture) open(t *testing.T, disclose []string) (id, token string) {
	t.Helper()
	id, audience, nonce := f.start(t, 7)
	resp := f.activate(t, id, f.present(t, f.credential, disclose, audience, nonce))
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("activating answered %d: %v", resp.StatusCode, decode(t, resp))
	}
	out := decode(t, resp)
	if !strings.HasSuffix(out["url"].(string), "/p/"+out["token"].(string)) {
		t.Fatalf("url = %v", out["url"])
	}
	return id, out["token"].(string)
}

func TestAttestationShareShowsWhatTheHolderPicked(t *testing.T) {
	f := newShareFixture(t)
	id, token := f.open(t, []string{"age_over_18"})

	t.Run("anyone with the link sees the attestation, verified", func(t *testing.T) {
		shown := f.api.E.GET("/api/public/attestation-shares/" + token).
			Expect().Status(http.StatusOK).JSON().Object()
		shown.Value("state").String().IsEqual(services.AttestationVerified)
		shown.Value("issuer").String().IsEqual(testDomain)
		shown.Value("type").String().IsEqual("membership")
		shown.Value("keyBound").Boolean().IsTrue()
		claims := shown.Value("claims").Object()
		claims.Keys().Length().IsEqual(1)
		claims.Value("age_over_18").Boolean().IsTrue()
		shown.Value("withheld").Number().IsEqual(2)
		shown.Value("holder").Object().Value("fingerprint").String().NotEmpty()
	})

	t.Run("the page shows it to a browser", func(t *testing.T) {
		req, _ := http.NewRequest(http.MethodGet, f.baseURL+"/p/"+token, nil)
		req.Header.Set("Accept", "text/html")
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		body, _ := io.ReadAll(resp.Body)
		if resp.StatusCode != http.StatusOK || !strings.Contains(string(body), "age_over_18") ||
			strings.Contains(string(body), "Ada Lovelace") {
			t.Fatalf("page %d:\n%s", resp.StatusCode, body)
		}
	})

	t.Run("the holder sees the link and how often it was opened, never its secrets", func(t *testing.T) {
		row := f.api.E.GET("/api/collections/"+util.Coll.AttestationShares+"/records/"+id).
			WithHeader("Authorization", f.holderToken).
			Expect().Status(http.StatusOK).JSON().Object().Raw()
		s := util.Fields.AttestationShare
		for _, hidden := range []string{s.Presentation, s.Nonce, s.TokenHash} {
			if _, leaked := row[hidden]; leaked {
				t.Fatalf("%s is readable through the collection API", hidden)
			}
		}
		if row[s.ViewCount] != float64(2) || row[s.Status] != util.ShareLinkActive {
			t.Fatalf("row = %v", row)
		}
		f.api.E.GET("/api/collections/"+util.Coll.AttestationShares+"/records/"+id).
			WithHeader("Authorization", f.issuerToken).
			Expect().Status(http.StatusNotFound)
	})

	t.Run("when the issuer revokes the attestation, the link says so", func(t *testing.T) {
		a := util.Fields.Attestation
		f.api.T(t).Update(util.Coll.Attestations, f.attestationID, f.issuerToken, map[string]any{
			a.Status: util.StatusRevoked,
		}).Expect().Status(http.StatusOK)
		f.api.E.GET("/api/public/attestation-shares/" + token).
			Expect().Status(http.StatusOK).JSON().Object().
			Value("state").String().IsEqual(services.AttestationRevoked)
	})

	t.Run("the holder ends it, and it shows nothing more", func(t *testing.T) {
		resp := postJSON(t, f.baseURL+"/api/attestation-shares/"+id+"/revoke", f.holderToken, map[string]any{})
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("revoke answered %d", resp.StatusCode)
		}
		f.api.E.GET("/api/public/attestation-shares/" + token).Expect().Status(http.StatusGone).
			JSON().Object().Value("code").String().IsEqual(util.Errors.AttestationShareClosed.ErrorCode)
	})
}

func TestAttestationShareRefusals(t *testing.T) {
	f := newShareFixture(t)

	t.Run("only the holder starts one, for a sensible time", func(t *testing.T) {
		for _, c := range []struct {
			token string
			body  map[string]any
			code  int
		}{
			{"", map[string]any{"credential": f.credentialID, "days": 7}, http.StatusUnauthorized},
			{f.issuerToken, map[string]any{"credential": f.credentialID, "days": 7}, http.StatusBadRequest},
			{f.holderToken, map[string]any{"credential": f.credentialID, "days": 0}, http.StatusBadRequest},
			{f.holderToken, map[string]any{"credential": f.credentialID, "days": 91}, http.StatusBadRequest},
			{f.holderToken, map[string]any{"credential": "nope", "days": 7}, http.StatusBadRequest},
		} {
			if resp := postJSON(t, f.baseURL+"/api/attestation-shares", c.token, c.body); resp.StatusCode != c.code {
				t.Errorf("%v answered %d, want %d", c.body, resp.StatusCode, c.code)
			}
		}
	})

	t.Run("a presentation for another occasion does not open it", func(t *testing.T) {
		id, audience, nonce := f.start(t, 1)
		for _, presentation := range []string{
			"not-a-credential",
			f.present(t, f.credential, nil, "https://shop.example", nonce),
			f.present(t, f.credential, nil, audience, "another-nonce"),
		} {
			if resp := f.activate(t, id, presentation); resp.StatusCode != http.StatusBadRequest {
				t.Fatalf("activation answered %d", resp.StatusCode)
			}
		}
		// Someone else cannot open the holder's link either.
		resp := postJSON(t, f.baseURL+"/api/attestation-shares/"+id+"/activate", f.issuerToken,
			map[string]any{"presentation": f.present(t, f.credential, nil, audience, nonce)})
		if resp.StatusCode != http.StatusNotFound {
			t.Fatalf("another user's activation answered %d", resp.StatusCode)
		}
	})

	t.Run("a link is signed once", func(t *testing.T) {
		id, audience, nonce := f.start(t, 1)
		if resp := f.activate(t, id, f.present(t, f.credential, nil, audience, nonce)); resp.StatusCode != http.StatusOK {
			t.Fatalf("first activation answered %d", resp.StatusCode)
		}
		if resp := f.activate(t, id, f.present(t, f.credential, nil, audience, nonce)); resp.StatusCode != http.StatusGone {
			t.Fatalf("second activation answered %d", resp.StatusCode)
		}
	})

	t.Run("a pending or unknown link shows nothing", func(t *testing.T) {
		f.api.E.GET("/api/public/attestation-shares/" + strings.Repeat("ab", 32)).
			Expect().Status(http.StatusNotFound)
		f.api.E.GET("/api/public/attestation-shares/").Expect().Status(http.StatusNotFound)
	})

	t.Run("removing the attestation removes its links", func(t *testing.T) {
		_, token := f.open(t, nil)
		f.api.T(t).Delete(util.Coll.Credentials, f.credentialID, f.holderToken).
			Expect().Status(http.StatusNoContent)
		f.api.E.GET("/api/public/attestation-shares/" + token).Expect().Status(http.StatusNotFound)
	})
}
