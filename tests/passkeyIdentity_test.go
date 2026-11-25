package tests

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"net/http"
	"strings"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"
)

// passkeyKey stands in for the key a browser derives from a passkey: a P-256
// key, which signs the way the page does (ECDSA over SHA-256, DER, base64).
type passkeyKey struct {
	priv *ecdsa.PrivateKey
	pem  string
}

func newPasskeyKey(t *testing.T) *passkeyKey {
	t.Helper()
	priv, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, _ := x509.MarshalPKIXPublicKey(&priv.PublicKey)
	return &passkeyKey{priv: priv, pem: string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der}))}
}

func (k *passkeyKey) sign(t *testing.T, message string) string {
	t.Helper()
	sum := sha256.Sum256([]byte(message))
	sig, err := ecdsa.SignASN1(rand.Reader, k.priv, sum[:])
	if err != nil {
		t.Fatal(err)
	}
	return base64.StdEncoding.EncodeToString(sig)
}

// registerPasskeyIdentity registers key as the page does.
func registerPasskeyIdentity(t *testing.T, api *testutils.PBClient, token, userID, wsID string, key *passkeyKey, primary bool) string {
	t.Helper()
	return api.Create(util.Coll.Identities, token, map[string]any{
		util.Fields.Identity.Name: "Browser identity", util.Fields.Identity.PublicKey: key.pem,
		util.Fields.Identity.Kind: util.IdentityKindPasskey, util.Fields.Identity.IsPrimary: primary,
		util.Fields.Identity.User: userID, util.Fields.Identity.Workspace: wsID,
	}).Expect().Status(http.StatusOK).JSON().Object().Value("id").String().Raw()
}

// A passkey identity is certified like any other, is always a P-256 key, and
// keeps its kind.
func TestPasskeyIdentityIsCertifiedLikeAnyOther(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatal(err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)

	id := registerPasskeyIdentity(t, api, token, userID, wsID, newPasskeyKey(t), false)
	rec := api.Get(util.Coll.Identities, id, token).Expect().Status(http.StatusOK).JSON().Object()
	rec.Value(util.Fields.Identity.Kind).String().IsEqual(util.IdentityKindPasskey)
	rec.Value(util.Fields.Identity.ParentSignature).String().NotEmpty()
	rec.Value(util.Fields.Identity.Certificate).String().Contains("BEGIN CERTIFICATE")
	rec.Value(util.Fields.Identity.PrivateKey).String().IsEmpty()

	rsa := testutils.NewTestIdentity(t, "not a passkey")
	api.Create(util.Coll.Identities, token, map[string]any{
		util.Fields.Identity.Name: "x", util.Fields.Identity.PublicKey: rsa.PublicKeyPem,
		util.Fields.Identity.Kind: util.IdentityKindPasskey, util.Fields.Identity.User: userID, util.Fields.Identity.Workspace: wsID,
	}).Expect().Status(http.StatusBadRequest)
	api.Create(util.Coll.Identities, token, map[string]any{
		util.Fields.Identity.Name: "x", util.Fields.Identity.PublicKey: newPasskeyKey(t).pem,
		util.Fields.Identity.Kind: "hardware", util.Fields.Identity.User: userID, util.Fields.Identity.Workspace: wsID,
	}).Expect().Status(http.StatusBadRequest)

	api.Update(util.Coll.Identities, id, token, map[string]any{util.Fields.Identity.Kind: ""}).
		Expect().Status(http.StatusOK).JSON().Object().Value(util.Fields.Identity.Kind).String().IsEqual(util.IdentityKindPasskey)
}

