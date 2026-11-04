package tests

import (
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// oidcService plays a service signing people in with Revoked: an origin, a
// redirect address on it, and a PKCE pair per sign-in. It never follows
// redirects, so where the provider sends the browser can be inspected.
type oidcService struct {
	t        *testing.T
	baseURL  string
	clientID string
	redirect string
	verifier string
	http     *http.Client
}

func newOIDCService(t *testing.T, baseURL, origin string) *oidcService {
	return &oidcService{
		t: t, baseURL: baseURL, clientID: origin, redirect: origin + "/callback",
		http: &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }},
	}
}

// params builds an authorization request with a fresh PKCE pair, overlaying
// extra on the standard parameters; an empty value removes one.
func (s *oidcService) params(extra map[string]string) url.Values {
	s.t.Helper()
	verifier, challenge := testutils.PKCEPair()
	s.verifier = verifier
	q := url.Values{
		"client_id":             {s.clientID},
		"redirect_uri":          {s.redirect},
		"response_type":         {"code"},
		"scope":                 {"openid profile email revoked_identity"},
		"state":                 {"st-123"},
		"nonce":                 {"n-456"},
		"code_challenge":        {challenge},
		"code_challenge_method": {"S256"},
	}
	for k, v := range extra {
		if v == "" {
			q.Del(k)
		} else {
			q.Set(k, v)
		}
	}
	return q
}

// authorize opens the authorization endpoint the way a browser sent there by
// the service does.
func (s *oidcService) authorize(extra map[string]string) *http.Response {
	s.t.Helper()
	resp, err := s.http.Get(s.baseURL + util.OIDCPagePath + "?" + s.params(extra).Encode())
	if err != nil {
		s.t.Fatal(err)
	}
	return resp
}

var pageAppLink = regexp.MustCompile(`appLink: "([^"]+)"`)

// appLink reads the revoked://signin link off the rendered page.
func appLink(t *testing.T, resp *http.Response) *url.URL {
	t.Helper()
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("authorize page: %d %s", resp.StatusCode, raw)
	}
	m := pageAppLink.FindSubmatch(raw)
	if m == nil {
		t.Fatalf("no app link on the page")
	}
	var link string
	if err := json.Unmarshal([]byte(`"`+string(m[1])+`"`), &link); err != nil {
		t.Fatal(err)
	}
	u, err := url.Parse(link)
	if err != nil {
		t.Fatal(err)
	}
	return u
}

// redirectParams reads the query the provider sent the browser back with.
func redirectParams(t *testing.T, location string) url.Values {
	t.Helper()
	u, err := url.Parse(location)
	if err != nil {
		t.Fatal(err)
	}
	return u.Query()
}

// oidcPerson is someone signed in to the Revoked app on their device: a
// session, and an identity whose private key only the device holds.
type oidcPerson struct {
	baseURL, userID, token, identityID string
	key                                *testutils.IdentityKeyPair
}

func newOIDCPerson(t *testing.T, baseURL string) *oidcPerson {
	t.Helper()
	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatal(err)
	}
	api := testutils.NewPBClient(t, baseURL)
	identityID, key := newIdentity(t, baseURL, token, "app", userID, activeWorkspaceOf(t, api, userID, token))
	return &oidcPerson{baseURL: baseURL, userID: userID, token: token, identityID: identityID, key: key}
}

// post sends a JSON body with the app's session and decodes the answer.
func (p *oidcPerson) post(t *testing.T, path string, body any) (int, map[string]any) {
	t.Helper()
	resp := postJSON(t, p.baseURL+path, p.token, body)
	defer resp.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&out)
	return resp.StatusCode, out
}

// open opens a request in the app, as a revoked://signin link does.
func (p *oidcPerson) open(t *testing.T, q url.Values) (int, map[string]any) {
	t.Helper()
	params := map[string]string{}
	for k := range q {
		params[k] = q.Get(k)
	}
	return p.post(t, "/oidc/authorize/app", map[string]any{"params": params})
}

// decide answers an opened request, signing an approval with the device key.
func (p *oidcPerson) decide(t *testing.T, ticket string, decision map[string]any) (int, map[string]any) {
	t.Helper()
	body := map[string]any{"ticket": ticket}
	if decision["approve"] == true {
		body["identityId"] = p.identityID
		body["signature"] = p.key.SignChallenge(t, "revoked-oidc-consent:"+ticket)
	}
	for k, v := range decision {
		body[k] = v
	}
	return p.post(t, "/oidc/authorize/consent", body)
}

// approve runs the app's part: it opens the request and records the
// decision. It returns the consent data and the redirect.
func (p *oidcPerson) approve(t *testing.T, q url.Values, decision map[string]any) (map[string]any, string) {
	t.Helper()
	status, consent := p.open(t, q)
	if status != http.StatusOK || consent["ticket"] == nil {
		t.Fatalf("open: %d %v", status, consent)
	}
	status, out := p.decide(t, consent["ticket"].(string), decision)
	if status != http.StatusOK {
		t.Fatalf("consent: %d %v", status, out)
	}
	return consent, out["redirect"].(string)
}

func (s *oidcService) redeem(code string) (*http.Response, map[string]any) {
	s.t.Helper()
	form := url.Values{
		"grant_type":    {"authorization_code"},
		"code":          {code},
		"client_id":     {s.clientID},
		"redirect_uri":  {s.redirect},
		"code_verifier": {s.verifier},
	}
	resp, err := s.http.PostForm(s.baseURL+"/oidc/token", form)
	if err != nil {
		s.t.Fatal(err)
	}
	defer resp.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&out)
	return resp, out
}

// verifyIDToken checks a token the way a client library does, against the
// published key — and, beyond that, checks that the root key certified it.
func verifyIDToken(t *testing.T, baseURL, raw string) jwt.MapClaims {
	t.Helper()
	var discovery struct {
		Issuer  string `json:"issuer"`
		JWKSURI string `json:"jwks_uri"`
	}
	getJSON(t, baseURL+"/.well-known/openid-configuration", &discovery)
	var jwks struct {
		Keys []server.JWK `json:"keys"`
	}
	getJSON(t, baseURL+"/oidc/jwks", &jwks)
	if len(jwks.Keys) != 1 {
		t.Fatalf("jwks: %v", jwks)
	}
	var serverInfo struct {
		PublicKey string `json:"publicKey"`
	}
	getJSON(t, baseURL+"/api/server", &serverInfo)
	if _, err := server.VerifySigningKey(jwks.Keys[0], serverInfo.PublicKey, testDomain); err != nil {
		t.Fatalf("published signing key is not certified by the root key: %v", err)
	}

	claims := jwt.MapClaims{}
	_, err := jwt.ParseWithClaims(raw, claims, func(tok *jwt.Token) (any, error) {
		if tok.Header["kid"] != jwks.Keys[0].Kid {
			t.Fatalf("token kid %v is not the published key", tok.Header["kid"])
		}
		n, _ := base64.RawURLEncoding.DecodeString(jwks.Keys[0].N)
		e, _ := base64.RawURLEncoding.DecodeString(jwks.Keys[0].E)
		return &rsa.PublicKey{N: new(big.Int).SetBytes(n), E: int(new(big.Int).SetBytes(e).Int64())}, nil
	}, jwt.WithValidMethods([]string{"RS256"}), jwt.WithIssuer(discovery.Issuer))
	if err != nil {
		t.Fatalf("id token did not verify: %v", err)
	}
	return claims
}

