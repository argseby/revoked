package sdkgen

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSDKGeneratedFilesCurrent(t *testing.T) {
	dir := filepath.Join("..", "..", "packages", "revoked-js", "src", "generated")
	for name, want := range Files() {
		got, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			t.Fatalf("%s: %v (run `go run ./cmd/gen-sdk`)", name, err)
		}
		if string(got) != want {
			t.Errorf("%s is stale: run `go run ./cmd/gen-sdk` from the repo root", name)
		}
	}
}

func TestErrorDocsCurrent(t *testing.T) {
	for path, want := range Docs() {
		got, err := os.ReadFile(filepath.Join("..", "..", path))
		if err != nil {
			t.Fatalf("%s: %v (run `go run ./cmd/gen-sdk`)", path, err)
		}
		if string(got) != want {
			t.Errorf("%s is stale: run `go run ./cmd/gen-sdk` from the repo root", path)
		}
	}
}
