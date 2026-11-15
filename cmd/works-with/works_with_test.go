package main

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const validEntry = `schema: 1
slug: example
origin: https://tool.example.org
name: Example
description:
  en: An example tool.
  de: Ein Beispielwerkzeug.
operator:
  name: Example GmbH
  imprint: https://tool.example.org/imprint
  security: mailto:security@example.org
privacy_policy: https://tool.example.org/privacy
website: https://tool.example.org/start
languages: [en, de]
pricing: paid
categories: [work]
does: [share, connect]
proposes:
  shares:
    keys: [full_name, iban]
permissions:
  - key: revoke_links
    reason:
      en: Removing an entry revokes its link.
      de: Ein entfernter Eintrag widerruft seinen Link.
stores:
  en: Nothing.
  de: Nichts.
maintainers: [example-dev]
reviewed: 2026-11-09
`

func parse(t *testing.T, yaml string) *Entry {
	t.Helper()
	e, err := ParseEntry([]byte(yaml))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	return e
}

func TestValidEntryPasses(t *testing.T) {
	e := parse(t, validEntry)
	if p := e.Validate("example", ParseBlocklist("")); len(p) != 0 {
		t.Fatalf("expected no problems, got %v", p)
	}
}

func TestUnknownFieldIsRefused(t *testing.T) {
	if _, err := ParseEntry([]byte(validEntry + "descriptoin: typo\n")); err == nil {
		t.Fatal("a misspelt field must fail the check, not be dropped")
	}
}

func TestValidationProblems(t *testing.T) {
	cases := []struct {
		name, from, to, want string
	}{
		{"slug differs from file", "slug: example", "slug: other", "must match the file name"},
		{"http origin", "origin: https://tool.example.org", "origin: http://tool.example.org", "origin"},
		{"origin with path", "origin: https://tool.example.org", "origin: https://tool.example.org/app", "origin"},
		{"upper-case origin", "origin: https://tool.example.org", "origin: https://Tool.example.org", "origin"},
		{"missing German", "  de: Ein Beispielwerkzeug.", "  de: \"\"", "description.de is required"},
		{"unknown category", "categories: [work]", "categories: [crypto]", "categories"},
		{"unknown permission", "  - key: revoke_links", "  - key: everything", "permissions[0].key"},
		{"website off origin", "website: https://tool.example.org/start", "website: https://elsewhere.example.org", "website must be on the origin"},
		{"permissions without connect", "does: [share, connect]", "does: [share]", "permissions need"},
		{"shares without share", "does: [share, connect]", "does: [connect]", "proposes.shares needs"},
		{"bad record key", "keys: [full_name, iban]", "keys: [Full Name]", "not a record key"},
		{"no maintainers", "maintainers: [example-dev]", "maintainers: []", "maintainers must name"},
		{"bad date", "reviewed: 2026-11-09", "reviewed: soon", "reviewed must be a date"},
		{"bad security contact", "security: mailto:security@example.org", "security: call us", "operator.security"},
		{"unknown status", "reviewed: 2026-11-09", "reviewed: 2026-11-09\nstatus: approved", "status must be"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if !strings.Contains(validEntry, c.from) {
				t.Fatalf("test setup: %q not in the valid entry", c.from)
			}
			e := parse(t, strings.Replace(validEntry, c.from, c.to, 1))
			problems := strings.Join(e.Validate("example", ParseBlocklist("")), "\n")
			if !strings.Contains(problems, c.want) {
				t.Fatalf("want a problem containing %q, got:\n%s", c.want, problems)
			}
		})
	}
}

func TestBlockedOriginIsRefused(t *testing.T) {
	e := parse(t, strings.Replace(validEntry, "https://tool.example.org", "https://login.revoked.app", -1))
	problems := strings.Join(e.Validate("example", ParseBlocklist("revoked.*\n")), "\n")
	if !strings.Contains(problems, "blocked-domains.txt") {
		t.Fatalf("want a blocklist problem, got:\n%s", problems)
	}
}

