package util

import (
	"net/url"
	"os"
	"regexp"
	"strings"
)

// PeerOverridesEnv maps peer domains to the base URLs they are reached at,
// as "a.example=http://127.0.0.1:8091,b.example=http://127.0.0.1:8092".
//
// For development and closed networks, where two instances run without public
// DNS: a listed domain is reached at its URL instead of https://<domain>, and
// its root key is taken from that URL without the DNS pin. Listing a domain is
// the operator vouching for it, so production deployments leave this empty.
const PeerOverridesEnv = "PEER_OVERRIDES"

// peerDomainPattern accepts a lowercase hostname with an optional port: the
// shape DOMAIN takes on every instance.
var peerDomainPattern = regexp.MustCompile(
	`^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*(:[0-9]{1,5})?$`)

// peerOverrides parses PeerOverridesEnv on every call, so tests and a running
// operator see the same thing; the list is short and read rarely.
func peerOverrides() map[string]string {
	out := map[string]string{}
	for _, pair := range strings.Split(os.Getenv(PeerOverridesEnv), ",") {
		domain, base, ok := strings.Cut(strings.TrimSpace(pair), "=")
		if !ok {
			continue
		}
		domain = strings.ToLower(strings.TrimSpace(domain))
		base = strings.TrimRight(strings.TrimSpace(base), "/")
		if domain == "" || base == "" {
			continue
		}
		out[domain] = base
	}
	return out
}

// NormalizePeerDomain lowercases and checks a domain received from a peer or a
// caller, reporting false for anything that is not a bare host[:port].
func NormalizePeerDomain(raw string) (string, bool) {
	d := strings.ToLower(strings.TrimSpace(raw))
	if d == "" || len(d) > 255 || !peerDomainPattern.MatchString(d) {
		return "", false
	}
	return d, true
}

// PeerBaseURL returns where a peer domain is reached, and whether its root key
// must be checked against the DNS pin. An overridden domain is not pinned.
func PeerBaseURL(domain string) (base string, pinned bool) {
	if base, ok := peerOverrides()[strings.ToLower(domain)]; ok {
		return base, false
	}
	return "https://" + domain, true
}

// PeerDomainForOrigin maps the address a client fetched a request from back to
// the domain of the server behind it: an overridden URL to its domain, and any
// other https origin to its host. Plain http is refused outside the overrides,
// since nothing reached that way can be tied to a DNS pin.
func PeerDomainForOrigin(origin string) (domain, base string, ok bool) {
	u, err := url.Parse(strings.TrimSpace(origin))
	if err != nil || !u.IsAbs() || u.Host == "" {
		return "", "", false
	}
	base = strings.ToLower(u.Scheme) + "://" + strings.ToLower(u.Host)
	for d, b := range peerOverrides() {
		if strings.EqualFold(b, base) {
			return d, b, true
		}
	}
	if u.Scheme != "https" {
		return "", "", false
	}
	domain, ok = NormalizePeerDomain(u.Host)
	if !ok {
		return "", "", false
	}
	return domain, "https://" + domain, true
}
