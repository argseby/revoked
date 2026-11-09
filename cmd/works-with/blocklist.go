package main

import (
	"regexp"
	"strings"
)

// Blocklist holds the rules of blocked-domains.txt, matched the way the app
// matches them (app/lib/core/config/server_blocklist.dart): `*` stands for any
// part of a single label, and a rule also covers every subdomain of what it
// matches. The official domain is never blocked.
type Blocklist struct {
	rules []*regexp.Regexp
}

const officialDomain = "revoked.link"

func ParseBlocklist(data string) *Blocklist {
	b := &Blocklist{}
	for _, raw := range strings.Split(data, "\n") {
		line := strings.ToLower(strings.TrimSpace(raw))
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.Split(line, "*")
		for i, p := range parts {
			parts[i] = regexp.QuoteMeta(p)
		}
		b.rules = append(b.rules, regexp.MustCompile("^"+strings.Join(parts, "[^.]*")+"$"))
	}
	return b
}

// Blocks reports whether [host], or any domain it is a subdomain of, matches
// a rule.
func (b *Blocklist) Blocks(host string) bool {
	h := strings.ToLower(strings.TrimSpace(host))
	if h == "" || h == officialDomain || strings.HasSuffix(h, "."+officialDomain) {
		return false
	}
	labels := strings.Split(h, ".")
	for i := range labels {
		candidate := strings.Join(labels[i:], ".")
		for _, r := range b.rules {
			if r.MatchString(candidate) {
				return true
			}
		}
	}
	return false
}
