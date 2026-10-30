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
// person decides in the app. The app names it by ticket and never sends the
// parameters back, so it cannot change what was asked.
type oidcAuthRequest struct {
	// The issuer the request was made to, which every answer to it names.
	issuer                                         string
	clientID, redirectURI, state, nonce, challenge string
	// The optional scopes asked for; openid is implied.
	scopes []string
	// The vault keys asked for as revoked_links.
	linkKeys []string
}

// oidcTicket is a request opened in the app of the person it is for, not yet
// decided.
type oidcTicket struct {
	req  oidcAuthRequest
	user string
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

// All three live in memory, like the passkey ceremonies: a restart costs a
// sign-in in progress and nothing else. There is no provider session to
// lose, since every sign-in is approved in the app.
var (
	oidcTickets passkeyVault[oidcTicket]
	oidcCodes   passkeyVault[oidcCode]
	oidcTokens  passkeyVault[oidcAccess]
)

// oidcConsentPrefix starts the message an approval is signed over. A
// challenge nonce never contains a colon, so a signature made for a
// challenge — even one a foreign server chose — never approves a sign-in.
const oidcConsentPrefix = "revoked-oidc-consent:"

// OIDCRoute makes this server an OpenID Connect provider, so a service signs
// people in with their Revoked account using an ordinary OIDC client library:
//
//	GET  /.well-known/openid-configuration
//	GET  /oidc/jwks
//	GET  /oidc/authorize                 the page: hands the request to the app
//	POST /oidc/authorize/app             app session + request -> consent data
//	POST /oidc/authorize/consent         app session + {ticket, approve, scopes, links, identityId, signature} -> {redirect}
//	POST /oidc/token                     authorization_code + PKCE -> id_token
//	GET  /oidc/userinfo                  Bearer access token -> claims
//
// A sign-in is approved in the Revoked app and nowhere else. The browser page
// only passes the request on to the app; the app opens it with its session,
// shows what the service asks for, and signs the person's approval with an
// identity key that never leaves the device. A session token alone, without
// the device, cannot approve anything.
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
			if !allowRequest(re, probeLimiter, "oidc") {
				return rateLimitedResponse(re)
			}
			return serveOIDCAuthorize(re, root)
		})

		e.Router.POST("/oidc/authorize/app", func(re *core.RequestEvent) error {
			return oidcAppRequest(app, re, root)
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

// oidcForwarded are the authorization request parameters the page passes on
// to the app. Anything else is dropped, as the app drops it too.
// revoked_return=background is for the app alone: the service waits for the
// answer on the page that asked, so the app hands it over without a browser.
var oidcForwarded = []string{
	"client_id", "redirect_uri", "response_type", "scope", "state", "nonce",
	"code_challenge", "code_challenge_method", "claims", "prompt", "revoked_return",
}

// errOIDCClient means a request whose service or redirect address did not
// check out: nothing may be sent back to it.
var errOIDCClient = errors.New("oidc: client not identified")

// checkOIDCRequest validates an authorization request made to issuer.
//
// Until the service's origin and redirect address check out, nothing is sent
// back to it: errOIDCClient says so, and the caller shows the error itself,
// never redirecting to an address nobody vouched for. After that, a refusal
// is returned as the redirect that tells the service, in the standard form.
func checkOIDCRequest(issuer string, q url.Values) (req *oidcAuthRequest, refusal string, err error) {
	clientID, ok := util.NormalizeOrigin(q.Get("client_id"))
	redirectURI := q.Get("redirect_uri")
	if !ok || !util.RedirectWithinOrigin(redirectURI, clientID) {
		return nil, "", errOIDCClient
	}
	state := q.Get("state")
	if len(state) > maxOIDCParamLength {
		state = ""
	}
	back := func(code, description string) (*oidcAuthRequest, string, error) {
		return nil, oidcRedirect(redirectURI, map[string]string{
			"error": code, "error_description": description, "state": state, "iss": issuer,
		}), nil
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
	// Every sign-in is approved by the person in the app; there is no session
	// here a silent request could be answered from.
	if slices.Contains(strings.Fields(q.Get("prompt")), "none") {
		return back("login_required", "Signing in needs the person's approval in the Revoked app.")
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
	return &oidcAuthRequest{
		issuer:      issuer,
		clientID:    clientID,
		redirectURI: redirectURI,
		state:       state,
		nonce:       q.Get("nonce"),
		challenge:   challenge,
		scopes:      optional,
		linkKeys:    linkKeys,
	}, "", nil
}

// serveOIDCAuthorize checks an authorization request and hands it to the
// Revoked app. Nothing is decided in the browser: the page only opens the
// app with the request, which the app then opens on the server it is signed
// into.
func serveOIDCAuthorize(re *core.RequestEvent, root *server.RootKey) error {
	q := re.Request.URL.Query()
	req, refusal, err := checkOIDCRequest(oidcIssuer(re, root), q)
	if err != nil {
		return renderOIDCPage(re, root, oidcPageData{Problem: "client"}, http.StatusBadRequest)
	}
	if refusal != "" {
		return re.Redirect(http.StatusFound, refusal)
	}
	forward := url.Values{}
	for _, k := range oidcForwarded {
		if v := q.Get(k); v != "" {
			forward.Set(k, v)
		}
	}
	// The app reads the service's origin as the server will.
	forward.Set("client_id", req.clientID)
	return renderOIDCPage(re, root, oidcPageData{
		Client:  req.clientID,
		AppLink: util.OIDCAppScheme + "?" + forward.Encode(),
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

// oidcAppRequest opens an authorization request in the app of the person
// it is for. The app is signed in, so its session names the person; what
// comes back is what the consent screen shows: the account, what each scope
// would reveal, and the person's entries for each key asked for.
//
// A request that cannot go on but names a service correctly is answered
// with the redirect that tells the service so, for the app to open.
func oidcAppRequest(app core.App, re *core.RequestEvent, root *server.RootKey) error {
	if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
	}
	if !allowRequest(re, passkeyLimiter, "oidc|"+re.Auth.Id) {
		return rateLimitedResponse(re)
	}
	var body struct {
		Params map[string]string `json:"params"`
	}
	if err := re.BindBody(&body); err != nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.OIDCRequestInvalid)
	}
	q := url.Values{}
	for _, k := range oidcForwarded {
		if v := body.Params[k]; v != "" {
			q.Set(k, v)
		}
	}
	req, refusal, err := checkOIDCRequest(oidcIssuer(re, root), q)
	if err != nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.OIDCRequestInvalid)
	}
	if refusal != "" {
		return re.JSON(http.StatusOK, map[string]any{"redirect": refusal})
	}
	user := re.Auth

	ticket := oidcTickets.put(&oidcTicket{req: *req, user: user.Id}, util.OIDCRequestTTL)

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
//
// Only the app the ticket was opened in can answer it, and an approval must
// be signed with one of the person's active identities: the key is held on
// the device, so a session token without the device approves nothing.
func oidcConsent(app core.App, re *core.RequestEvent) error {
	if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
		return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
	}
	var body struct {
		Ticket     string            `json:"ticket"`
		Approve    bool              `json:"approve"`
		Scopes     []string          `json:"scopes"`
		Links      map[string]string `json:"links"`
		IdentityID string            `json:"identityId"`
		Signature  string            `json:"signature"`
	}
	if err := re.BindBody(&body); err != nil {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.OIDCRequestInvalid)
	}
	t, ok := oidcTickets.take(body.Ticket)
	if !ok || t.user != re.Auth.Id {
		return appErrorResponse(re, http.StatusBadRequest, &util.Errors.OIDCRequestInvalid)
	}
	req := t.req
	if body.Approve {
		if appErr, status := verifyOIDCApproval(app, t.user, body.Ticket, body.IdentityID, body.Signature); appErr != nil {
			return appErrorResponse(re, status, appErr)
		}
	}
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
		authTime: time.Now(),
		grant:    grant,
	}, util.OIDCCodeTTL)
	app.Logger().Info("OIDC sign-in approved", "user", t.user, "client", req.clientID)

	return re.JSON(http.StatusOK, map[string]any{"redirect": oidcRedirect(req.redirectURI, map[string]string{
		"code": code, "state": req.state, "iss": req.issuer,
	})})
}

// verifyOIDCApproval checks that an approval of ticket was signed by one of
// user's active identities, over oidcConsentPrefix followed by the ticket.
func verifyOIDCApproval(app core.App, user, ticket, identityID, signature string) (*util.AppError, int) {
	if identityID == "" || signature == "" {
		return &util.Errors.IdentityRequired, http.StatusUnauthorized
	}
	f := util.Fields.Identity
	id, err := app.FindRecordById(util.Coll.Identities, identityID)
	if err != nil || id == nil || id.GetString(f.User) != user {
		return &util.Errors.IdentityNotOwned, http.StatusForbidden
	}
	if id.GetString(f.Status) != util.StatusActive {
		return &util.Errors.IdentityRevoked, http.StatusForbidden
	}
	key := id.GetString(f.Certificate)
	if key == "" {
		key = id.GetString(f.PublicKey)
	}
	if err := util.VerifySignature(key, oidcConsentPrefix+ticket, signature); err != nil {
		return &util.Errors.SignatureInvalid, http.StatusUnauthorized
	}
	return nil, 0
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
