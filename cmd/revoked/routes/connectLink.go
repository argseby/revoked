package routes

import (
	"net/url"
	"regexp"
	"slices"
	"strings"

	"revoked/util"
)

// connectLink is a connect request as the browser page shows it, read by the
// rules the app reads revoked://connect by (app/lib/core/models/tool_client.dart).
type connectLink struct {
	Client      string            `json:"client"`
	Name        string            `json:"name"`
	Redirect    string            `json:"redirect"`
	State       string            `json:"state"`
	Challenge   string            `json:"challenge"`
	Reasons     map[string]string `json:"reasons"`
	Vault       bool              `json:"vault"`
	Section     bool              `json:"section"`
	Permissions []string          `json:"permissions"`
}

var connectStatePattern = regexp.MustCompile(`^[A-Za-z0-9._~-]{1,128}$`)

const (
	connectMaxName   = 40
	connectMaxReason = 120
)

var connectReasonKeys = []string{"revoke", "links", "vault", "section", "permissions"}

var connectControlChars = regexp.MustCompile(`[\x00-\x1F\x7F]+`)

// parseConnectLink reads a connect request, or reports !ok when any part is
// invalid. A link naming poll is read too: in a browser the answer comes back
// in the same tab, through the return address, so the page never polls.
func parseConnectLink(q url.Values) (*connectLink, bool) {
	client, ok := util.NormalizeOrigin(q.Get("client"))
	if !ok {
		return nil, false
	}
	redirect := strings.TrimSpace(q.Get("redirect"))
	if !util.RedirectWithinOrigin(redirect, client) {
		return nil, false
	}
	challenge := q.Get("challenge")
	if !util.ValidPKCE(challenge) {
		return nil, false
	}
	state := q.Get("state")
	if !connectStatePattern.MatchString(state) {
		return nil, false
	}
	name := strings.Join(strings.Fields(connectControlChars.ReplaceAllString(q.Get("name"), " ")), " ")
	if len(name) > connectMaxName {
		return nil, false
	}
	if name == "" {
		if u, err := url.Parse(client); err == nil {
			name = u.Host
		}
	}
	reasons := map[string]string{}
	for _, k := range connectReasonKeys {
		r := strings.Join(strings.Fields(connectControlChars.ReplaceAllString(q.Get(k+"_reason"), " ")), " ")
		if len(r) > connectMaxReason {
			return nil, false
		}
		if r != "" {
			reasons[k] = r
		}
	}
	if v := q.Get("vault"); v != "" && v != "read" {
		return nil, false
	}
	if s := q.Get("section"); s != "" && s != "1" {
		return nil, false
	}
	if p := q.Get("poll"); p != "" {
		if _, ok := util.NormalizeOrigin(p); !ok {
			return nil, false
		}
	}
	permissions := []string{}
	for _, part := range strings.Split(q.Get("permissions"), ",") {
		key := strings.TrimSpace(part)
		if key == "" {
			continue
		}
		if !slices.Contains(util.ConnectionPermissions, key) {
			return nil, false
		}
		if !slices.Contains(permissions, key) {
			permissions = append(permissions, key)
		}
	}
	return &connectLink{
		Client: client, Name: name, Redirect: redirect, State: state, Challenge: challenge,
		Reasons: reasons, Vault: q.Get("vault") == "read", Section: q.Get("section") == "1",
		Permissions: permissions,
	}, true
}
