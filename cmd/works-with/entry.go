package main

import (
	"bytes"
	"fmt"
	"net/mail"
	"net/url"
	"regexp"
	"slices"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// Entry is one service in Works with Revoked, as reviewed in
// services/<slug>.yaml. Everything the app and the website show about a
// service comes from here; the service's own domain only proves control
// (see proof.go) and never supplies a word of it.
type Entry struct {
	Schema         int          `yaml:"schema" json:"-"`
	Slug           string       `yaml:"slug" json:"slug"`
	Origin         string       `yaml:"origin" json:"origin"`
	Name           string       `yaml:"name" json:"name"`
	Description    Localized    `yaml:"description" json:"description"`
	Operator       Operator     `yaml:"operator" json:"operator"`
	PrivacyPolicy  string       `yaml:"privacy_policy" json:"privacy_policy"`
	Website        string       `yaml:"website,omitempty" json:"website,omitempty"`
	Source         string       `yaml:"source,omitempty" json:"source,omitempty"`
	SelfHostable   bool         `yaml:"self_hostable" json:"self_hostable"`
	Servers        []string     `yaml:"servers,omitempty" json:"servers"`
	Languages      []string     `yaml:"languages" json:"languages"`
	Pricing        string       `yaml:"pricing" json:"pricing"`
	Categories     []string     `yaml:"categories" json:"categories"`
	Does           []string     `yaml:"does" json:"does"`
	Proposes       Proposes     `yaml:"proposes,omitempty" json:"proposes"`
	Permissions    []Permission `yaml:"permissions,omitempty" json:"permissions"`
	Stores         Localized    `yaml:"stores" json:"stores"`
	Maintainers    []string     `yaml:"maintainers" json:"-"`
	BuiltByRevoked bool         `yaml:"built_by_revoked,omitempty" json:"built_by_revoked"`
	Verified       bool         `yaml:"verified,omitempty" json:"verified"`
	Status         string       `yaml:"status,omitempty" json:"status"`
	Reviewed       string       `yaml:"reviewed" json:"reviewed"`
}

// Localized is a text in English and German; both are required.
type Localized struct {
	En string `yaml:"en" json:"en"`
	De string `yaml:"de" json:"de"`
}

type Operator struct {
	Name     string `yaml:"name" json:"name"`
	Imprint  string `yaml:"imprint,omitempty" json:"imprint,omitempty"`
	Security string `yaml:"security" json:"security"`
}

// Proposes names what a service proposes in the app, so a proposal asking for
// something else can be pointed out there.
type Proposes struct {
	Shares   *ProposedShares   `yaml:"shares,omitempty" json:"shares,omitempty"`
	Requests *ProposedRequests `yaml:"requests,omitempty" json:"requests,omitempty"`
}

type ProposedShares struct {
	Templates []string `yaml:"templates,omitempty" json:"templates"`
	Keys      []string `yaml:"keys" json:"keys"`
}

type ProposedRequests struct {
	Templates []string `yaml:"templates" json:"templates"`
}

// Permission is one switch a service may ask for when it connects, with the
// reason it gives.
type Permission struct {
	Key    string    `yaml:"key" json:"key"`
	Reason Localized `yaml:"reason" json:"reason"`
}

const schemaVersion = 1

var (
	slugPattern   = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$`)
	originPattern = regexp.MustCompile(`^https://[a-z0-9.-]+(:[0-9]{1,5})?$`)
	keyPattern    = regexp.MustCompile(`^[a-z][a-z0-9_]{0,63}$`)
	handlePattern = regexp.MustCompile(`^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$`)
	controlChars  = regexp.MustCompile(`[\x00-\x1F\x7F]`)
)

// The vocabularies an entry may use. The app knows the same words; a word
// outside them is a typo or a change the app has to learn first.
var (
	categories = []string{"health", "housing", "work", "finance", "games", "developer", "other"}
	doesKinds  = []string{"share", "collect", "prove", "sign_in", "connect"}
	languages  = []string{"en", "de"}
	pricings   = []string{"free", "paid", "freemium"}
	statuses   = []string{"listed", "unavailable"}

	// permissionKeys are the switches of the connect screen: the catalogue
	// keys of ConnectRequest.toolPermissions, plus the three flags a connect
	// link carries outside that list. revoke_links and receive_links are
	// offered to every tool, so they are described, never compared.
	permissionKeys = []string{
		"section", "read_vault", "revoke_links", "receive_links",
		"shares:read", "shares:manage", "requests:manage",
		"attestations:issue", "vault:read", "vault:write",
	}
)

const (
	maxName        = 40
	maxDescription = 280
	maxReason      = 120
	maxStores      = 200
	maxListed      = 64
)

// ParseEntry reads one entry strictly: unknown fields are refused, so a
// misspelt field fails the check instead of being silently dropped.
func ParseEntry(data []byte) (*Entry, error) {
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	var e Entry
	if err := dec.Decode(&e); err != nil {
		return nil, err
	}
	return &e, nil
}

// Validate returns every problem with the entry, empty when it is fine.
// [slug] is the file's name without .yaml, which the entry must repeat.
func (e *Entry) Validate(slug string, blocked *Blocklist) []string {
	var p []string
	add := func(format string, args ...any) { p = append(p, fmt.Sprintf(format, args...)) }

	if e.Schema != schemaVersion {
		add("schema must be %d", schemaVersion)
	}
	if !slugPattern.MatchString(e.Slug) {
		add("slug %q: lower-case letters, digits and dashes, 1–40 characters", e.Slug)
	}
	if e.Slug != slug {
		add("slug %q must match the file name %q", e.Slug, slug+".yaml")
	}
	if !originPattern.MatchString(e.Origin) {
		add("origin %q must be https://host[:port], lower-case, with no path", e.Origin)
	} else if blocked != nil {
		if host := hostOf(e.Origin); blocked.Blocks(host) {
			add("origin %q is on blocked-domains.txt", e.Origin)
		}
	}
	text(&p, "name", e.Name, maxName)
	localized(&p, "description", e.Description, maxDescription, true)
	localized(&p, "stores", e.Stores, maxStores, true)

	text(&p, "operator.name", e.Operator.Name, maxName*2)
	if e.Operator.Imprint != "" {
		httpsURL(&p, "operator.imprint", e.Operator.Imprint)
	}
	contact(&p, "operator.security", e.Operator.Security)
	httpsURL(&p, "privacy_policy", e.PrivacyPolicy)
	if e.Website != "" {
		httpsURL(&p, "website", e.Website)
		if !sameOrigin(e.Website, e.Origin) {
			add("website must be on the origin %s", e.Origin)
		}
	}
	if e.Source != "" {
		httpsURL(&p, "source", e.Source)
	}

	// Empty means every Revoked server; otherwise the only ones it works with.
	for _, s := range e.Servers {
		if !originPattern.MatchString(s) {
			add("servers: %q must be https://host[:port]", s)
		}
	}
	oneOf(&p, "languages", e.Languages, languages, true)
	if !slices.Contains(pricings, e.Pricing) {
		add("pricing must be one of %s", strings.Join(pricings, ", "))
	}
	oneOf(&p, "categories", e.Categories, categories, true)
	oneOf(&p, "does", e.Does, doesKinds, true)

	if s := e.Proposes.Shares; s != nil {
		keys(&p, "proposes.shares.keys", s.Keys, true)
		names(&p, "proposes.shares.templates", s.Templates)
		if !slices.Contains(e.Does, "share") {
			add("proposes.shares needs \"share\" in does")
		}
	}
	if r := e.Proposes.Requests; r != nil {
		names(&p, "proposes.requests.templates", r.Templates)
		if len(r.Templates) == 0 {
			add("proposes.requests.templates must name at least one template")
		}
		if !slices.Contains(e.Does, "collect") {
			add("proposes.requests needs \"collect\" in does")
		}
	}

	seen := map[string]bool{}
	for i, perm := range e.Permissions {
		field := fmt.Sprintf("permissions[%d]", i)
		if !slices.Contains(permissionKeys, perm.Key) {
			add("%s.key %q must be one of %s", field, perm.Key, strings.Join(permissionKeys, ", "))
		}
		if seen[perm.Key] {
			add("%s.key %q is listed twice", field, perm.Key)
		}
		seen[perm.Key] = true
		localized(&p, field+".reason", perm.Reason, maxReason, true)
	}
	if len(e.Permissions) > 0 && !slices.Contains(e.Does, "connect") {
		add("permissions need \"connect\" in does")
	}

	if len(e.Maintainers) == 0 {
		add("maintainers must name at least one GitHub account")
	}
	for _, m := range e.Maintainers {
		if !handlePattern.MatchString(m) {
			add("maintainers: %q is not a GitHub account name", m)
		}
	}
	if e.Status != "" && !slices.Contains(statuses, e.Status) {
		add("status must be one of %s", strings.Join(statuses, ", "))
	}
	if _, err := time.Parse(time.DateOnly, e.Reviewed); err != nil {
		add("reviewed must be a date like 2026-11-09")
	}
	return p
}

func text(p *[]string, field, s string, max int) {
	switch {
	case strings.TrimSpace(s) == "":
		*p = append(*p, field+" is required")
	case controlChars.MatchString(s):
		*p = append(*p, field+" must be a single line")
	case len([]rune(s)) > max:
		*p = append(*p, fmt.Sprintf("%s is longer than %d characters", field, max))
	case strings.TrimSpace(s) != s:
		*p = append(*p, field+" has leading or trailing spaces")
	}
}

func localized(p *[]string, field string, l Localized, max int, required bool) {
	if !required && l.En == "" && l.De == "" {
		return
	}
	text(p, field+".en", l.En, max)
	text(p, field+".de", l.De, max)
}

func httpsURL(p *[]string, field, raw string) {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.Host == "" || u.User != nil {
		*p = append(*p, fmt.Sprintf("%s %q must be an https:// address", field, raw))
	}
}

// contact is where security reports go: an https page or a mailto: address.
func contact(p *[]string, field, raw string) {
	if addr, ok := strings.CutPrefix(raw, "mailto:"); ok {
		if _, err := mail.ParseAddress(addr); err != nil || strings.ContainsAny(addr, "<> ") {
			*p = append(*p, fmt.Sprintf("%s %q is not a valid mailto: address", field, raw))
		}
		return
	}
	httpsURL(p, field, raw)
}

func oneOf(p *[]string, field string, got, allowed []string, required bool) {
	if required && len(got) == 0 {
		*p = append(*p, field+" must name at least one of "+strings.Join(allowed, ", "))
	}
	seen := map[string]bool{}
	for _, g := range got {
		if !slices.Contains(allowed, g) {
			*p = append(*p, fmt.Sprintf("%s: %q must be one of %s", field, g, strings.Join(allowed, ", ")))
		}
		if seen[g] {
			*p = append(*p, fmt.Sprintf("%s: %q is listed twice", field, g))
		}
		seen[g] = true
	}
}

func keys(p *[]string, field string, got []string, required bool) {
	if required && len(got) == 0 {
		*p = append(*p, field+" must name at least one record key")
	}
	if len(got) > maxListed {
		*p = append(*p, fmt.Sprintf("%s lists more than %d keys", field, maxListed))
	}
	for _, k := range got {
		if !keyPattern.MatchString(k) {
			*p = append(*p, fmt.Sprintf("%s: %q is not a record key", field, k))
		}
	}
}

func names(p *[]string, field string, got []string) {
	for i, n := range got {
		text(p, fmt.Sprintf("%s[%d]", field, i), n, maxName*2)
	}
}

func hostOf(origin string) string {
	u, err := url.Parse(origin)
	if err != nil {
		return ""
	}
	return u.Hostname()
}

func sameOrigin(raw, origin string) bool {
	u, err := url.Parse(raw)
	if err != nil {
		return false
	}
	return strings.ToLower(u.Scheme+"://"+u.Host) == origin
}
