package tests

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
	"unicode"

	"gopkg.in/yaml.v3"
)

// Nothing generates the OpenAPI document from the source: PocketBase emits no
// spec and the custom handlers carry no annotations, so it is hand-written and
// would drift silently the first time someone adds a route. This is the guard.
//
// It compares registered paths against documented ones. Both directions matter:
// an undocumented route is a gap, and a documented route that no longer exists
// sends integrators at something that will 404.
func TestOpenAPICoversEveryCustomRoute(t *testing.T) {
	registered := registeredRoutes(t)
	documented := documentedPaths(t)

	// Deliberately undocumented. Each needs a reason, not just an entry.
	skip := map[string]string{
		// One DAV collection is documented; the file route underneath it is an
		// implementation detail of that collection, not a separate endpoint.
		"/dav/s/{slug}/{file...}": "covered by the DAV collection entry",
	}

	var missing []string
	for _, route := range registered {
		if _, ok := skip[route]; ok {
			continue
		}
		if !documented[normalizePath(route)] {
			missing = append(missing, route)
		}
	}
	if len(missing) > 0 {
		sort.Strings(missing)
		t.Errorf("registered but absent from docs/api/openapi.yaml:\n  %s",
			strings.Join(missing, "\n  "))
	}

	// The reverse: the spec also carries PocketBase's own collection endpoints,
	// which are not registered here, so only custom-looking paths are checked.
	pocketBase := map[string]bool{"/api/health": true}
	registeredSet := map[string]bool{}
	for _, r := range registered {
		registeredSet[normalizePath(r)] = true
	}
	var stale []string
	for path := range documented {
		if strings.HasPrefix(path, "/api/collections/") || strings.HasPrefix(path, "/api/files/") || pocketBase[path] {
			continue
		}
		if !registeredSet[path] {
			stale = append(stale, path)
		}
	}
	if len(stale) > 0 {
		sort.Strings(stale)
		t.Errorf("documented but no longer registered:\n  %s", strings.Join(stale, "\n  "))
	}
}

// A trailing slash is a routing detail, not a different endpoint.
func normalizePath(p string) string {
	if len(p) > 1 && strings.HasSuffix(p, "/") {
		return strings.TrimSuffix(p, "/")
	}
	return p
}

var routePattern = regexp.MustCompile(`e\.Router\.(?:GET|POST|PATCH|PUT|DELETE|HEAD|OPTIONS|Any)\("([^"]+)"`)

var registrarPattern = regexp.MustCompile(`(?m)^func (\w+)\(`)

// registeredRoutes returns the routes that are actually reachable: those
// declared inside a registrar bootstrap binds, or inside an unexported helper
// such a registrar calls. A registrar nobody calls registers nothing, and
// counting its routes would have this test demand documentation for endpoints
// that answer 404.
func registeredRoutes(t *testing.T) []string {
	t.Helper()
	bootstrap, err := os.ReadFile(filepath.Join("..", "cmd", "revoked", "bootstrap", "bootstrap.go"))
	if err != nil {
		t.Fatalf("reading bootstrap: %v", err)
	}
	bound := string(bootstrap)

	dir := filepath.Join("..", "cmd", "revoked", "routes")
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("reading routes: %v", err)
	}

	// Registrars known to be unreachable, each with the reason. A new name
	// appearing here should be wired up or deleted, not added to this list.
	knownUnbound := map[string]string{
		// Duplicates handlers that publicShort.go, publicLinks.go and
		// publicFiles.go serve live. Its rendering helpers are still used by
		// publicShort.go, so the file itself is not dead — only this entry
		// point and the three handlers under it.
		"publicPage.go: BindPublicLinkRoutes": "superseded; pending delete-or-wire decision",
	}

	type registrar struct {
		file, name, body string
		routes           [][]string
	}
	var funcs []registrar
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".go") || strings.HasSuffix(entry.Name(), "_test.go") {
			continue
		}
		raw, err := os.ReadFile(filepath.Join(dir, entry.Name()))
		if err != nil {
			t.Fatalf("reading %s: %v", entry.Name(), err)
		}
		source := string(raw)

		starts := registrarPattern.FindAllStringSubmatchIndex(source, -1)
		for i, loc := range starts {
			end := len(source)
			if i+1 < len(starts) {
				end = starts[i+1][0]
			}
			body := source[loc[0]:end]
			funcs = append(funcs, registrar{
				file:   entry.Name(),
				name:   source[loc[2]:loc[3]],
				body:   body,
				routes: routePattern.FindAllStringSubmatch(body, -1),
			})
		}
	}

	reached := map[string]bool{}
	for _, f := range funcs {
		if strings.Contains(bound, "routes."+f.name+"(") {
			reached[f.name] = true
		}
	}
	for changed := true; changed; {
		changed = false
		for _, f := range funcs {
			if reached[f.name] || unicode.IsUpper(rune(f.name[0])) {
				continue
			}
			call := regexp.MustCompile(`\b` + regexp.QuoteMeta(f.name) + `\(`)
			for _, caller := range funcs {
				if reached[caller.name] && caller.name != f.name && call.MatchString(caller.body) {
					reached[f.name] = true
					changed = true
					break
				}
			}
		}
	}

	seen := map[string]bool{}
	var out []string
	var unbound []string
	for _, f := range funcs {
		if len(f.routes) == 0 {
			continue
		}
		if !reached[f.name] {
			if _, known := knownUnbound[f.file+": "+f.name]; !known {
				unbound = append(unbound, f.file+": "+f.name)
			}
			continue
		}
		for _, match := range f.routes {
			if !seen[match[1]] {
				seen[match[1]] = true
				out = append(out, match[1])
			}
		}
	}

	if len(unbound) > 0 {
		sort.Strings(unbound)
		t.Errorf("these register routes but bootstrap never calls them, so the routes do not exist:\n  %s",
			strings.Join(unbound, "\n  "))
	}
	if len(out) == 0 {
		t.Fatal("found no registered routes — the scan pattern is probably stale")
	}
	return out
}

func documentedPaths(t *testing.T) map[string]bool {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("..", "docs", "api", "openapi.yaml"))
	if err != nil {
		t.Fatalf("reading the spec: %v", err)
	}
	var spec struct {
		Paths map[string]any `yaml:"paths"`
	}
	if err := yaml.Unmarshal(raw, &spec); err != nil {
		t.Fatalf("parsing the spec: %v", err)
	}
	out := map[string]bool{}
	for path := range spec.Paths {
		out[normalizePath(path)] = true
	}
	return out
}
