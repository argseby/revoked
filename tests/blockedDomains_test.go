package tests

import (
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"
)

func TestBlockedDomainsServesTheOperatorsFile(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	t.Setenv(util.BlockedDomainsFileEnv, "")
	api.E.GET("/api/blocked-domains").Expect().
		Status(http.StatusOK).Body().IsEmpty()

	path := filepath.Join(t.TempDir(), "blocked.txt")
	if err := os.WriteFile(path, []byte("# ours\nfake-revoked.example\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv(util.BlockedDomainsFileEnv, path)
	page := api.E.GET("/api/blocked-domains").Expect().Status(http.StatusOK)
	page.Header("Content-Type").Contains("text/plain")
	page.Body().IsEqual("# ours\nfake-revoked.example\n")

	// An edit applies without a restart.
	if err := os.WriteFile(path, []byte("other.example\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	api.E.GET("/api/blocked-domains").Expect().
		Status(http.StatusOK).Body().IsEqual("other.example\n")
}

// A list the server cannot read must not look like an empty one, or the app
// would replace the copy it holds with nothing.
func TestBlockedDomainsUnreadableFileIsAnError(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	t.Setenv(util.BlockedDomainsFileEnv, filepath.Join(t.TempDir(), "missing.txt"))
	api.E.GET("/api/blocked-domains").Expect().Status(http.StatusInternalServerError)
}
