package routes

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/golang-jwt/jwt/v5"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// maxOIDCParamLength bounds state and nonce, which are echoed back verbatim.
const maxOIDCParamLength = 1024

// maxLinkOptions bounds how many entries the consent screen offers per key.
const maxLinkOptions = 500

// oidcAuthRequest is a validated authorization request, held while the
// person signs in and decides. The page never carries the parameters back:
// it names this by id, so it cannot change what was asked.
type oidcAuthRequest struct {
	// The issuer the request was made to, which every answer to it names.
	issuer                                         string
	clientID, redirectURI, state, nonce, challenge string
	// The optional scopes asked for; openid is implied.
	scopes []string
	// The vault keys asked for as revoked_links.
	linkKeys []string
}

// oidcTicket is a request whose person has signed in and not yet decided.
type oidcTicket struct {
	req      oidcAuthRequest
	user     string
	authTime time.Time
}

// oidcCode is a decision waiting for the service to redeem it.
type oidcCode struct {
	req      oidcAuthRequest
	user     string
	scopes   []string
	authTime time.Time
	grant    *services.SignInGrant
}

// oidcAccess is what an access token lets the service read at userinfo.
type oidcAccess struct {
	issuer         string
	user, clientID string
	scopes         []string
	grant          *services.SignInGrant
}

// All four live in memory, like the passkey ceremonies: a restart costs a
// sign-in in progress and nothing else. There is no provider session to
// lose, since every sign-in is confirmed with a passkey.
var (
	oidcRequests passkeyVault[oidcAuthRequest]
	oidcTickets  passkeyVault[oidcTicket]
	oidcCodes    passkeyVault[oidcCode]
	oidcTokens   passkeyVault[oidcAccess]
)

// OIDCRoute makes this server an OpenID Connect provider, so a service signs
// people in with their Revoked account using an ordinary OIDC client library:
//
//	GET  /.well-known/openid-configuration
//	GET  /oidc/jwks
//	GET  /oidc/authorize                 the page: passkey, then consent
//	POST /oidc/authorize/session         {request, code, verifier} -> consent data
//	POST /oidc/authorize/consent         {ticket, approve, scopes, links} -> {redirect}
//	POST /oidc/token                     authorization_code + PKCE -> id_token
//	GET  /oidc/userinfo                  Bearer access token -> claims
//
// A service is identified by its origin, as a connected tool is: client_id is
// the origin, redirect_uri must lie on it, and PKCE (S256) stands in for a
// client secret, so no registration is needed. Each service sees its own
// subject for a person. Vault entries a service asks for are given as grants
// it reads with a token, never as copies.
func OIDCRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/.well-known/openid-configuration", func(re *core.RequestEvent) error {
			issuer := oidcIssuer(re, root)
			return re.JSON(http.StatusOK, map[string]any{
				"issuer":                                issuer,
				"authorization_endpoint":                issuer + util.OIDCPagePath,
				"token_endpoint":                        issuer + "/oidc/token",
				"userinfo_endpoint":                     issuer + "/oidc/userinfo",
				"jwks_uri":                              issuer + "/oidc/jwks",
				"response_types_supported":              []string{"code"},
				"response_modes_supported":              []string{"query"},
				"grant_types_supported":                 []string{"authorization_code"},
				"subject_types_supported":               []string{"pairwise"},
				"id_token_signing_alg_values_supported": []string{"RS256"},
				"token_endpoint_auth_methods_supported": []string{"none"},
				"code_challenge_methods_supported":      []string{"S256"},
				"scopes_supported":                      append([]string{util.OIDCScopeOpenID}, util.OIDCOptionalScopes...),
				"claims_supported": []string{
					"sub", "iss", "aud", "exp", "iat", "auth_time", "nonce",
					"name", "email", "email_verified", util.OIDCScopeIdentity, util.OIDCClaimLinks,
				},
				"claims_parameter_supported":                     true,
				"request_parameter_supported":                    false,
				"request_uri_parameter_supported":                false,
				"authorization_response_iss_parameter_supported": true,
				"prompt_values_supported":                        []string{"none", "login", "consent"},
			})
		})

		e.Router.GET("/oidc/jwks", func(re *core.RequestEvent) error {
			keys, err := root.Issuer()
			if err != nil {
				return re.InternalServerError("Signing key unavailable", err)
			}
			re.Response.Header().Set("Cache-Control", "public, max-age=3600")
			return re.JSON(http.StatusOK, map[string]any{"keys": []server.JWK{keys.JWK()}})
		})

		// util.OIDCPagePath, spelled out so the route list reads as one.
		e.Router.GET("/oidc/authorize", func(re *core.RequestEvent) error {
			return serveOIDCAuthorize(re, root)
		})

		e.Router.POST("/oidc/authorize/session", func(re *core.RequestEvent) error {
			return oidcSession(app, re)
		})

		e.Router.POST("/oidc/authorize/consent", func(re *core.RequestEvent) error {
			return oidcConsent(app, re)
		})

		e.Router.POST("/oidc/token", func(re *core.RequestEvent) error {
			return oidcToken(app, re, root)
		})

		e.Router.GET("/oidc/userinfo", func(re *core.RequestEvent) error {
			return oidcUserinfo(app, re, root)
		})
		e.Router.POST("/oidc/userinfo", func(re *core.RequestEvent) error {
			return oidcUserinfo(app, re, root)
		})

		return e.Next()
	})
}

