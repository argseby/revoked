package tests

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"revoked/tests/testutils"
)

// TestJavaScriptSDK runs the SDK's integration suite against this server, so
// its headers, rules, handshakes and signatures meet the real thing rather
// than a mock of it.
func TestJavaScriptSDK(t *testing.T) {
	npx, err := exec.LookPath("npx")
	if err != nil {
		t.Skip("node is not installed; the JavaScript SDK is not checked against the server on this machine")
	}
	pkg, err := filepath.Abs(filepath.Join("..", "packages", "revoked-js"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(pkg, "node_modules", "vitest")); err != nil {
		t.Skip("packages/revoked-js has no node_modules; run `npm ci` there first")
	}

	baseURL, _ := testutils.SetupTestApp(t)
	_, owner, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("owner: %v", err)
	}
	_, responder, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("responder: %v", err)
	}

	cmd := exec.Command(npx, "vitest", "run", "--config", "vitest.integration.config.ts")
	cmd.Dir = pkg
	cmd.Env = append(os.Environ(),
		"REVOKED_SERVER="+baseURL,
		"REVOKED_SESSION="+owner,
		"REVOKED_RESPONDER_SESSION="+responder,
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("the SDK integration suite failed: %v\n%s", err, out)
	}
	t.Logf("%s", out)
}
