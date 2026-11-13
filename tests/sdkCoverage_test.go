package tests

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

// The JavaScript SDK claims to cover every operation an integration can call.
// Its manifest maps each operation in the spec to the SDK method that calls it,
// or excludes it with a reason; a new route that is neither fails here, and the
// SDK's own test fails on a mapping that names no method.
func TestJavaScriptSDKCoversEveryOperation(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "packages", "revoked-js", "coverage.json"))
	if err != nil {
		t.Fatal(err)
	}
	var manifest struct {
		Operations map[string]json.RawMessage `json:"operations"`
	}
	if err := json.Unmarshal(raw, &manifest); err != nil {
		t.Fatal(err)
	}

	specRaw, err := os.ReadFile(filepath.Join("..", "docs", "api", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	var spec struct {
		Paths map[string]map[string]any `yaml:"paths"`
	}
	if err := yaml.Unmarshal(specRaw, &spec); err != nil {
		t.Fatal(err)
	}

	documented := map[string]bool{}
	for path, item := range spec.Paths {
		for method := range item {
			switch method {
			case "get", "post", "put", "patch", "delete", "head":
				documented[strings.ToUpper(method)+" "+path] = true
			}
		}
	}

	var missing, stale []string
	for op := range documented {
		if _, ok := manifest.Operations[op]; !ok {
			missing = append(missing, op)
		}
	}
	for op, entry := range manifest.Operations {
		if !documented[op] {
			stale = append(stale, op)
		}
		var excluded struct {
			Excluded string `json:"excluded"`
		}
		if json.Unmarshal(entry, &excluded) == nil && entry[0] == '{' && strings.TrimSpace(excluded.Excluded) == "" {
			t.Errorf("%s is excluded without a reason", op)
		}
	}
	sort.Strings(missing)
	sort.Strings(stale)
	if len(missing) > 0 {
		t.Errorf("in docs/api/openapi.yaml but not in packages/revoked-js/coverage.json; map each to an SDK method or exclude it with a reason:\n  %s",
			strings.Join(missing, "\n  "))
	}
	if len(stale) > 0 {
		t.Errorf("in packages/revoked-js/coverage.json but no longer in the spec:\n  %s", strings.Join(stale, "\n  "))
	}
}