// oidcIssuer is the issuer a request is answered as: https://<domain>, or the
// address the request reached when that is the configured domain or this
// machine — as for the passkey page, a development server answers at
// localhost as well as at its domain. A client must see one issuer from
// discovery to token, so the issuer is fixed when a sign-in starts. Any other
// Host header falls back to the domain, so it cannot name a different issuer.
func oidcIssuer(re *core.RequestEvent, root *server.RootKey) string {
	return util.OIDCIssuer(pageOrigin(re, root))
}

// serveOIDCAuthorize validates an authorization request and renders the page
// it continues on.
//
// Until the service's origin and redirect address check out, nothing is sent
// back to it: an error is shown here, never redirected to an address nobody
// vouched for. After that, every refusal goes back to the service in the
// standard form.
func serveOIDCAuthorize(re *core.RequestEvent, root *server.RootKey) error {
	issuer := oidcIssuer(re, root)
	q := re.Request.URL.Query()
	clientID, ok := util.NormalizeOrigin(q.Get("client_id"))
	redirectURI := q.Get("redirect_uri")
	if !ok || !util.RedirectWithinOrigin(redirectURI, clientID) {
		return renderOIDCPage(re, root, oidcPageData{Problem: "client"}, http.StatusBadRequest)
	}
	state := q.Get("state")
	if len(state) > maxOIDCParamLength {
		state = ""
	}
	back := func(code, description string) error {
		return re.Redirect(http.StatusFound, oidcRedirect(redirectURI, map[string]string{
			"error": code, "error_description": description, "state": state, "iss": issuer,
		}))
	}

	if q.Get("response_type") != "code" {
		return back("unsupported_response_type", "Only the authorization code flow is supported.")
	}
	scopes := strings.Fields(q.Get("scope"))
	if !slices.Contains(scopes, util.OIDCScopeOpenID) {
		return back("invalid_scope", "The openid scope is required.")
	}
	if q.Get("request") != "" {
		return back("request_not_supported", "Request objects are not supported.")
	}
	if q.Get("request_uri") != "" {
		return back("request_uri_not_supported", "Request objects are not supported.")
	}
	if m := q.Get("response_mode"); m != "" && m != "query" {
		return back("invalid_request", "Only the query response mode is supported.")
	}
	challenge := q.Get("code_challenge")
	if !util.ValidPKCE(challenge) || q.Get("code_challenge_method") != "S256" {
		return back("invalid_request", "PKCE with the S256 method is required.")
	}
	if len(q.Get("state")) > maxOIDCParamLength || len(q.Get("nonce")) > maxOIDCParamLength {
		return back("invalid_request", "state or nonce is too long.")
	}
	// Every sign-in is confirmed with a passkey; there is no session here a
	// silent request could be answered from.
	if slices.Contains(strings.Fields(q.Get("prompt")), "none") {
		return back("login_required", "Signing in needs the person's passkey.")
	}
	linkKeys, err := parseLinkClaims(q.Get("claims"))
	if err != nil {
		return back("invalid_request", err.Error())
	}

	var optional []string
	for _, s := range util.OIDCOptionalScopes {
		if slices.Contains(scopes, s) {
			optional = append(optional, s)
		}
	}
	id := oidcRequests.put(&oidcAuthRequest{
		issuer:      issuer,
		clientID:    clientID,
		redirectURI: redirectURI,
		state:       state,
		nonce:       q.Get("nonce"),
		challenge:   challenge,
		scopes:      optional,
		linkKeys:    linkKeys,
	}, util.OIDCRequestTTL)

	return renderOIDCPage(re, root, oidcPageData{
		Request:  id,
		Client:   clientID,
		Scopes:   optional,
		LinkKeys: linkKeys,
	}, http.StatusOK)
}

