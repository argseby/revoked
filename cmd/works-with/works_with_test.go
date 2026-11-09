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
	_, problems := LoadEntries(dir, ParseBlocklist(""))
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
	entries, problems := LoadEntries(filepath.Join(root, "services"), ParseBlocklist(string(blocked)))
	if len(problems) > 0 {
		t.Fatalf("problems in services/:\n%s", strings.Join(problems, "\n"))
	}
	if len(entries) == 0 {
		t.Fatal("services/ has no entries")
	}
	built, _ := Build(entries).Encode()
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
