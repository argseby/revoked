// Package routes defines the application's custom public HTTP endpoints.
package routes

import (
	"net/http"
	"revoked/cmd/revoked/server"
	"revoked/util"
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
			})
		})
		return e.Next()
	})
}
