package tests

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"testing"

	"gopkg.in/yaml.v3"
)

// docker-compose.yml maps every variable by name instead of using env_file, and
// .env never reaches the image, so a setting missing from that list is silently
// ignored in production while working under `go run`. ALLOW_ATTESTATIONS was
// lost this way.
func TestComposePassesEveryDocumentedVariable(t *testing.T) {
	root := filepath.Join("..")

	example, err := os.ReadFile(filepath.Join(root, ".env.example"))
	if err != nil {
		t.Fatalf("read .env.example: %v", err)
	}
	raw, err := os.ReadFile(filepath.Join(root, "docker-compose.yml"))
	if err != nil {
		t.Fatalf("read docker-compose.yml: %v", err)
	}
	var compose struct {
		Services map[string]struct {
			Environment map[string]any `yaml:"environment"`
		} `yaml:"services"`
	}
	if err := yaml.Unmarshal(raw, &compose); err != nil {
		t.Fatalf("parse docker-compose.yml: %v", err)
	}
	passed := compose.Services["api"].Environment

	// Read by compose itself to lay out the stack, never by the server.
	composeOnly := map[string]bool{
		"CONTAINER_NAME": true,
		"API_PORT":       true,
		"HTTP_PORT":      true,
		"HTTPS_PORT":     true,
		"PROXY_NETWORK":  true,
		// A build argument, not a runtime variable.
		"REVOKED_VERSION": true,
	}

	var missing []string
	for _, m := range regexp.MustCompile(`(?m)^#?\s*([A-Z][A-Z0-9_]*)=`).FindAllStringSubmatch(string(example), -1) {
		key := m[1]
		if composeOnly[key] {
			continue
		}
		if _, ok := passed[key]; !ok {
			missing = append(missing, key)
		}
	}
	sort.Strings(missing)
	if len(missing) > 0 {
		t.Fatalf("docker-compose.yml does not pass these .env.example variables to the api service: %v", missing)
	}
}
