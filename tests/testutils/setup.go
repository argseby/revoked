// Package testutils provides shared helpers for spinning up a test PocketBase app.
package testutils

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"revoked/cmd/revoked/bootstrap"
	"revoked/cmd/revoked/routes"
	"revoked/cmd/revoked/server"
	_ "revoked/migrations"
	"revoked/util"
	"sync"
	"testing"
	"time"

	"github.com/gavv/httpexpect/v2"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/plugins/migratecmd"
	"github.com/stretchr/testify/assert"
)

var (
	testApp                *pocketbase.PocketBase
	testAppURL             = "127.0.0.1:5559"
	testAppUrlWithProtocol = "http://127.0.0.1:5559"
	serverOnce             sync.Once
	serverCtx              context.Context
	cancelServer           context.CancelFunc
)

// SetupTestApp starts (once) the PocketBase instance shared by the suite.
func SetupTestApp(t testing.TB) (string, *pocketbase.PocketBase) {
	t.Helper()

	serverOnce.Do(func() {
		testDataDir := "./pb_test_data"
		_ = os.RemoveAll(testDataDir)

		// The suite registers its own accounts over HTTP, which a server that
		// refuses registrations would reject. Not t.Setenv: that reverts when
		// the first test returns, while this server is booted once and serves
		// every test after it. Signup policy itself is covered by
		// TestSignups_*, which sets the variable per case.
		_ = os.Setenv(util.AllowSignupsEnv, "true")

		testApp = pocketbase.NewWithConfig(pocketbase.Config{
			DefaultDataDir: testDataDir,
		})

		migratecmd.MustRegister(testApp, testApp.RootCmd, migratecmd.Config{
			Automigrate: true,
		})

		if err := testApp.Bootstrap(); err != nil {
			t.Fatalf("Failed to bootstrap app: %v", err)
		}

		os.Args = []string{"pb", "migrate", "up"}
		if err := testApp.RootCmd.ExecuteContext(context.Background()); err != nil {
			fmt.Printf("Migration notice: %v\n", err)
		}

		// The data dir is wiped above, so the root key is fresh on every run and
		// no identity signed by a stale key survives between runs.
		root, err := server.Load("test.invalid", filepath.Join(testDataDir, "server_root.pem"))
		if err != nil {
			t.Fatalf("Failed to initialize test root key: %v", err)
		}

		if _, err := util.LoadOrGenerateCertificate(testDataDir); err != nil {
			t.Fatalf("Failed to load or generate server certificate: %v", err)
		}

		// The whole suite shares one loopback rate-limit bucket, so the
		// public-surface limits would trip as tests are added. Tests that assert
		// 429 re-enable a low limit for their duration.
		routes.ConfigureRateLimits(0, 0, 0)

		bootstrap.Bind(testApp, root)

		serverCtx, cancelServer = context.WithCancel(context.Background())

		testApp.OnServe().BindFunc(func(e *core.ServeEvent) error {
			e.InstallerFunc = nil
			return e.Next()
		})

		go func() {
			if err := apis.Serve(testApp, apis.ServeConfig{
				HttpAddr:        testAppURL,
				ShowStartBanner: false,
			}); err != nil {
				fmt.Printf("Server stopped: %v\n", err)
			}
		}()

		fmt.Printf("http://%s/healthz\n", testAppURL)
		waitForHealthy(t, fmt.Sprintf("http://%s/healthz", testAppURL))
	})

	return fmt.Sprintf("http://%s", testAppURL), testApp
}
func waitForHealthy(t testing.TB, url string) {
	timeout := time.After(30 * time.Second)
	ticker := time.NewTicker(200 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-timeout:
			t.Fatal("Timeout: PocketBase server failed to start")
		case <-ticker.C:
			resp, err := http.Get(url)
			if err == nil && resp.StatusCode == http.StatusOK {
				return
			}
		}
	}
}

// ClearCollections truncates the named collections.
func ClearCollections(t testing.TB, app *pocketbase.PocketBase, names ...string) {
	t.Helper()

	for _, name := range names {
		collection, err := app.FindCollectionByNameOrId(name)
		if err != nil {
			t.Fatalf("Collection %s not found: %v", name, err)
		}

		if err := app.TruncateCollection(collection); err != nil {
			t.Fatalf("Failed to truncate %s: %v", name, err)
		}
	}
}

// ClearAllCustomData truncates the workspace, membership and user collections.
func ClearAllCustomData(t testing.TB, app *pocketbase.PocketBase) {
	t.Helper()

	collections := []string{"workspaces", "workspace_members", "users"}
	ClearCollections(t, app, collections...)
}

// AssertBadRequestErrors asserts a 400 whose data object carries the expected
// error code and message under each key.
func AssertBadRequestErrors(t *testing.T, resp *httpexpect.Response, expectations map[string]util.AppError) {
	resp.Status(http.StatusBadRequest)
	body := resp.JSON().Object()

	body.Value("status").Number().IsEqual(http.StatusBadRequest)
	actualMsg := resp.JSON().Object().Value("message").String().Raw()
	if actualMsg != "Something went wrong while processing your request." && actualMsg != util.Errors.WorkspaceLimitReached.ErrorText {
		assert.Equal(t, "Something went wrong while processing your request.", actualMsg)
	}

	data := body.Value("data").Object()

	for key, appErr := range expectations {
		errorContext := data.Value(key).Object()
		errorContext.Value("code").String().IsEqual(appErr.ErrorCode)
		errorContext.Value("message").String().IsEqual(appErr.ErrorText)
	}
}

// AssertErrorResponse asserts the HTTP status plus the status and message of a
// top-level error body.
func AssertErrorResponse(t *testing.T, resp *httpexpect.Response, expectedStatus int, expectedMessage string) {
	resp.Status(expectedStatus)
	body := resp.JSON().Object()

	body.Value("status").Number().IsEqual(expectedStatus)
	body.Value("message").String().IsEqual(expectedMessage)
}

// NewExpect returns an httpexpect instance scoped to t.
func NewExpect(t *testing.T, baseURL string) *httpexpect.Expect {
	return httpexpect.WithConfig(httpexpect.Config{
		BaseURL:  baseURL,
		Reporter: httpexpect.NewAssertReporter(t),
		Printers: []httpexpect.Printer{
			httpexpect.NewCompactPrinter(t),
		},
	})
}
