package routes

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestBrandLogosMatchApp(t *testing.T) {
	for _, name := range []string{"revoced-mark-redacted-black-on-white.svg", "revoced-mark-redacted-white-on-black.svg"} {
		app, err := os.ReadFile(filepath.Join("..", "..", "..", "app", "assets", "icon", name))
		if err != nil {
			t.Fatal(err)
		}
		embedded, err := brandFS.ReadFile("brand/" + name)
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(app, embedded) {
			t.Errorf("cmd/revoked/routes/brand/%s differs from app/assets/icon/%s; copy it over", name, name)
		}
	}
}