// parseLinkClaims reads the vault keys a service asks for from the claims
// parameter: {"userinfo": {"revoked_links": {"values": ["email", ...]}}}. The
// id_token member is read too, for clients that put every claim there; the
// grants are delivered at userinfo either way.
func parseLinkClaims(raw string) ([]string, error) {
	if raw == "" {
		return nil, nil
	}
	var claims map[string]map[string]*struct {
		Values []string `json:"values"`
	}
	if err := json.Unmarshal([]byte(raw), &claims); err != nil {
		return nil, errors.New("The claims parameter is not valid JSON.")
	}
	var keys []string
	for _, member := range []string{"userinfo", "id_token"} {
		req := claims[member][util.OIDCClaimLinks]
		if req == nil {
			continue
		}
		for _, k := range req.Values {
			if !recordKeyPattern.MatchString(k) {
				return nil, errors.New("revoked_links names a key that is not a vault key.")
			}
			if !slices.Contains(keys, k) {
				keys = append(keys, k)
			}
		}
	}
	if len(keys) > util.OIDCMaxLinkKeys {
		return nil, errors.New("revoked_links asks for too many keys.")
	}
	return keys, nil
}

// oidcRedirect adds params to a redirect address, keeping its own query.
// Empty values are left out.
func oidcRedirect(redirectURI string, params map[string]string) string {
	u, err := url.Parse(redirectURI)
	if err != nil {
		return redirectURI
	}
	q := u.Query()
	for k, v := range params {
		if v != "" {
			q.Set(k, v)
		}
	}
	u.RawQuery = q.Encode()
	return u.String()
}

// oidcSession joins a finished passkey sign-in to the authorization request it
// was made for, and returns what the consent screen shows: the account, what
// each scope would reveal, and the person's entries for each key asked for.
func oidcSession(app core.App, re *core.RequestEvent) error {
	if !allowRequest(re, passkeyLimiter, "") {
		return rateLimitedResponse(re)
	}
	var body struct {
		Request  string `json:"request"`
		Code     string `json:"code"`
		Verifier string `json:"verifier"`
	}
	if err := re.BindBody(&body); err != nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.OIDCRequestInvalid)
	}
	req, ok := oidcRequests.take(body.Request)
	if !ok {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.OIDCRequestInvalid)
	}
	grant, ok := passkeyCodes.take(body.Code)
	if !ok || !util.ValidPKCE(body.Verifier) ||
		subtle.ConstantTimeCompare([]byte(util.PKCEChallenge(body.Verifier)), []byte(grant.pkce)) != 1 {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyGrantInvalid)
	}
	user, err := app.FindRecordById(util.Coll.Users, grant.user)
	if err != nil || user == nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyGrantInvalid)
	}

	ticket := oidcTickets.put(&oidcTicket{req: *req, user: user.Id, authTime: time.Now()}, util.OIDCRequestTTL)

	// What each scope would give away, shown before the person agrees to it.
	preview := services.OIDCClaims(app, user, req.clientID, nil, util.OIDCOptionalScopes)
	scopes := make([]map[string]any, 0, len(req.scopes))
	for _, s := range req.scopes {
		item := map[string]any{"scope": s}
		switch s {
		case util.OIDCScopeProfile:
			item["value"] = preview["name"]
		case util.OIDCScopeEmail:
			item["value"] = preview["email"]
		case util.OIDCScopeIdentity:
			if id := services.PrimaryIdentity(app, user.Id); id != nil {
				item["value"] = id.GetString(util.Fields.Identity.Name)
			}
		}
		scopes = append(scopes, item)
	}

	return re.JSON(http.StatusOK, map[string]any{
		"ticket":  ticket,
		"client":  req.clientID,
		"account": map[string]any{"email": user.Email()},
		"scopes":  scopes,
		"links":   linkOptions(app, user, req.linkKeys),
	})
}