// discoveredIssuer reads the issuer from discovery, sending host as the Host
// header when it is set.
func discoveredIssuer(t *testing.T, baseURL, host string) string {
	t.Helper()
	req, _ := http.NewRequest(http.MethodGet, baseURL+"/.well-known/openid-configuration", nil)
	if host != "" {
		req.Host = host
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var out struct {
		Issuer string `json:"issuer"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatal(err)
	}
	return out.Issuer
}

// A server is reached at its domain in production and at localhost while it
// is developed on, and a client must see the issuer it actually talks to. Any
// other Host header falls back to the domain.
func TestOIDCIssuerFollowsOnlyTheDomainOrLoopback(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	port := strings.TrimPrefix(baseURL, "http://127.0.0.1")
	for host, want := range map[string]string{
		"localhost" + port:              "http://localhost" + port,
		testDomain:                      "https://" + testDomain,
		"evil.example":                  "https://" + testDomain,
		"localhost.evil.example" + port: "https://" + testDomain,
	} {
		if got := discoveredIssuer(t, baseURL, host); got != want {
			t.Errorf("Host %s: issuer %s, want %s", host, got, want)
		}
	}
}

func getJSON(t *testing.T, target string, out any) {
	t.Helper()
	resp, err := http.Get(target)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("GET %s: %d", target, resp.StatusCode)
	}
	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		t.Fatal(err)
	}
}

func userinfo(t *testing.T, baseURL, token string) (int, map[string]any) {
	t.Helper()
	req, _ := http.NewRequest(http.MethodGet, baseURL+"/oidc/userinfo", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&out)
	return resp.StatusCode, out
}

func TestSignInWithRevoked(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	person := newOIDCPerson(t, baseURL)
	userID, token := person.userID, person.token
	wsID := activeWorkspaceOf(t, api, userID, token)
	recordID := extractID(t, baseURL, util.Coll.Records, token, map[string]any{
		util.Fields.Record.Key:       "shipping_address",
		util.Fields.Record.Value:     "1 Infinite Loop",
		util.Fields.Record.Label:     "Shipping address",
		util.Fields.Record.Type:      util.TypeText,
		util.Fields.Record.Format:    util.FormatDefault,
		util.Fields.Record.User:      userID,
		util.Fields.Record.Workspace: wsID,
	})

	game := newOIDCService(t, baseURL, "https://game.example")
	consent, location := person.approve(t, game.params(map[string]string{
		"claims": `{"userinfo":{"revoked_links":{"values":["shipping_address"]}}}`,
	}), map[string]any{
		"approve": true,
		// The person keeps their identity to themselves.
		"scopes": []string{util.OIDCScopeProfile, util.OIDCScopeEmail},
		"name":   map[string]string{"kind": services.NameFromIdentity, "id": person.identityID},
		"links":  map[string]string{"shipping_address": recordID},
	})

	t.Run("the consent screen offers the matching entry first", func(t *testing.T) {
		links := consent["links"].([]any)
		first := links[0].(map[string]any)["options"].([]any)[0].(map[string]any)
		if first["id"] != recordID {
			t.Fatalf("first option = %v", first)
		}
	})

	params := redirectParams(t, location)
	if !strings.HasPrefix(location, game.redirect+"?") || params.Get("state") != "st-123" ||
		params.Get("iss") != discoveredIssuer(t, baseURL, "") || params.Get("code") == "" {
		t.Fatalf("redirect = %s", location)
	}
	resp, tokens := game.redeem(params.Get("code"))
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("token: %d %v", resp.StatusCode, tokens)
	}

	var sub string
	t.Run("the ID token verifies and carries what was agreed", func(t *testing.T) {
		claims := verifyIDToken(t, baseURL, tokens["id_token"].(string))
		if claims["aud"] != game.clientID || claims["nonce"] != "n-456" {
			t.Fatalf("claims = %v", claims)
		}
		if claims["email"] == nil || claims["email_verified"] == nil {
			t.Fatalf("email missing: %v", claims)
		}
		if _, leaked := claims[util.OIDCScopeIdentity]; leaked {
			t.Fatal("a declined scope reached the token")
		}
		if _, leaked := claims[util.OIDCClaimLinks]; leaked {
			t.Fatal("grant tokens belong at userinfo, not in the ID token")
		}
		sub = claims["sub"].(string)
		if sub == "" || sub == userID {
			t.Fatalf("sub = %q", sub)
		}
		if tokens["scope"] != "openid profile email" {
			t.Fatalf("scope = %v", tokens["scope"])
		}
	})

	t.Run("a code is redeemed once", func(t *testing.T) {
		resp, out := game.redeem(params.Get("code"))
		if resp.StatusCode != http.StatusBadRequest || out["error"] != "invalid_grant" {
			t.Fatalf("second redemption: %d %v", resp.StatusCode, out)
		}
	})

	t.Run("userinfo hands over a grant, which reads the live value", func(t *testing.T) {
		status, info := userinfo(t, baseURL, tokens["access_token"].(string))
		if status != http.StatusOK || info["sub"] != sub {
			t.Fatalf("userinfo: %d %v", status, info)
		}
		links := info[util.OIDCClaimLinks].(map[string]any)
		if links["endpoint"] != discoveredIssuer(t, baseURL, "")+"/api/grants/resolve" {
			t.Fatalf("endpoint = %v", links["endpoint"])
		}
		g := links["grants"].([]any)[0].(map[string]any)
		read := func() map[string]any {
			return api.E.POST("/api/grants/resolve").
				WithJSON(map[string]any{"grants": []map[string]any{{"id": g["id"], "token": g["token"]}}}).
				Expect().Status(http.StatusOK).JSON().Object().Value("items").Array().Value(0).Object().Raw()
		}
		if v := read()["values"].(map[string]any)["shipping_address"]; v != "1 Infinite Loop" {
			t.Fatalf("value = %v", v)
		}
		api.Update(util.Coll.Records, recordID, token, map[string]any{
			util.Fields.Record.Value: "2 Infinite Loop",
		}).Expect().Status(http.StatusOK)
		if v := read()["values"].(map[string]any)["shipping_address"]; v != "2 Infinite Loop" {
			t.Fatalf("value after edit = %v", v)
		}

		// The person sees the grant as a link of their own and can revoke it.
		link := api.Get(util.Coll.Links, g["id"].(string), token).Expect().Status(http.StatusOK).JSON().Object()
		link.Value(util.Fields.Link.SignInClient).String().IsEqual(game.clientID)
		api.Update(util.Coll.Links, g["id"].(string), token, map[string]any{
			util.Fields.Link.Status: util.StatusRevoked,
		}).Expect().Status(http.StatusOK)
		if r := read(); r["status"] != util.StatusRevoked || r["values"] != nil {
			t.Fatalf("after revoking: %v", r)
		}
	})

	t.Run("the same person is the same subject at the same service, and another at another", func(t *testing.T) {
		again := newOIDCService(t, baseURL, game.clientID)
		_, loc := person.approve(t, again.params(nil), map[string]any{"approve": true})
		_, tk := again.redeem(redirectParams(t, loc).Get("code"))
		if verifyIDToken(t, baseURL, tk["id_token"].(string))["sub"] != sub {
			t.Fatal("subject changed between sign-ins at one service")
		}

		other := newOIDCService(t, baseURL, "https://shop.example")
		_, loc = person.approve(t, other.params(nil), map[string]any{"approve": true})
		_, tk = other.redeem(redirectParams(t, loc).Get("code"))
		if verifyIDToken(t, baseURL, tk["id_token"].(string))["sub"] == sub {
			t.Fatal("two services see the same subject for one person")
		}
	})

	t.Run("declining sends the person back with access_denied", func(t *testing.T) {
		svc := newOIDCService(t, baseURL, game.clientID)
		_, loc := person.approve(t, svc.params(nil), map[string]any{"approve": false})
		p := redirectParams(t, loc)
		if p.Get("error") != "access_denied" || p.Get("code") != "" || p.Get("state") != "st-123" {
			t.Fatalf("redirect = %s", loc)
		}
	})

	t.Run("an entry that is not the person's cannot be shared", func(t *testing.T) {
		otherID, otherToken, err := testutils.CreateRandomUser(baseURL)
		if err != nil {
			t.Fatal(err)
		}
		foreign := extractID(t, baseURL, util.Coll.Records, otherToken, map[string]any{
			util.Fields.Record.Key:       "shipping_address",
			util.Fields.Record.Value:     "not yours",
			util.Fields.Record.Label:     "Theirs",
			util.Fields.Record.Type:      util.TypeText,
			util.Fields.Record.Format:    util.FormatDefault,
			util.Fields.Record.User:      otherID,
			util.Fields.Record.Workspace: activeWorkspaceOf(t, api, otherID, otherToken),
		})
		svc := newOIDCService(t, baseURL, game.clientID)
		_, consent := person.open(t, svc.params(map[string]string{
			"claims": `{"userinfo":{"revoked_links":{"values":["shipping_address"]}}}`,
		}))
		status, out := person.decide(t, consent["ticket"].(string), map[string]any{
			"approve": true, "links": map[string]string{"shipping_address": foreign},
		})
		if status != http.StatusBadRequest || out["code"] != util.Errors.OIDCLinkRecordInvalid.ErrorCode {
			t.Fatalf("consent: %d %v", status, out)
		}
	})
}

func TestOIDCRefusesBadRequests(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	svc := newOIDCService(t, baseURL, "https://game.example")

	t.Run("a redirect off the client's origin is never followed", func(t *testing.T) {
		resp := svc.authorize(map[string]string{"redirect_uri": "https://evil.example/callback"})
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusBadRequest || resp.Header.Get("Location") != "" {
			t.Fatalf("status %d, location %q", resp.StatusCode, resp.Header.Get("Location"))
		}
	})

	for name, tc := range map[string]struct {
		extra map[string]string
		want  string
	}{
		"PKCE is required":           {map[string]string{"code_challenge": ""}, "invalid_request"},
		"plain PKCE is refused":      {map[string]string{"code_challenge_method": "plain"}, "invalid_request"},
		"openid is required":         {map[string]string{"scope": "profile"}, "invalid_scope"},
		"only the code flow":         {map[string]string{"response_type": "token"}, "unsupported_response_type"},
		"no silent sign-in":          {map[string]string{"prompt": "none"}, "login_required"},
		"claims must be valid":       {map[string]string{"claims": "{"}, "invalid_request"},
		"links must name vault keys": {map[string]string{"claims": `{"userinfo":{"revoked_links":{"values":["Not A Key"]}}}`}, "invalid_request"},
	} {
		t.Run(name, func(t *testing.T) {
			resp := svc.authorize(tc.extra)
			resp.Body.Close()
			if resp.StatusCode != http.StatusFound {
				t.Fatalf("status = %d", resp.StatusCode)
			}
			p := redirectParams(t, resp.Header.Get("Location"))
			if p.Get("error") != tc.want || p.Get("state") != "st-123" {
				t.Fatalf("location = %s", resp.Header.Get("Location"))
			}
		})
	}

	t.Run("a wrong verifier does not redeem the code", func(t *testing.T) {
		_, loc := newOIDCPerson(t, baseURL).approve(t, svc.params(nil), map[string]any{"approve": true})
		svc.verifier = strings.Repeat("x", 43)
		resp, out := svc.redeem(redirectParams(t, loc).Get("code"))
		if resp.StatusCode != http.StatusBadRequest || out["error"] != "invalid_grant" {
			t.Fatalf("token: %d %v", resp.StatusCode, out)
		}
	})

	t.Run("userinfo refuses an unknown token", func(t *testing.T) {
		if status, _ := userinfo(t, baseURL, "not-a-token"); status != http.StatusUnauthorized {
			t.Fatalf("status = %d", status)
		}
	})

	t.Run("a sign-in request is used once", func(t *testing.T) {
		person := newOIDCPerson(t, baseURL)
		_, consent := person.open(t, svc.params(nil))
		ticket := consent["ticket"].(string)
		if status, out := person.decide(t, ticket, map[string]any{"approve": true}); status != http.StatusOK {
			t.Fatalf("first answer: %d %v", status, out)
		}
		status, out := person.decide(t, ticket, map[string]any{"approve": true})
		if status != http.StatusBadRequest || out["code"] != util.Errors.OIDCRequestInvalid.ErrorCode {
			t.Fatalf("second answer: %d %v", status, out)
		}
	})
}

// A sign-in is approved in the Revoked app, and the browser can only pass the
// request on to it.
func TestSignInIsApprovedOnlyInTheApp(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	svc := newOIDCService(t, baseURL, "https://game.example")
	person := newOIDCPerson(t, baseURL)

	t.Run("the page hands the request to the app, which signs the person in", func(t *testing.T) {
		resp := svc.authorize(map[string]string{
			"claims":         `{"userinfo":{"revoked_links":{"values":["phone"]}}}`,
			"revoked_return": "background",
		})
		link := appLink(t, resp)
		if link.Scheme != "revoked" || link.Host != "signin" {
			t.Fatalf("app link = %s", link)
		}
		q := link.Query()
		if q.Get("client_id") != svc.clientID || q.Get("state") != "st-123" || q.Get("claims") == "" ||
			q.Get("revoked_return") != "background" {
			t.Fatalf("app link query = %v", q)
		}
		_, loc := person.approve(t, q, map[string]any{"approve": true})
		p := redirectParams(t, loc)
		if p.Get("state") != "st-123" || p.Get("code") == "" {
			t.Fatalf("redirect = %s", loc)
		}
		if resp, out := svc.redeem(p.Get("code")); resp.StatusCode != http.StatusOK {
			t.Fatalf("token: %d %v", resp.StatusCode, out)
		}
	})

	t.Run("the page asks for no passkey and decides nothing", func(t *testing.T) {
		resp := svc.authorize(nil)
		defer resp.Body.Close()
		raw, _ := io.ReadAll(resp.Body)
		for _, s := range []string{"/api/passkeys", "/oidc/authorize/consent", "navigator.credentials"} {
			if strings.Contains(string(raw), s) {
				t.Fatalf("the page still reaches for %s", s)
			}
		}
		r, err := http.Post(baseURL+"/oidc/authorize/session", "application/json", strings.NewReader(`{}`))
		if err != nil {
			t.Fatal(err)
		}
		_ = r.Body.Close()
		if r.StatusCode != http.StatusNotFound {
			t.Fatalf("the browser's session route answers %d", r.StatusCode)
		}
	})

	t.Run("a request is not opened without the app's session", func(t *testing.T) {
		resp := postJSON(t, baseURL+"/oidc/authorize/app", "", map[string]any{"params": map[string]string{}})
		if out := decode(t, resp); resp.StatusCode != http.StatusUnauthorized ||
			out["code"] != util.Errors.NotAuthenticated.ErrorCode {
			t.Fatalf("open: %d %v", resp.StatusCode, out)
		}
	})

	t.Run("a refusal reaches the service through the app", func(t *testing.T) {
		status, out := person.open(t, svc.params(map[string]string{"prompt": "none"}))
		if status != http.StatusOK || out["ticket"] != nil {
			t.Fatalf("open: %d %v", status, out)
		}
		if p := redirectParams(t, out["redirect"].(string)); p.Get("error") != "login_required" || p.Get("state") != "st-123" {
			t.Fatalf("redirect = %v", out["redirect"])
		}
	})

	t.Run("a service that did not identify itself is not answered", func(t *testing.T) {
		status, out := person.open(t, svc.params(map[string]string{"redirect_uri": "https://evil.example/callback"}))
		if status != http.StatusBadRequest || out["redirect"] != nil || out["code"] != util.Errors.OIDCRequestInvalid.ErrorCode {
			t.Fatalf("open: %d %v", status, out)
		}
	})

	// refused opens a request and answers it with body, which must be refused
	// with code; the ticket is spent either way.
	refused := func(t *testing.T, opener, answerer *oidcPerson, body map[string]any, wantStatus int, wantCode string) {
		t.Helper()
		_, consent := opener.open(t, svc.params(nil))
		ticket := consent["ticket"].(string)
		body["ticket"] = ticket
		status, out := answerer.post(t, "/oidc/authorize/consent", body)
		if status != wantStatus || out["code"] != wantCode {
			t.Fatalf("consent: %d %v", status, out)
		}
		if status, _ := opener.decide(t, ticket, map[string]any{"approve": true}); status != http.StatusBadRequest {
			t.Fatalf("the ticket survived a refused answer: %d", status)
		}
	}

	t.Run("a session alone cannot approve", func(t *testing.T) {
		refused(t, person, person, map[string]any{"approve": true},
			http.StatusUnauthorized, util.Errors.IdentityRequired.ErrorCode)
	})

	t.Run("a key the identity does not hold cannot approve", func(t *testing.T) {
		stranger := testutils.NewTestIdentity(t, "stranger")
		_, consent := person.open(t, svc.params(nil))
		ticket := consent["ticket"].(string)
		status, out := person.post(t, "/oidc/authorize/consent", map[string]any{
			"ticket": ticket, "approve": true, "identityId": person.identityID,
			"signature": stranger.SignChallenge(t, "revoked-oidc-consent:"+ticket),
		})
		if status != http.StatusUnauthorized || out["code"] != util.Errors.SignatureInvalid.ErrorCode {
			t.Fatalf("consent: %d %v", status, out)
		}
	})

	t.Run("a signature made for a challenge does not approve", func(t *testing.T) {
		_, consent := person.open(t, svc.params(nil))
		ticket := consent["ticket"].(string)
		status, out := person.post(t, "/oidc/authorize/consent", map[string]any{
			"ticket": ticket, "approve": true, "identityId": person.identityID,
			"signature": person.key.SignChallenge(t, ticket),
		})
		if status != http.StatusUnauthorized || out["code"] != util.Errors.SignatureInvalid.ErrorCode {
			t.Fatalf("consent: %d %v", status, out)
		}
	})

	other := newOIDCPerson(t, baseURL)

	t.Run("another person's identity cannot approve", func(t *testing.T) {
		_, consent := person.open(t, svc.params(nil))
		ticket := consent["ticket"].(string)
		status, out := person.post(t, "/oidc/authorize/consent", map[string]any{
			"ticket": ticket, "approve": true, "identityId": other.identityID,
			"signature": other.key.SignChallenge(t, "revoked-oidc-consent:"+ticket),
		})
		if status != http.StatusForbidden || out["code"] != util.Errors.IdentityNotOwned.ErrorCode {
			t.Fatalf("consent: %d %v", status, out)
		}
	})

	t.Run("another person's app cannot answer", func(t *testing.T) {
		refused(t, person, other, map[string]any{"approve": false},
			http.StatusBadRequest, util.Errors.OIDCRequestInvalid.ErrorCode)
	})

	t.Run("a revoked identity cannot approve", func(t *testing.T) {
		gone := newOIDCPerson(t, baseURL)
		revokeIdentity(t, testutils.NewPBClient(t, baseURL), gone.identityID, gone.token, util.RevocationKeyCompromise)
		_, consent := gone.open(t, svc.params(nil))
		status, out := gone.decide(t, consent["ticket"].(string), map[string]any{"approve": true})
		if status != http.StatusForbidden || out["code"] != util.Errors.IdentityRevoked.ErrorCode {
			t.Fatalf("consent: %d %v", status, out)
		}
	})
}

func TestSignInsLeaveARowThePersonCanFind(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	person := newOIDCPerson(t, baseURL)
	f := util.Fields.SignIn
	recordID := extractID(t, baseURL, util.Coll.Records, person.token, map[string]any{
		util.Fields.Record.Key:       "shipping_address",
		util.Fields.Record.Value:     "1 Infinite Loop",
		util.Fields.Record.Label:     "Shipping address",
		util.Fields.Record.Type:      util.TypeText,
		util.Fields.Record.Format:    util.FormatDefault,
		util.Fields.Record.User:      person.userID,
		util.Fields.Record.Workspace: activeWorkspaceOf(t, api, person.userID, person.token),
	})
	rows := func(who *oidcPerson) []any {
		return api.List(util.Coll.SignIns, who.token).Expect().Status(http.StatusOK).
			JSON().Object().Value("items").Array().Raw()
	}
	only := func() map[string]any {
		t.Helper()
		items := rows(person)
		if len(items) != 1 {
			t.Fatalf("rows = %v", items)
		}
		return items[0].(map[string]any)
	}

	svc := newOIDCService(t, baseURL, "https://forum.example")

	t.Run("declining writes nothing", func(t *testing.T) {
		person.approve(t, svc.params(nil), map[string]any{"approve": false})
		if items := rows(person); len(items) != 0 {
			t.Fatalf("rows after declining = %v", items)
		}
	})

	t.Run("an entry that is not theirs leaves no row", func(t *testing.T) {
		stranger := newOIDCPerson(t, baseURL)
		foreign := extractID(t, baseURL, util.Coll.Records, stranger.token, map[string]any{
			util.Fields.Record.Key:       "shipping_address",
			util.Fields.Record.Value:     "not yours",
			util.Fields.Record.Label:     "Theirs",
			util.Fields.Record.Type:      util.TypeText,
			util.Fields.Record.Format:    util.FormatDefault,
			util.Fields.Record.User:      stranger.userID,
			util.Fields.Record.Workspace: activeWorkspaceOf(t, api, stranger.userID, stranger.token),
		})
		_, consent := person.open(t, svc.params(map[string]string{
			"claims": `{"userinfo":{"revoked_links":{"values":["shipping_address"]}}}`,
		}))
		status, out := person.decide(t, consent["ticket"].(string), map[string]any{
			"approve": true, "links": map[string]string{"shipping_address": foreign},
		})
		if status != http.StatusBadRequest {
			t.Fatalf("consent: %d %v", status, out)
		}
		if items := rows(person); len(items) != 0 {
			t.Fatalf("rows after a refused sign-in = %v", items)
		}
	})

	person.approve(t, svc.params(map[string]string{
		"claims": `{"userinfo":{"revoked_links":{"values":["shipping_address"]}}}`,
	}), map[string]any{
		"approve": true,
		"scopes":  []string{util.OIDCScopeEmail},
		"links":   map[string]string{"shipping_address": recordID},
	})
	first := only()
	linkID, _ := first[f.Link].(string)

	t.Run("an approval records the service, its scopes and its link", func(t *testing.T) {
		if first[f.ClientId] != svc.clientID || linkID == "" {
			t.Fatalf("row = %v", first)
		}
		if got := first[f.Scopes].([]any); len(got) != 1 || got[0] != util.OIDCScopeEmail {
			t.Fatalf("scopes = %v", got)
		}
		api.Get(util.Coll.Links, linkID, person.token).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.Link.SignInClient).String().IsEqual(svc.clientID)
	})

	t.Run("signing in again keeps the one row, its link and what was learned", func(t *testing.T) {
		time.Sleep(5 * time.Millisecond)
		person.approve(t, svc.params(nil), map[string]any{
			"approve": true, "scopes": []string{util.OIDCScopeProfile},
			"name": map[string]string{"kind": services.NameFromIdentity, "id": person.identityID},
		})
		again := only()
		if again["id"] != first["id"] || again[f.Link] != linkID {
			t.Fatalf("row = %v, was %v", again, first)
		}
		got := again[f.Scopes].([]any)
		if len(got) != 2 || got[0] != util.OIDCScopeEmail || got[1] != util.OIDCScopeProfile {
			t.Fatalf("scopes = %v", got)
		}
		if again[f.LastSignInAt].(string) <= first[f.LastSignInAt].(string) {
			t.Fatalf("lastSignInAt did not move: %v then %v", first[f.LastSignInAt], again[f.LastSignInAt])
		}
	})

	t.Run("the audit log names the keys and never the values", func(t *testing.T) {
		logged, err := app.FindAllRecords(util.Coll.AuditLogs, dbx.HashExp{
			util.Fields.AuditLog.Collection: util.Coll.SignIns,
			util.Fields.AuditLog.RecordId:   first["id"].(string),
			util.Fields.AuditLog.Action:     "sign_in_approved",
		})
		if err != nil {
			t.Fatal(err)
		}
		if len(logged) != 2 {
			t.Fatalf("audit rows = %d, want one per approval", len(logged))
		}
		sharing := ""
		for _, row := range logged {
			if data := row.GetString(util.Fields.AuditLog.NewData); strings.Contains(data, "shipping_address") {
				sharing = data
			}
		}
		if !strings.Contains(sharing, svc.clientID) {
			t.Fatalf("no audit row names the key and the service: %v", logged)
		}
		if strings.Contains(sharing, "Infinite Loop") || strings.Contains(sharing, "token") {
			t.Fatalf("audit row holds more than names: %s", sharing)
		}
	})

	t.Run("it is the person's alone and nobody writes it through the API", func(t *testing.T) {
		id := first["id"].(string)
		stranger := newOIDCPerson(t, baseURL)
		if items := rows(stranger); len(items) != 0 {
			t.Fatalf("a stranger lists %v", items)
		}
		api.Get(util.Coll.SignIns, id, stranger.token).Expect().Status(http.StatusNotFound)
		api.Create(util.Coll.SignIns, person.token, map[string]any{
			f.User: person.userID, f.ClientId: "https://planted.example", f.LastSignInAt: "2026-01-01 00:00:00.000Z",
		}).Expect().Status(http.StatusForbidden)
		api.Update(util.Coll.SignIns, id, person.token, map[string]any{
			f.ClientId: "https://planted.example",
		}).Expect().Status(http.StatusForbidden)
		api.Delete(util.Coll.SignIns, id, person.token).Expect().Status(http.StatusForbidden)
	})
}

// A person gives each service the name they choose for it: one of their
// identities' names, or a vault entry that the service reads as it changes.
func TestSignInNameIsChosenPerService(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	person := newOIDCPerson(t, baseURL)
	wsID := activeWorkspaceOf(t, api, person.userID, person.token)

	entry := func(key, value, format string) string {
		return extractID(t, baseURL, util.Coll.Records, person.token, map[string]any{
			util.Fields.Record.Key:       key,
			util.Fields.Record.Value:     value,
			util.Fields.Record.Label:     key,
			util.Fields.Record.Type:      util.TypeText,
			util.Fields.Record.Format:    format,
			util.Fields.Record.User:      person.userID,
			util.Fields.Record.Workspace: wsID,
		})
	}
	nameOf := func(kind, id string) map[string]string { return map[string]string{"kind": kind, "id": id} }

	// signIn approves one sign-in and redeems its code.
	signIn := func(svc *oidcService, decision map[string]any) map[string]any {
		t.Helper()
		_, loc := person.approve(t, svc.params(map[string]string{"scope": "openid profile"}), decision)
		_, tokens := svc.redeem(redirectParams(t, loc).Get("code"))
		return tokens
	}
	idName := func(tokens map[string]any) any {
		t.Helper()
		return verifyIDToken(t, baseURL, tokens["id_token"].(string))["name"]
	}

	gamerTag := entry("gamer_tag", "xXAdaXx", util.FormatDefault)

	t.Run("no name picked means no name, even with the scope ticked", func(t *testing.T) {
		svc := newOIDCService(t, baseURL, "https://quiet.example")
		tokens := signIn(svc, map[string]any{"approve": true, "scopes": []string{util.OIDCScopeProfile}})
		if tokens["scope"] != "openid" {
			t.Fatalf("scope = %v", tokens["scope"])
		}
		if n := idName(tokens); n != nil {
			t.Fatalf("name = %v", n)
		}
	})

	t.Run("a name typed for the sign-in joins the service's section", func(t *testing.T) {
		svc := newOIDCService(t, baseURL, "https://typed.example")
		typed := entry("name_typed_example", "Ada at the table", util.FormatDefault)
		signIn(svc, map[string]any{
			"approve": true, "scopes": []string{util.OIDCScopeProfile},
			"name":    nameOf(services.NameFromRecord, typed),
			"created": []string{typed},
		})
		section, err := app.FindFirstRecordByFilter(util.Coll.Sections,
			util.Fields.Section.Key+" = 'signin_typed_example' && "+util.Fields.Section.User+" = {:u}",
			dbx.Params{"u": person.userID})
		if err != nil {
			t.Fatal(err)
		}
		if !slices.Contains(section.GetStringSlice(util.Fields.Section.Records), typed) {
			t.Fatalf("records = %v", section.GetStringSlice(util.Fields.Section.Records))
		}
	})

	t.Run("a name typed on a later sign-in joins the service's section too", func(t *testing.T) {
		svc := newOIDCService(t, baseURL, "https://again.example")
		signIn(svc, map[string]any{
			"approve": true, "scopes": []string{util.OIDCScopeProfile},
			"name": nameOf(services.NameFromIdentity, person.identityID),
		})
		typed := entry("name_again_example", "Ada again", util.FormatDefault)
		signIn(svc, map[string]any{
			"approve": true, "scopes": []string{util.OIDCScopeProfile},
			"name":    nameOf(services.NameFromRecord, typed),
			"created": []string{typed},
		})
		section, err := app.FindFirstRecordByFilter(util.Coll.Sections,
			util.Fields.Section.Key+" = 'signin_again_example' && "+util.Fields.Section.User+" = {:u}",
			dbx.Params{"u": person.userID})
		if err != nil {
			t.Fatal(err)
		}
		if !slices.Contains(section.GetStringSlice(util.Fields.Section.Records), typed) {
			t.Fatalf("records = %v", section.GetStringSlice(util.Fields.Section.Records))
		}
	})

	t.Run("each service keeps its own name", func(t *testing.T) {
		game := newOIDCService(t, baseURL, "https://game.example")
		shop := newOIDCService(t, baseURL, "https://shop.example")
		tag := signIn(game, map[string]any{
			"approve": true, "scopes": []string{util.OIDCScopeProfile},
			"name": nameOf(services.NameFromRecord, gamerTag),
		})
		formal := signIn(shop, map[string]any{
			"approve": true, "scopes": []string{util.OIDCScopeProfile},
			"name": nameOf(services.NameFromIdentity, person.identityID),
		})
		if n := idName(tag); n != "xXAdaXx" {
			t.Fatalf("game got %v", n)
		}
		if n := idName(formal); n == "xXAdaXx" || n == nil {
			t.Fatalf("shop got %v", n)
		}
	})

	t.Run("a name from the vault reaches the service when it changes, until revoked", func(t *testing.T) {
		live := newOIDCService(t, baseURL, "https://live.example")
		tokens := signIn(live, map[string]any{
			"approve": true, "scopes": []string{util.OIDCScopeProfile},
			"name": nameOf(services.NameFromRecord, gamerTag),
		})
		access := tokens["access_token"].(string)
		_, info := userinfo(t, baseURL, access)
		g := info[util.OIDCClaimLinks].(map[string]any)["grants"].([]any)[0].(map[string]any)
		if keys := g["keys"].([]any); len(keys) != 1 || keys[0] != services.SignInNameKey {
			t.Fatalf("keys = %v", keys)
		}
		read := func() map[string]any {
			return api.E.POST("/api/grants/resolve").
				WithJSON(map[string]any{"grants": []map[string]any{{"id": g["id"], "token": g["token"]}}}).
				Expect().Status(http.StatusOK).JSON().Object().Value("items").Array().Value(0).Object().Raw()
		}

		api.Update(util.Coll.Records, gamerTag, person.token, map[string]any{
			util.Fields.Record.Value: "NewTag",
		}).Expect().Status(http.StatusOK)
		if _, info = userinfo(t, baseURL, access); info["name"] != "NewTag" {
			t.Fatalf("userinfo name = %v", info["name"])
		}
		if v := read()["values"].(map[string]any)[services.SignInNameKey]; v != "NewTag" {
			t.Fatalf("grant value = %v", v)
		}

		api.Update(util.Coll.Links, g["id"].(string), person.token, map[string]any{
			util.Fields.Link.Status: util.StatusRevoked,
		}).Expect().Status(http.StatusOK)
		if _, info = userinfo(t, baseURL, access); info["name"] != nil {
			t.Fatalf("name after revoking = %v", info["name"])
		}
	})

	t.Run("giving another name stops the old entry being read", func(t *testing.T) {
		moved := newOIDCService(t, baseURL, "https://moved.example")
		tokens := signIn(moved, map[string]any{
			"approve": true, "scopes": []string{util.OIDCScopeProfile},
			"name": nameOf(services.NameFromRecord, gamerTag),
		})
		_, info := userinfo(t, baseURL, tokens["access_token"].(string))
		g := info[util.OIDCClaimLinks].(map[string]any)["grants"].([]any)[0].(map[string]any)

		signIn(moved, map[string]any{
			"approve": true, "scopes": []string{util.OIDCScopeProfile},
			"name": nameOf(services.NameFromIdentity, person.identityID),
		})
		read := api.E.POST("/api/grants/resolve").
			WithJSON(map[string]any{"grants": []map[string]any{{"id": g["id"], "token": g["token"]}}}).
			Expect().Status(http.StatusOK).JSON().Object().Value("items").Array().Value(0).Object().Raw()
		if read["status"] != util.StatusRevoked || read["values"] != nil {
			t.Fatalf("old grant = %v", read)
		}
	})

	t.Run("a name that is not the person's own is refused", func(t *testing.T) {
		other := newOIDCPerson(t, baseURL)
		foreign := extractID(t, baseURL, util.Coll.Records, other.token, map[string]any{
			util.Fields.Record.Key:       "theirs",
			util.Fields.Record.Value:     "Not yours",
			util.Fields.Record.Label:     "Theirs",
			util.Fields.Record.Type:      util.TypeText,
			util.Fields.Record.Format:    util.FormatDefault,
			util.Fields.Record.User:      other.userID,
			util.Fields.Record.Workspace: activeWorkspaceOf(t, api, other.userID, other.token),
		})
		hidden := entry("a_password", "hunter2", util.FormatHidden)
		for label, choice := range map[string]map[string]string{
			"another person's identity": nameOf(services.NameFromIdentity, other.identityID),
			"another person's entry":    nameOf(services.NameFromRecord, foreign),
			"a hidden entry":            nameOf(services.NameFromRecord, hidden),
			"an unknown kind":           nameOf("password", person.identityID),
		} {
			svc := newOIDCService(t, baseURL, "https://refused.example")
			_, consent := person.open(t, svc.params(map[string]string{"scope": "openid profile"}))
			status, out := person.decide(t, consent["ticket"].(string), map[string]any{
				"approve": true, "scopes": []string{util.OIDCScopeProfile}, "name": choice,
			})
			if status != http.StatusBadRequest || out["code"] != util.Errors.OIDCNameInvalid.ErrorCode {
				t.Fatalf("%s: %d %v", label, status, out)
			}
		}
	})

	t.Run("the consent screen offers names and remembers the choice", func(t *testing.T) {
		svc := newOIDCService(t, baseURL, "https://game.example")
		_, consent := person.open(t, svc.params(map[string]string{"scope": "openid profile"}))
		selected := consent["nameSelected"].(map[string]any)
		if selected["kind"] != services.NameFromRecord || selected["id"] != gamerTag {
			t.Fatalf("selected = %v", selected)
		}
		seen := map[string]bool{}
		for _, o := range consent["nameOptions"].([]any) {
			item := o.(map[string]any)
			seen[item["id"].(string)] = true
			if item["key"] == "a_password" {
				t.Fatalf("a hidden entry is offered: %v", item)
			}
		}
		if !seen[person.identityID] || !seen[gamerTag] {
			t.Fatalf("options = %v", consent["nameOptions"])
		}

		_, fresh := person.open(t, newOIDCService(t, baseURL, "https://new.example").params(map[string]string{"scope": "openid profile"}))
		if fresh["nameSelected"] != nil {
			t.Fatalf("a new service starts with %v", fresh["nameSelected"])
		}
	})

	t.Run("the person can read which name a service gets, and nobody else can", func(t *testing.T) {
		rows := api.E.GET("/api/collections/"+util.Coll.SignIns+"/records").
			WithQuery("expand", "nameRecord,nameIdentity").
			WithQuery("filter", util.Fields.SignIn.ClientId+"='https://game.example'").
			WithHeader("Authorization", person.token).
			Expect().Status(http.StatusOK).JSON().Object().Value("items").Array()
		rows.Length().IsEqual(1)
		rows.Value(0).Object().Value("expand").Object().Value("nameRecord").Object().
			Value(util.Fields.Record.Value).String().IsEqual("NewTag")

		other := newOIDCPerson(t, baseURL)
		api.E.GET("/api/collections/"+util.Coll.SignIns+"/records").
			WithHeader("Authorization", other.token).
			Expect().Status(http.StatusOK).JSON().Object().Value("items").Array().Length().IsEqual(0)
	})

	t.Run("the account has no name of its own", func(t *testing.T) {
		api.Update(util.Coll.Users, person.userID, person.token, map[string]any{"name": "Ada"}).
			Expect().Status(http.StatusOK).JSON().Object().NotContainsKey("name")
	})
}

func TestSignInSharesEntriesFromTheChosenWorkspace(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	person := newOIDCPerson(t, baseURL)
	first := activeWorkspaceOf(t, api, person.userID, person.token)
	f := util.Fields.Record
	saveEntry := func(workspace, key, value, format string) string {
		return extractID(t, baseURL, util.Coll.Records, person.token, map[string]any{
			f.Key: key, f.Value: value, f.Label: key, f.Type: util.TypeText, f.Format: format,
			f.User: person.userID, f.Workspace: workspace,
		})
	}
	claims := map[string]string{
		"scope":  "openid",
		"claims": `{"userinfo":{"revoked_links":{"values":["game_name"]}}}`,
	}
	game := newOIDCService(t, baseURL, "https://game.example")
	inVault := func(workspace, key string) *core.Record {
		rec, _ := app.FindFirstRecordByFilter(util.Coll.Records,
			f.Key+" = {:k} && "+f.User+" = {:u} && "+f.Workspace+" = {:w}",
			dbx.Params{"k": key, "u": person.userID, "w": workspace})
		return rec
	}
	option := func(consent map[string]any) map[string]any {
		return consent["links"].([]any)[0].(map[string]any)["options"].([]any)[0].(map[string]any)
	}

	tag := saveEntry(first, "gamer_tag", "xXAdaXx", util.FormatDefault)
	consent, _ := person.approve(t, game.params(claims), map[string]any{
		"approve": true, "links": map[string]string{"game_name": tag},
	})
	if option(consent)["type"] != util.TypeText {
		t.Fatalf("option = %v", option(consent))
	}

	t.Run("an entry under another key gets an alias under the one asked for", func(t *testing.T) {
		alias := inVault(first, "game_name")
		if alias == nil || alias.GetString(f.AliasOf) != tag || alias.GetString(f.Value) != "" {
			t.Fatalf("alias = %v", alias)
		}
	})

	t.Run("the alias is filed under the service, and the entry it uses is not", func(t *testing.T) {
		section, err := app.FindFirstRecordByFilter(util.Coll.Sections,
			util.Fields.Section.Key+" = 'signin_game_example' && "+util.Fields.Section.User+" = {:u}",
			dbx.Params{"u": person.userID})
		if err != nil {
			t.Fatal(err)
		}
		alias := inVault(first, "game_name")
		if got := section.GetStringSlice(util.Fields.Section.Records); len(got) != 1 || got[0] != alias.Id {
			t.Fatalf("records = %v", got)
		}
		if section.GetString(util.Fields.Section.Name) != "game.example" ||
			alias.GetString(f.RequestedBy) != "game.example" {
			t.Fatalf("section = %v, alias = %v", section, alias)
		}
		if rec := inVault(first, "gamer_tag"); rec.GetString(f.RequestedBy) != "" {
			t.Fatalf("the person's own entry was marked: %v", rec)
		}
	})

	t.Run("an entry saved for the sign-in joins the section", func(t *testing.T) {
		saved := saveEntry(first, "game_badge", "Gold", util.FormatDefault)
		person.approve(t, game.params(claims), map[string]any{
			"approve": true,
			"links":   map[string]string{"game_name": saved},
			"created": []string{saved},
		})
		section, err := app.FindFirstRecordByFilter(util.Coll.Sections,
			util.Fields.Section.Key+" = 'signin_game_example' && "+util.Fields.Section.User+" = {:u}",
			dbx.Params{"u": person.userID})
		if err != nil {
			t.Fatal(err)
		}
		if !slices.Contains(section.GetStringSlice(util.Fields.Section.Records), saved) {
			t.Fatalf("records = %v", section.GetStringSlice(util.Fields.Section.Records))
		}
	})

	t.Run("someone else's entry can't be filed", func(t *testing.T) {
		other := newOIDCPerson(t, baseURL)
		_, opened := other.open(t, game.params(claims))
		status, out := other.decide(t, opened["ticket"].(string), map[string]any{
			"approve": true, "created": []string{tag},
		})
		if status != http.StatusBadRequest {
			t.Fatalf("decide: %d %v", status, out)
		}
	})

	t.Run("the next sign-in offers the alias first, with its value", func(t *testing.T) {
		status, again := person.open(t, game.params(claims))
		if status != http.StatusOK {
			t.Fatalf("open: %d %v", status, again)
		}
		o := option(again)
		if o["key"] != "game_name" || o["preview"] != "xXAdaXx" {
			t.Fatalf("option = %v", o)
		}
		sections := again["sections"].([]any)
		if len(sections) != 1 || sections[0].(map[string]any)["key"] != "signin_game_example" ||
			sections[0].(map[string]any)["name"] != "game.example" {
			t.Fatalf("sections = %v", sections)
		}
	})

	t.Run("a name read from an entry adds no alias", func(t *testing.T) {
		service := newOIDCService(t, baseURL, "https://named.example")
		person.approve(t, service.params(map[string]string{"scope": "openid profile"}), map[string]any{
			"approve": true,
			"scopes":  []string{util.OIDCScopeProfile},
			"name":    map[string]string{"kind": services.NameFromRecord, "id": tag},
		})
		if rec := inVault(first, services.SignInNameKey); rec != nil {
			t.Fatalf("an alias took over the key %q: %v", services.SignInNameKey, rec)
		}
	})

	second := api.Create(util.Coll.Workspaces, person.token, map[string]any{
		"name": "Second", "slug": "second-" + uuid.New().String()[:8],
	}).Expect().Status(http.StatusOK).JSON().Object().Value("id").String().Raw()
	api.Update(util.Coll.Users, person.userID, person.token, map[string]any{
		util.Fields.User.ActiveWorkspace: second,
		util.Fields.User.ActiveRole:      util.RoleAdmin,
	}).Expect().Status(http.StatusOK)

	t.Run("the identity that signs can belong to another workspace", func(t *testing.T) {
		_, opened := person.open(t, game.params(claims))
		signers := opened["signers"].([]any)
		if len(signers) != 1 || signers[0] != person.identityID {
			t.Fatalf("signers = %v", signers)
		}
	})

	t.Run("an entry from the workspace left behind is refused", func(t *testing.T) {
		_, opened := person.open(t, game.params(claims))
		status, out := person.decide(t, opened["ticket"].(string), map[string]any{
			"approve": true, "links": map[string]string{"game_name": tag},
		})
		if status != http.StatusBadRequest {
			t.Fatalf("decide: %d %v", status, out)
		}
	})

	t.Run("each workspace shares through a link of its own", func(t *testing.T) {
		secondTag := saveEntry(second, "game_name", "AdaAtWork", util.FormatDefault)
		consent, _ := person.approve(t, game.params(claims), map[string]any{
			"approve": true, "links": map[string]string{"game_name": secondTag},
		})
		if option(consent)["id"] != secondTag {
			t.Fatalf("option = %v", option(consent))
		}
		for _, ws := range []string{first, second} {
			if _, err := app.FindFirstRecordByFilter(util.Coll.Links,
				util.Fields.Link.User+" = {:u} && "+util.Fields.Link.Workspace+" = {:w} && "+
					util.Fields.Link.SignInClient+" = {:c}",
				dbx.Params{"u": person.userID, "w": ws, "c": game.clientID}); err != nil {
				t.Fatalf("no link in workspace %s: %v", ws, err)
			}
		}
	})
}
