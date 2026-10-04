package util

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"net"
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
	// OIDCRequestTTL is how long the consent page may stay open.
	OIDCRequestTTL = 10 * time.Minute
	// OIDCCodeTTL is how long an authorization code may wait to be redeemed:
	// a redirect and one request.
	OIDCCodeTTL = 2 * time.Minute
	// OIDCIDTokenTTL bounds an ID token. It proves a sign-in that just
	// happened; a service keeps its own session afterwards.
	OIDCIDTokenTTL = 10 * time.Minute
	// OIDCAccessTokenTTL bounds the token for the userinfo endpoint.
	OIDCAccessTokenTTL = time.Hour

	// OIDCPagePath is the authorization endpoint, which is also the page the
	// passkey ceremony and the consent screen run on.
	OIDCPagePath = "/oidc/authorize"
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

// PairwiseSubject derives the subject a person has at one service: stable for
// that service, and unrelated to the subject the same person has at any
// other, so services cannot match their users across each other.
func PairwiseSubject(secret []byte, userID, clientID string) string {
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(clientID))
	mac.Write([]byte{0})
	mac.Write([]byte(userID))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}