// linkOptions lists, for each key a service asked for, the entries of the
// person's active workspace they could share under it, the ones whose key
// matches first. Hidden entries show no value.
func linkOptions(app core.App, user *core.Record, keys []string) []map[string]any {
	out := make([]map[string]any, 0, len(keys))
	if len(keys) == 0 {
		return out
	}
	f := util.Fields.Record
	records, _ := app.FindRecordsByFilter(util.Coll.Records,
		f.User+" = {:u} && "+f.Workspace+" = {:w}", f.Key, maxLinkOptions, 0,
		dbx.Params{"u": user.Id, "w": user.GetString(util.Fields.User.ActiveWorkspace)})
	for _, key := range keys {
		var matching, others []map[string]any
		for _, rec := range records {
			entry := map[string]any{
				"id":    rec.Id,
				"key":   rec.GetString(f.Key),
				"label": rec.GetString(f.Label),
			}
			if rec.GetString(f.Format) != util.FormatHidden && rec.GetString(f.Type) != util.TypeFile &&
				rec.GetString(f.AliasOf) == "" {
				entry["preview"] = truncateRunes(rec.GetString(f.Value), 60)
			}
			if rec.GetString(f.Key) == key {
				matching = append(matching, entry)
			} else {
				others = append(others, entry)
			}
		}
		out = append(out, map[string]any{"key": key, "options": append(matching, others...)})
	}
	return out
}

func truncateRunes(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "…"
}

// oidcConsent records the person's decision and sends them back to the
// service: with a code when they agreed, with access_denied when they did not.
func oidcConsent(app core.App, re *core.RequestEvent) error {
	var body struct {
		Ticket  string            `json:"ticket"`
		Approve bool              `json:"approve"`
		Scopes  []string          `json:"scopes"`
		Links   map[string]string `json:"links"`
	}
	if err := re.BindBody(&body); err != nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.OIDCRequestInvalid)
	}
	t, ok := oidcTickets.take(body.Ticket)
	if !ok {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.OIDCRequestInvalid)
	}
	req := t.req
	if !body.Approve {
		return re.JSON(http.StatusOK, map[string]any{"redirect": oidcRedirect(req.redirectURI, map[string]string{
			"error": "access_denied", "error_description": "The person declined.", "state": req.state, "iss": req.issuer,
		})})
	}

	// Only what was asked for can be granted, whatever the page sends.
	granted := []string{util.OIDCScopeOpenID}
	for _, s := range req.scopes {
		if slices.Contains(body.Scopes, s) {
			granted = append(granted, s)
		}
	}
	choices := map[string]string{}
	for _, key := range req.linkKeys {
		if id := body.Links[key]; id != "" {
			choices[key] = id
		}
	}

	var grant *services.SignInGrant
	if len(choices) > 0 {
		user, err := app.FindRecordById(util.Coll.Users, t.user)
		if err != nil || user == nil {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.OIDCRequestInvalid)
		}
		token, err := util.GenerateToken(32)
		if err != nil {
			return re.InternalServerError("Failed to share the entries", err)
		}
		link, err := services.SaveSignInGrant(app, user, req.clientID, choices, token)
		if errors.Is(err, services.ErrSignInRecord) {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.OIDCLinkRecordInvalid)
		}
		if err != nil {
			return re.InternalServerError("Failed to share the entries", err)
		}
		keys := make([]string, 0, len(choices))
		for _, k := range req.linkKeys {
			if _, ok := choices[k]; ok {
				keys = append(keys, k)
			}
		}
		grant = &services.SignInGrant{ID: link.Id, Token: token, Keys: keys}
	}

	code := oidcCodes.put(&oidcCode{
		req:      req,
		user:     t.user,
		scopes:   granted,
		authTime: t.authTime,
		grant:    grant,
	}, util.OIDCCodeTTL)
	app.Logger().Info("OIDC sign-in approved", "user", t.user, "client", req.clientID)

	return re.JSON(http.StatusOK, map[string]any{"redirect": oidcRedirect(req.redirectURI, map[string]string{
		"code": code, "state": req.state, "iss": req.issuer,
	})})
}

// oauthError writes an OAuth 2.0 error response.
func oauthError(re *core.RequestEvent, status int, code, description string) error {
	re.Response.Header().Set("Cache-Control", "no-store")
	return re.JSON(status, map[string]any{"error": code, "error_description": description})
}

