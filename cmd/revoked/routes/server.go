// Package routes defines the application's custom public HTTP endpoints.
package routes

import (
	"io"
	"net/http"
	"os"
	"revoked/cmd/revoked/server"
	"revoked/util"
	"strings"
	"time"

	"github.com/pocketbase/pocketbase/core"
)

// ServerInfoRoute exposes GET /api/server — domain claim, root public key and a
// freshly-signed assertion — so any peer can walk the trust chain
// DNS-TXT → root-pubkey → identity-signature → request. Unauthenticated by design;
// the returned "txt" is an operator diagnostic and carries no trust weight.
func ServerInfoRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/server", func(re *core.RequestEvent) error {
			assertion, err := root.IssueAssertion(time.Now())
			if err != nil {
				return re.InternalServerError("failed to issue assertion", err)
			}
			return re.JSON(http.StatusOK, map[string]any{
				"domain":      root.Domain(),
				"version":     util.Version(),
				"fingerprint": root.Fingerprint(),
				"publicKey":   root.PublicKeyPEM(),
				"assertion":   assertion,
				"txt": map[string]string{
					"host":  root.TXTRecordHost(),
					"value": root.TXTRecordValue(),
				},
				// Operator policy, not workspace state: a client that knows the
				// cap can refuse an oversized file before spending the upload
				// rather than after. -1 means the operator set no cap.
				"limits": map[string]any{
					"maxFileSize": util.FileLimitBytes(util.FileMaxSizeEnv),
				},
				// Operator policy as well: whether this server issues
				// attestations in its domain's name. Holding and verifying
				// credentials do not depend on it.
				"attestations": map[string]any{
					"issuing": util.AttestationsAllowed(),
				},
				// Operator policy too: whether anyone may make an account here,
				// and whether a new one confirms its address with a mailed code.
				// The app tells someone how many steps sign-up takes before
				// sending them to the passkey page, which knows the same.
				"signups": map[string]any{
					"open":        util.SignupsAllowed(),
					"verifyEmail": util.SignupEmailVerification(),
				},
			})
		})

		e.Router.GET("/api/blocked-domains", func(re *core.RequestEvent) error {
			if !allowRequest(re, probeLimiter, "") {
				return rateLimitedResponse(re)
			}
			return serveBlockedDomains(app, re)
		})
		return e.Next()
	})
}

// serveBlockedDomains publishes the operator's own list of impersonating
// domains. The app applies it on top of the project's list, never instead of
// it, so a server can add warnings but cannot lift one.
//
// Read on every request so an edit applies without a restart. An unreadable
// file is a 500 rather than an empty list: the app then keeps the copy it
// fetched last instead of forgetting every entry.
func serveBlockedDomains(app core.App, re *core.RequestEvent) error {
	re.Response.Header().Set("Content-Type", "text/plain; charset=utf-8")
	path := strings.TrimSpace(os.Getenv(util.BlockedDomainsFileEnv))
	if path == "" {
		return re.String(http.StatusOK, "")
	}
	f, err := os.Open(path)
	if err != nil {
		app.Logger().Error("Blocked domains file unreadable", "env", util.BlockedDomainsFileEnv, "error", err)
		return re.String(http.StatusInternalServerError, "")
	}
	defer f.Close()
	body, err := io.ReadAll(io.LimitReader(f, util.MaxBlockedDomainsBytes+1))
	if err != nil || len(body) > util.MaxBlockedDomainsBytes {
		app.Logger().Error("Blocked domains file unreadable or too large", "env", util.BlockedDomainsFileEnv, "error", err)
		return re.String(http.StatusInternalServerError, "")
	}
	return re.String(http.StatusOK, string(body))
}
