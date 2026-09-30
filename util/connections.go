package util

import (
	"crypto/sha256"
	"encoding/base64"
	"net/url"
	"regexp"
	"strings"
	"time"
)

const (
	// ConnectionTTL is how long a connection lasts after the owner last agreed
	// to it. Connecting the tool again from the app renews it; nothing the tool
	// does on its own can: a browser let in without asking leaves it as it is.
	ConnectionTTL = 90 * 24 * time.Hour

	// ConnectionCodeTTL is how long the one-time code the app hands a tool
	// may wait to be exchanged: a redirect and one request.
	ConnectionCodeTTL = 5 * time.Minute

	// ConnectionHeader carries a tool's bearer token. Not Authorization, which
	// PocketBase reads as a session token of its own.
	ConnectionHeader = "X-Revoked-Connection"

	// ConnectionOriginPattern is what a tool's identity may look like: an https
	// origin, or plain http on the local machine for development.
	ConnectionOriginPattern = `^(https://[a-z0-9.-]+|http://(localhost|127\.0\.0\.1))(:[0-9]{1,5})?$`
)

var (
	connectionOrigin = regexp.MustCompile(ConnectionOriginPattern)
	// RFC 7636: 43–128 characters of the unreserved set; S256 output is 43.
	pkceValue = regexp.MustCompile(`^[A-Za-z0-9._~-]{43,128}$`)
)

// ConnectionExpired reports whether a connection that expires at the given
// time has lapsed. A connection without an expiry never has.
func ConnectionExpired(expiresAt time.Time) bool {
	return !expiresAt.IsZero() && !expiresAt.After(time.Now())
}

// NormalizeOrigin reduces a tool's claimed identity to scheme://host[:port],
// lower-cased, or reports that it is not one: no path, query, fragment or
// credentials may ride along.
func NormalizeOrigin(raw string) (string, bool) {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || u.User != nil || u.Host == "" {
		return "", false
	}
	if (u.Path != "" && u.Path != "/") || u.RawQuery != "" || u.Fragment != "" {
		return "", false
	}
	origin := strings.ToLower(u.Scheme + "://" + u.Host)
	if !connectionOrigin.MatchString(origin) {
		return "", false
	}
	return origin, true
}

// RedirectWithinOrigin reports whether redirect is an absolute URL on exactly
// the given origin — the only place a code for that tool may be delivered.
func RedirectWithinOrigin(redirect, origin string) bool {
	u, err := url.Parse(strings.TrimSpace(redirect))
	if err != nil || u.User != nil || u.Host == "" || u.Fragment != "" {
		return false
	}
	return strings.ToLower(u.Scheme+"://"+u.Host) == origin
}

// ValidPKCE reports whether s is a well-formed PKCE verifier or S256 challenge.
func ValidPKCE(s string) bool {
	return pkceValue.MatchString(s)
}

// PKCEChallenge derives the S256 challenge of a verifier.
func PKCEChallenge(verifier string) string {
	sum := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}
