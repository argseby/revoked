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
	"strings"
	"testing"

	"revoked/cmd/revoked/server"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/golang-jwt/jwt/v5"
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

// authorize opens the authorization endpoint the way a browser sent there by
// the service does, overlaying extra on the standard parameters.
func (s *oidcService) authorize(extra map[string]string) *http.Response {
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
	resp, err := s.http.Get(s.baseURL + util.OIDCPagePath + "?" + q.Encode())
	if err != nil {
		s.t.Fatal(err)
	}
	return resp
}

var pageRequestID = regexp.MustCompile(`request: "([A-Za-z0-9]+)"`)

// requestID reads the stored request's id off the rendered page.
func requestID(t *testing.T, resp *http.Response) string {
	t.Helper()
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("authorize page: %d %s", resp.StatusCode, raw)
	}
	m := pageRequestID.FindSubmatch(raw)
	if m == nil {
		t.Fatalf("no request id on the page")
	}
	return string(m[1])
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

// signInAndConsent runs the page's part: a passkey sign-in joined to the
// request, then the decision. It returns the consent data and the redirect.
func signInAndConsent(t *testing.T, device *testutils.PasskeyDevice, request string, decision map[string]any) (map[string]any, string) {
	t.Helper()
	verifier, challenge := testutils.PKCEPair()
	code, err := device.SignInCode(challenge)
	if err != nil {
		t.Fatalf("passkey sign-in: %v", err)
	}
	var consent map[string]any
	if err := device.Post("/oidc/authorize/session",
		map[string]any{"request": request, "code": code, "verifier": verifier}, &consent); err != nil {
		t.Fatalf("session: %v", err)
	}
	body := map[string]any{"ticket": consent["ticket"]}
	for k, v := range decision {
		body[k] = v
	}
	var out struct {
		Redirect string `json:"redirect"`
	}
	if err := device.Post("/oidc/authorize/consent", body, &out); err != nil {
		t.Fatalf("consent: %v", err)
	}
	return consent, out.Redirect
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
	userID, token, device, err := testutils.CreateRandomUserWithDevice(baseURL)
	if err != nil {
		t.Fatal(err)
	}
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
	request := requestID(t, game.authorize(map[string]string{
		"claims": `{"userinfo":{"revoked_links":{"values":["shipping_address"]}}}`,
	}))
	consent, location := signInAndConsent(t, device, request, map[string]any{
		"approve": true,
		// The person keeps their identity to themselves.
		"scopes": []string{util.OIDCScopeProfile, util.OIDCScopeEmail},
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
		_, loc := signInAndConsent(t, device, requestID(t, again.authorize(nil)), map[string]any{"approve": true})
		_, tk := again.redeem(redirectParams(t, loc).Get("code"))
		if verifyIDToken(t, baseURL, tk["id_token"].(string))["sub"] != sub {
			t.Fatal("subject changed between sign-ins at one service")
		}

		other := newOIDCService(t, baseURL, "https://shop.example")
		_, loc = signInAndConsent(t, device, requestID(t, other.authorize(nil)), map[string]any{"approve": true})
		_, tk = other.redeem(redirectParams(t, loc).Get("code"))
		if verifyIDToken(t, baseURL, tk["id_token"].(string))["sub"] == sub {
			t.Fatal("two services see the same subject for one person")
		}
	})

	t.Run("declining sends the person back with access_denied", func(t *testing.T) {
		svc := newOIDCService(t, baseURL, game.clientID)
		_, loc := signInAndConsent(t, device, requestID(t, svc.authorize(nil)), map[string]any{"approve": false})
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
		request := requestID(t, svc.authorize(map[string]string{
			"claims": `{"userinfo":{"revoked_links":{"values":["shipping_address"]}}}`,
		}))
		verifier, challenge := testutils.PKCEPair()
		code, err := device.SignInCode(challenge)
		if err != nil {
			t.Fatal(err)
		}
		var consent map[string]any
		if err := device.Post("/oidc/authorize/session",
			map[string]any{"request": request, "code": code, "verifier": verifier}, &consent); err != nil {
			t.Fatal(err)
		}
		err = device.Post("/oidc/authorize/consent", map[string]any{
			"ticket": consent["ticket"], "approve": true,
			"links": map[string]string{"shipping_address": foreign},
		}, nil)
		if perr, ok := err.(*testutils.PasskeyError); !ok || perr.Code != util.Errors.OIDCLinkRecordInvalid.ErrorCode {
			t.Fatalf("err = %v", err)
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
		_, _, device, err := testutils.CreateRandomUserWithDevice(baseURL)
		if err != nil {
			t.Fatal(err)
		}
		_, loc := signInAndConsent(t, device, requestID(t, svc.authorize(nil)), map[string]any{"approve": true})
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
		_, _, device, err := testutils.CreateRandomUserWithDevice(baseURL)
		if err != nil {
			t.Fatal(err)
		}
		request := requestID(t, svc.authorize(nil))
		signInAndConsent(t, device, request, map[string]any{"approve": true})
		verifier, challenge := testutils.PKCEPair()
		code, err := device.SignInCode(challenge)
		if err != nil {
			t.Fatal(err)
		}
		err = device.Post("/oidc/authorize/session", map[string]any{"request": request, "code": code, "verifier": verifier}, nil)
		if perr, ok := err.(*testutils.PasskeyError); !ok || perr.Code != util.Errors.OIDCRequestInvalid.ErrorCode {
			t.Fatalf("err = %v", err)
		}
	})
}