// oidcToken redeems an authorization code for an ID token and an access
// token. A code is spent the moment it is presented, right or wrong.
func oidcToken(app core.App, re *core.RequestEvent, root *server.RootKey) error {
	if !allowRequest(re, grantPeerLimiter, "oidc") {
		return rateLimitedResponse(re)
	}
	if err := re.Request.ParseForm(); err != nil {
		return oauthError(re, http.StatusBadRequest, "invalid_request", "The body must be form-encoded.")
	}
	form := re.Request.PostForm
	if form.Get("grant_type") != "authorization_code" {
		return oauthError(re, http.StatusBadRequest, "unsupported_grant_type", "Only authorization_code is supported.")
	}
	c, ok := oidcCodes.take(form.Get("code"))
	invalid := func() error {
		return oauthError(re, http.StatusBadRequest, "invalid_grant", "The code is invalid, expired, or was issued to another client.")
	}
	if !ok {
		return invalid()
	}
	verifier := form.Get("code_verifier")
	if form.Get("client_id") != c.req.clientID ||
		form.Get("redirect_uri") != c.req.redirectURI ||
		!util.ValidPKCE(verifier) ||
		subtle.ConstantTimeCompare([]byte(util.PKCEChallenge(verifier)), []byte(c.req.challenge)) != 1 {
		return invalid()
	}
	user, err := app.FindRecordById(util.Coll.Users, c.user)
	if err != nil || user == nil {
		return invalid()
	}
	keys, err := root.Issuer()
	if err != nil {
		return oauthError(re, http.StatusInternalServerError, "server_error", "The signing key is unavailable.")
	}

	now := time.Now()
	claims := services.OIDCClaims(app, user, c.req.clientID, keys.SubjectSecret(), c.scopes)
	claims["iss"] = c.req.issuer
	claims["aud"] = c.req.clientID
	claims["iat"] = now.Unix()
	claims["exp"] = now.Add(util.OIDCIDTokenTTL).Unix()
	claims["auth_time"] = c.authTime.Unix()
	if c.req.nonce != "" {
		claims["nonce"] = c.req.nonce
	}
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims(claims))
	token.Header["kid"] = keys.Kid()
	idToken, err := token.SignedString(keys.PrivateKey())
	if err != nil {
		return oauthError(re, http.StatusInternalServerError, "server_error", "The ID token could not be signed.")
	}

	access := oidcTokens.put(&oidcAccess{
		issuer:   c.req.issuer,
		user:     c.user,
		clientID: c.req.clientID,
		scopes:   c.scopes,
		grant:    c.grant,
	}, util.OIDCAccessTokenTTL)

	re.Response.Header().Set("Cache-Control", "no-store")
	re.Response.Header().Set("Pragma", "no-cache")
	return re.JSON(http.StatusOK, map[string]any{
		"access_token": access,
		"token_type":   "Bearer",
		"expires_in":   int(util.OIDCAccessTokenTTL.Seconds()),
		"id_token":     idToken,
		"scope":        strings.Join(c.scopes, " "),
	})
}

// oidcUserinfo answers with the claims the access token was granted, and the
// grant over shared entries when there is one.
func oidcUserinfo(app core.App, re *core.RequestEvent, root *server.RootKey) error {
	if !allowRequest(re, grantPeerLimiter, "oidc") {
		return rateLimitedResponse(re)
	}
	token := ""
	if h := re.Request.Header.Get("Authorization"); len(h) > 7 && strings.EqualFold(h[:7], "bearer ") {
		token = strings.TrimSpace(h[7:])
	}
	a, ok := oidcTokens.peek(token)
	var user *core.Record
	if ok {
		user, _ = app.FindRecordById(util.Coll.Users, a.user)
	}
	if !ok || user == nil {
		re.Response.Header().Set("WWW-Authenticate", `Bearer error="invalid_token"`)
		return oauthError(re, http.StatusUnauthorized, "invalid_token", "The access token is invalid or expired.")
	}
	keys, err := root.Issuer()
	if err != nil {
		return oauthError(re, http.StatusInternalServerError, "server_error", "The issuer keys are unavailable.")
	}
	claims := services.OIDCClaims(app, user, a.clientID, keys.SubjectSecret(), a.scopes)
	if a.grant != nil {
		claims[util.OIDCClaimLinks] = map[string]any{
			"endpoint": a.issuer + "/api/grants/resolve",
			"grants":   []*services.SignInGrant{a.grant},
		}
	}
	re.Response.Header().Set("Cache-Control", "no-store")
	return re.JSON(http.StatusOK, claims)
}