func TestBlocklistMatchesLikeTheApp(t *testing.T) {
	b := ParseBlocklist("# comment\nrevoked.*\nrevokd.*\n\nexact.example.com\n")
	cases := map[string]bool{
		"revoked.app":               true,
		"api.revoked.app":           true,
		"revoked.example.com":       false, // * covers one label only
		"revokd.io":                 true,
		"exact.example.com":         true,
		"a.exact.example.com":       true,
		"example.com":               false,
		"revoked.link":              false, // the official domain is never blocked
		"notfallkarte.revoked.link": false,
	}
	for host, want := range cases {
		if got := b.Blocks(host); got != want {
			t.Errorf("Blocks(%q) = %t, want %t", host, got, want)
		}
	}
}

func TestBuildIsDeterministicAndHasNoNulls(t *testing.T) {
	a := parse(t, validEntry)
	b := parse(t, strings.NewReplacer("slug: example", "slug: aaa", "name: Example", "name: Aaa", "https://tool.example.org", "https://aaa.example.org").Replace(validEntry))
	b.Permissions, b.Proposes = nil, Proposes{}
	first, err := Build([]*Entry{a, b}).Encode()
	if err != nil {
		t.Fatal(err)
	}
	second, _ := Build([]*Entry{b, a}).Encode()
	if !bytes.Equal(first, second) {
		t.Fatal("the same entries in another order must give the same catalog")
	}
	out := string(first)
	if strings.Contains(out, "null") {
		t.Fatalf("catalog must not contain null:\n%s", out)
	}
	if strings.Index(out, `"slug": "aaa"`) > strings.Index(out, `"slug": "example"`) {
		t.Fatal("entries must be sorted by name")
	}
	if strings.Contains(out, "maintainers") || strings.Contains(out, "example-dev") {
		t.Fatal("maintainers are for the repository only, not the catalog")
	}
	if !strings.Contains(out, `"status": "listed"`) {
		t.Fatal("status defaults to listed")
	}
}

func TestDuplicateOriginIsRefused(t *testing.T) {
	dir := t.TempDir()
	write := func(name, body string) {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("example.yaml", validEntry)
	write("copy.yaml", strings.Replace(validEntry, "slug: example", "slug: copy", 1))
	_, _, problems := LoadEntries(dir, ParseBlocklist(""))
	if !strings.Contains(strings.Join(problems, "\n"), "already listed") {
		t.Fatalf("want a duplicate-origin problem, got %v", problems)
	}
}

func TestProofState(t *testing.T) {
	e := parse(t, validEntry)
	no := false
	cases := []struct {
		name  string
		proof Proof
		want  ProofState
	}{
		{"matches", Proof{Listing: "example", Origin: "https://tool.example.org"}, ProofMatches},
		{"other slug", Proof{Listing: "other", Origin: "https://tool.example.org"}, ProofMissing},
		{"other origin", Proof{Listing: "example", Origin: "https://elsewhere.example.org"}, ProofMissing},
		{"opt out", Proof{Listing: "example", Origin: "https://tool.example.org", Listed: &no}, ProofOptOut},
	}
	for _, c := range cases {
		if got := c.proof.StateFor(e); got != c.want {
			t.Errorf("%s: got %s, want %s", c.name, got, c.want)
		}
	}
}

func TestProofFileTooLarge(t *testing.T) {
	big := `{"listing":"example","origin":"https://tool.example.org","pad":"` + strings.Repeat("x", maxProofBytes) + `"}`
	if _, err := ParseProof(strings.NewReader(big)); err == nil {
		t.Fatal("a proof file over 4 KiB must be refused")
	}
}

// The checker against a fake origin: what it reports for each combination
// of the entry's verified flag and the file the origin serves.
func TestCheckerFindings(t *testing.T) {
	proof := ""
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == ProofPath {
			if proof == "" {
				http.NotFound(w, r)
				return
			}
			_, _ = w.Write([]byte(proof))
			return
		}
		_, _ = w.Write([]byte("<html></html>"))
	}))
	defer srv.Close()

	e := parse(t, validEntry)
	e.Origin = srv.URL
	matching := `{"listing":"example","origin":"` + srv.URL + `"}`
	checker := &Checker{Client: srv.Client()}

	cases := []struct {
		name     string
		verified bool
		proof    string
		want     string
	}{
		{"unverified without file", false, "", ""},
		{"verified with file", true, matching, ""},
		{"file appears", false, matching, "can be set to verified: true"},
		{"file disappears", true, "", "change of hands"},
		{"file changed", true, `{"listing":"other","origin":"` + srv.URL + `"}`, "change of hands"},
		{"opt out", true, `{"listing":"example","origin":"` + srv.URL + `","listed":false}`, "opted out"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			e.Verified, proof = c.verified, c.proof
			f := checker.Check(context.Background(), e)
			if !f.Reachable {
				t.Fatal("the fake origin answers")
			}
			if c.want == "" && f.Problem != "" || c.want != "" && !strings.Contains(f.Problem, c.want) {
				t.Fatalf("problem = %q, want %q", f.Problem, c.want)
			}
		})
	}
}