// What phase 4 unlocks, end to end with a passkey identity: a request that
// requires a verified identity, a share that does, and the identity claim of
// Sign in with Revoked.
func TestPasskeyIdentityUnlocksIdentityFlows(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	ownerID, ownerToken, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatal(err)
	}
	ownerWS := activeWorkspaceOf(t, api, ownerID, ownerToken)
	ownerIdentity, _ := newIdentity(t, baseURL, ownerToken, "club", ownerID, ownerWS)

	person := newBrowserPerson(t, baseURL)
	ws := activeWorkspaceOf(t, api, person.userID, person.token)
	key := newPasskeyKey(t)
	identityID := registerPasskeyIdentity(t, api, person.token, person.userID, ws, key, true)

	t.Run("a request that requires a verified identity", func(t *testing.T) {
		slug, _ := setupRequest(t, baseURL, ownerToken, ownerID, ownerWS, ownerIdentity, map[string]any{
			util.Fields.Request.RequireHandshake: true, util.Fields.Request.IdentityScope: "from_root",
		})
		answer := func() {
			nonce := api.E.GET("/api/challenges/request/"+slug).WithQuery("identityId", identityID).
				Expect().Status(http.StatusOK).JSON().Object().Value("nonce").String().Raw()
			api.E.POST("/api/public/requests/"+slug).WithHeader("Authorization", person.token).
				WithJSON(map[string]any{
					"identityId": identityID, "challengeNonce": nonce, "challengeSignature": key.sign(t, nonce),
					"data": map[string]any{"phone": "+49 30 1"},
				}).Expect().Status(http.StatusOK)
		}
		answer()
		// The page keeps no handshake token: signing again answers again.
		answer()
		link := api.E.GET("/api/collections/"+util.Coll.Links+"/records").
			WithQuery("filter", `user = "`+person.userID+`"`).WithHeader("Authorization", person.token).
			Expect().Status(http.StatusOK).JSON().Object().Value("items").Array().Value(0).Object()
		link.Value(util.Fields.Link.Identity).String().IsEqual(identityID)
	})

	t.Run("a share that requires a verified identity", func(t *testing.T) {
		slug, _ := pageShare(t, baseURL, ownerToken, ownerID, ownerWS, map[string]any{
			util.Fields.Link.RequireHandshake: true,
		})
		open := func() {
			nonce := api.E.GET("/api/challenges/link/"+slug).WithQuery("identityId", identityID).
				Expect().Status(http.StatusOK).JSON().Object().Value("nonce").String().Raw()
			api.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{
				"identityId": identityID, "challengeNonce": nonce, "challengeSignature": key.sign(t, nonce),
			}).Expect().Status(http.StatusOK).Body().Contains("page-canary-value-7f31")
		}
		open()
		// A handshake already made does not lock out a reader without its token.
		open()
		// Nor does it let one in without a signature.
		api.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{"identityId": identityID}).
			Expect().Status(http.StatusUnauthorized)

		page := api.E.GET("/s/"+slug).WithHeader("Accept", browserAccept).Expect().Status(http.StatusOK).Body().Raw()
		if !strings.Contains(page, `href="/s/`+slug+`/identity"`) {
			t.Fatal("the share page does not offer the browser")
		}
		api.E.GET("/s/"+slug+"/identity").WithHeader("Accept", browserAccept).
			Expect().Status(http.StatusOK).Body().NotContains("page-canary-value-7f31")
	})

	t.Run("the identity claim of Sign in with Revoked", func(t *testing.T) {
		svc := newOIDCService(t, baseURL, "https://game.example")
		consent := person.open(t, svc.params(nil))
		ticket := consent["ticket"].(string)
		status, out := person.consent(t, map[string]any{
			"ticket": ticket, "approve": true, "scopes": []string{util.OIDCScopeIdentity},
			"identityId": identityID, "signature": key.sign(t, "revoked-oidc-consent:"+ticket),
		})
		if status != http.StatusOK {
			t.Fatalf("consent: %d %v", status, out)
		}
		resp, tokens := svc.redeem(redirectParams(t, out["redirect"].(string)).Get("code"))
		if resp.StatusCode != http.StatusOK || tokens["scope"] != "openid revoked_identity" {
			t.Fatalf("token: %d %v", resp.StatusCode, tokens)
		}
		claims := verifyIDToken(t, baseURL, tokens["id_token"].(string))
		if claims[util.OIDCScopeIdentity] == nil {
			t.Fatalf("the identity claim is missing: %v", claims)
		}
	})

	t.Run("a revoked passkey identity unlocks nothing", func(t *testing.T) {
		revokeIdentity(t, api, identityID, person.token, util.RevocationKeyCompromise)
		slug, _ := pageShare(t, baseURL, ownerToken, ownerID, ownerWS, map[string]any{
			util.Fields.Link.RequireHandshake: true,
		})
		nonce := api.E.GET("/api/challenges/link/"+slug).WithQuery("identityId", identityID).
			Expect().Status(http.StatusOK).JSON().Object().Value("nonce").String().Raw()
		api.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{
			"identityId": identityID, "challengeNonce": nonce, "challengeSignature": key.sign(t, nonce),
		}).Expect().Status(http.StatusForbidden)
	})
}
