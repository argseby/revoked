package util

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"net"
	"strconv"
	"strings"
	"time"
)

// OpenID Connect scopes this provider understands. openid is required; the
// others each add claims the person may decline on the consent screen.
const (
	OIDCScopeOpenID   = "openid"
	OIDCScopeProfile  = "profile"
	OIDCScopeEmail    = "email"
	OIDCScopeIdentity = "revoked_identity"

	// OIDCClaimLinks is requested through the claims parameter, naming the
	// vault keys a service asks for. It is answered with grants, never values.
	OIDCClaimLinks = "revoked_links"

	// OIDCMaxLinkKeys bounds how many vault keys one sign-in may ask for.
	OIDCMaxLinkKeys = 20
)

// OIDCOptionalScopes are the scopes beyond openid, in the order the consent
// screen lists them.
var OIDCOptionalScopes = []string{OIDCScopeProfile, OIDCScopeEmail, OIDCScopeIdentity}

const (
	// OIDCRequestTTL is how long the consent screen in the app may stay open.
	OIDCRequestTTL = 10 * time.Minute
	// OIDCCodeTTL is how long an authorization code may wait to be redeemed:
	// a redirect and one request.
	OIDCCodeTTL = 2 * time.Minute
	// OIDCIDTokenTTL bounds an ID token. It proves a sign-in that just
	// happened; a service keeps its own session afterwards.
	OIDCIDTokenTTL = 10 * time.Minute
	// OIDCAccessTokenTTL bounds the token for the userinfo endpoint.
	OIDCAccessTokenTTL = time.Hour

	// OIDCPagePath is the authorization endpoint: a page that hands the
	// request to the Revoked app, where the person decides.
	OIDCPagePath = "/oidc/authorize"

	// OIDCAppScheme is the link the authorization page opens the app with,
	// followed by the request's parameters.
	OIDCAppScheme = "revoked://signin"
)

// OIDCIssuer is the issuer identifier for a domain: https, except on the
// local machine, where development servers answer over plain http.
func OIDCIssuer(domain string) string {
	host := domain
	if h, _, err := net.SplitHostPort(domain); err == nil {
		host = h
	}
	host = strings.Trim(strings.ToLower(host), "[]")
	if host == "localhost" {
		return "http://" + domain
	}
	if ip := net.ParseIP(host); ip != nil && ip.IsLoopback() {
		return "http://" + domain
	}
	return "https://" + domain
}

// PairwiseSubject derives the subject a person has at one service from one
// workspace: stable for that service and workspace, and unrelated to the
// subject the same person has at any other service or from any other of their
// workspaces, so neither services nor one workspace's accounts can be matched
// to another's. A higher version is a new subject, unrelated to the earlier
// ones.
func PairwiseSubject(secret []byte, userID, workspaceID, clientID string, version int) string {
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(clientID))
	mac.Write([]byte{0})
	mac.Write([]byte(userID))
	mac.Write([]byte{0})
	mac.Write([]byte(workspaceID))
	if version > 0 {
		mac.Write([]byte{0})
		mac.Write([]byte(strconv.Itoa(version)))
	}
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}