func TestUnreachableOrigin(t *testing.T) {
	srv := httptest.NewTLSServer(http.NotFoundHandler())
	url := srv.URL
	client := srv.Client()
	srv.Close()

	e := parse(t, validEntry)
	e.Origin = url
	f := (&Checker{Client: client}).Check(context.Background(), e)
	if f.Reachable || !strings.Contains(f.Problem, "status: unavailable") {
		t.Fatalf("got reachable=%t problem=%q", f.Reachable, f.Problem)
	}
}

// The real entries in services/ are valid and the committed catalog is
// what they build to: the same check CI runs.
func TestRepositoryEntries(t *testing.T) {
	root := filepath.Join("..", "..")
	blocked, err := os.ReadFile(filepath.Join(root, "blocked-domains.txt"))
	if err != nil {
		t.Fatal(err)
	}
	entries, tools, problems := LoadEntries(filepath.Join(root, "services"), ParseBlocklist(string(blocked)))
	if len(problems) > 0 {
		t.Fatalf("problems in services/:\n%s", strings.Join(problems, "\n"))
	}
	if len(entries) == 0 {
		t.Fatal("services/ has no entries")
	}
	built, _ := Build(entries, tools...).Encode()
	current, err := os.ReadFile(filepath.Join(root, "app", "assets", "works_with", "catalog.json"))
	if err != nil || !bytes.Equal(built, current) {
		t.Fatal("app/assets/works_with/catalog.json is out of date: run go run ./cmd/works-with build")
	}
}

func TestRunCheckReportsStaleCatalog(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "example.yaml"), []byte(validEntry), 0o644); err != nil {
		t.Fatal(err)
	}
	block := filepath.Join(dir, "blocked.txt")
	_ = os.WriteFile(block, nil, 0o644)
	out := filepath.Join(dir, "catalog.json")
	args := []string{"-services", dir, "-blocklist", block, "-out", out}

	var stdout, stderr bytes.Buffer
	if code := run(append([]string{"check"}, args...), &stdout, &stderr); code != 1 {
		t.Fatalf("check without a catalog: exit %d, want 1", code)
	}
	if code := run(append([]string{"build"}, args...), &stdout, &stderr); code != 0 {
		t.Fatalf("build: exit %d: %s", code, stderr.String())
	}
	if code := run(append([]string{"check"}, args...), &stdout, &stderr); code != 0 {
		t.Fatalf("check after build: exit %d: %s", code, stderr.String())
	}
}

