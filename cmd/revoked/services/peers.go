package services

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/util"
)

// PeerFetchTimeout bounds one request to another server.
const PeerFetchTimeout = 8 * time.Second

// peerKeyCacheTTL caps how long a peer's verified root key is reused before
// the chain is walked again. The assertion's own expiry caps it further.
const peerKeyCacheTTL = time.Hour

// txtPinPattern matches the pinned root fingerprint in a `_revoked.<domain>` TXT record.
var txtPinPattern = regexp.MustCompile(`(?i)v=revoked1;\s*k=sha256/([0-9a-f]{64})`)

// ErrPeerNotPinned is returned when a domain publishes no `_revoked` TXT
// record, so no key it serves can be tied to it.
var ErrPeerNotPinned = errors.New("no _revoked TXT record")

// ErrPeerKeySpoofed is returned when what a domain serves contradicts its DNS
// pin or its own signature.
var ErrPeerKeySpoofed = errors.New("peer key does not match its DNS pin")

// LookupRevokedTXTPin resolves the pinned root fingerprint from the domain's
// _revoked TXT record. A genuinely absent record yields ("", nil); an error
// means the lookup itself failed.
func LookupRevokedTXTPin(domain string) (string, error) {
	host := server.TXTPrefix + "." + hostOnly(domain)
	records, err := net.LookupTXT(host)
	if err != nil {
		var dnsErr *net.DNSError
		if errors.As(err, &dnsErr) && dnsErr.IsNotFound {
			return "", nil
		}
		return "", err
	}
	for _, rec := range records {
		if m := txtPinPattern.FindStringSubmatch(rec); m != nil {
			return strings.ToLower(m[1]), nil
		}
	}
	return "", nil
}

// hostOnly drops a port, which DNS knows nothing about.
func hostOnly(domain string) string {
	if h, _, err := net.SplitHostPort(domain); err == nil {
		return h
	}
	return domain
}

// FetchServerAssertion fetches and decodes the peer's /api/server assertion.
//
// The domain is caller-supplied, so this is a server-side fetch of an
// attacker-chosen URL: through the SSRF-safe client, which refuses redirects
// and re-checks the resolved address at connect time.
func FetchServerAssertion(domain string) (server.Assertion, error) {
	base, _ := util.PeerBaseURL(domain)
	body, err := peerGet(base + "/api/server")
	if err != nil {
		return server.Assertion{}, err
	}
	var payload struct {
		Assertion server.Assertion `json:"assertion"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return server.Assertion{}, err
	}
	return payload.Assertion, nil
}

// FetchPeerIdentityStatus retrieves a peer's signed status answer about one
// identity, through the same SSRF-safe client.
func FetchPeerIdentityStatus(domain, fingerprint string) (server.IdentityStatusAssertion, error) {
	base, _ := util.PeerBaseURL(domain)
	body, err := peerGet(base + "/api/identities/" + url.PathEscape(fingerprint) + "/status")
	if err != nil {
		return server.IdentityStatusAssertion{}, err
	}
	var assertion server.IdentityStatusAssertion
	if err := json.Unmarshal(body, &assertion); err != nil {
		return server.IdentityStatusAssertion{}, err
	}
	return assertion, nil
}

// peerGet reads at most 1 MiB from a 200 answer.
func peerGet(target string) ([]byte, error) {
	resp, err := util.NewSafeCallbackClient(PeerFetchTimeout).Get(target)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	return io.ReadAll(io.LimitReader(resp.Body, 1<<20))
}

type cachedPeerKey struct {
	pubPEM  string
	expires time.Time
}

var peerKeys = struct {
	sync.Mutex
	m map[string]cachedPeerKey
}{m: map[string]cachedPeerKey{}}

// PeerRootKey returns a peer's root public key once it has been tied to the
// domain: DNS pin, served assertion, assertion signature, pin match. An
// overridden domain (see [util.PeerOverridesEnv]) skips the pin and keeps the
// rest. Verified keys are cached; a failure is not, so a peer that fixes its
// DNS is believed on the next attempt.
func PeerRootKey(domain string) (string, error) {
	now := time.Now()
	key := strings.ToLower(domain)

	peerKeys.Lock()
	if c, ok := peerKeys.m[key]; ok && now.Before(c.expires) {
		peerKeys.Unlock()
		return c.pubPEM, nil
	}
	peerKeys.Unlock()

	_, pinned := util.PeerBaseURL(key)
	pin := ""
	if pinned {
		p, err := LookupRevokedTXTPin(key)
		if err != nil {
			return "", err
		}
		if p == "" {
			return "", ErrPeerNotPinned
		}
		pin = p
	}

	assertion, err := FetchServerAssertion(key)
	if err != nil {
		return "", err
	}
	if err := server.VerifyAssertion(assertion, now); err != nil {
		return "", fmt.Errorf("%w: %v", ErrPeerKeySpoofed, err)
	}
	if !strings.EqualFold(assertion.Body.Domain, key) {
		return "", fmt.Errorf("%w: assertion is for %s", ErrPeerKeySpoofed, assertion.Body.Domain)
	}
	if pinned && strings.ToLower(assertion.Body.Fingerprint) != pin {
		return "", ErrPeerKeySpoofed
	}

	expires := now.Add(peerKeyCacheTTL)
	if exp := time.Unix(assertion.Body.ExpiresAt, 0); exp.Before(expires) {
		expires = exp
	}
	peerKeys.Lock()
	peerKeys.m[key] = cachedPeerKey{pubPEM: assertion.Body.PublicKey, expires: expires}
	peerKeys.Unlock()
	return assertion.Body.PublicKey, nil
}

// ForgetPeerRootKey drops a cached key, reporting whether there was one, so a
// signature that fails under it can be checked again under a fresh fetch.
func ForgetPeerRootKey(domain string) bool {
	key := strings.ToLower(domain)
	peerKeys.Lock()
	defer peerKeys.Unlock()
	_, ok := peerKeys.m[key]
	delete(peerKeys.m, key)
	return ok
}