func TestBuiltByRevoked(t *testing.T) {
	outside := parse(t, validEntry+"built_by_revoked: true\n")
	if p := strings.Join(outside.Validate("example", ParseBlocklist("")), "\n"); !strings.Contains(p, "only for services on revoked.link") {
		t.Fatalf("built_by_revoked outside revoked.link must be refused, got:\n%s", p)
	}

	own := parse(t, strings.Replace(validEntry, "https://tool.example.org", "https://tool.revoked.link", -1)+"built_by_revoked: true\n")
	if p := own.Validate("example", ParseBlocklist("")); len(p) != 0 {
		t.Fatalf("expected no problems, got %v", p)
	}
	out, _ := Build([]*Entry{own}).Encode()
	if !strings.Contains(string(out), `"verified": true`) {
		t.Fatal("a service built by Revoked is verified in the catalog")
	}
}

const validTool = `schema: 1
kind: tool
slug: example-sdk
name: Example SDK
platform: npm
description:
  en: An example client.
  de: Ein Beispielclient.
install: npm install example-sdk
registry: https://www.npmjs.com/package/example-sdk
source: https://github.com/example/sdk
license: MIT
maintainers: [example-dev]
reviewed: 2026-11-15
`

func TestToolsLoadBesideServices(t *testing.T) {
	dir := t.TempDir()
	for name, body := range map[string]string{
		"example.yaml":     validEntry,
		"example-sdk.yaml": validTool,
	} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	entries, tools, problems := LoadEntries(dir, ParseBlocklist(""))
	if len(problems) > 0 {
		t.Fatalf("problems: %v", problems)
	}
	if len(entries) != 1 || len(tools) != 1 {
		t.Fatalf("got %d services and %d tools, want 1 and 1", len(entries), len(tools))
	}
	out, _ := Build(entries, tools...).Encode()
	if !strings.Contains(string(out), `"tools": [`) || !strings.Contains(string(out), `"does": []`) {
		t.Fatalf("tools belong in their own array with no nulls:\n%s", out)
	}
	if strings.Contains(string(out), "maintainers") || strings.Contains(string(out), `"kind"`) {
		t.Fatal("review-only fields stay out of the catalog")
	}
}

func TestToolValidation(t *testing.T) {
	if _, err := ParseTool([]byte(validTool + "orign: https://x.example\n")); err == nil {
		t.Fatal("an unknown field in a tool must be refused")
	}
	cases := map[string]string{
		"platform must be one of":                strings.Replace(validTool, "platform: npm", "platform: pip", 1),
		"license must be one of":                 strings.Replace(validTool, "license: MIT", "license: WTFPL", 1),
		`source "http://github.com/example/sdk"`: strings.Replace(validTool, "https://github.com/example/sdk", "http://github.com/example/sdk", 1),
		"built_by_revoked is only for tools":     validTool + "built_by_revoked: true\n",
		"must match the file name":               validTool,
	}
	for want, body := range cases {
		tool, err := ParseTool([]byte(body))
		if err != nil {
			t.Fatalf("parse: %v", err)
		}
		slug := "example-sdk"
		if want == "must match the file name" {
			slug = "other"
		}
		if p := strings.Join(tool.Validate(slug), "\n"); !strings.Contains(p, want) {
			t.Errorf("want a problem containing %q, got:\n%s", want, p)
		}
	}
	if p := parseTool(t, validTool).Validate("example-sdk"); len(p) != 0 {
		t.Fatalf("a valid tool has no problems, got %v", p)
	}
}

func TestServiceRefusesUnknownKind(t *testing.T) {
	e := parse(t, validEntry+"kind: plugin\n")
	if p := strings.Join(e.Validate("example", ParseBlocklist("")), "\n"); !strings.Contains(p, "kind must be") {
		t.Fatalf("an unknown kind must be refused, got:\n%s", p)
	}
}

func parseTool(t *testing.T, yaml string) *Tool {
	t.Helper()
	tool, err := ParseTool([]byte(yaml))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	return tool
}
