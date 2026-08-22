package routes

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// IdentityStatusRoute exposes GET /api/identities/{fingerprint}/status: this
// server's signed, timestamped answer about one identity it issued.
//
// This is the piece a certificate cannot carry. A leaf is minted for ten years
// and its parentSignature never expires, so a holder who has been removed from
// the workspace goes on proving the same thing they proved on their first day.
// A signed challenge cannot close that — it proves possession of the key, which
// the departed holder still has. Only the issuer's current opinion can, and this
// is where the issuer states it.
//
// Signed by the root key rather than served on TLS alone: the caller has already
// pinned that key through DNS to verify the identity's parentSignature, so the
// answer needs no separate trust in this endpoint, and a proxy cannot rewrite it.
//
// Unauthenticated by design — the people who most need to ask are the ones with
// no account here.
func IdentityStatusRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/identities/{fingerprint}/status", func(re *core.RequestEvent) error {
			if !allowRequest(re, probeLimiter, "identity-status") {
				return rateLimitedResponse(re)
			}

			fingerprint := strings.ToLower(strings.TrimSpace(re.Request.PathValue("fingerprint")))
			if !server.ValidIdentityFingerprint(fingerprint) {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.IdentityFingerprintInvalid)
			}

			assertion, err := IssueIdentityStatusFor(app, root, fingerprint, time.Now())
			if err != nil {
				return re.InternalServerError("Failed to issue an identity status", nil)
			}

			// Cacheable for exactly as long as the signature claims to be valid,
			// so a relay's cache can never outlive the statement inside it.
			re.Response.Header().Set(
				"Cache-Control",
				"public, max-age="+strconv.Itoa(int(server.IdentityStatusTTL.Seconds())),
			)
			return re.JSON(http.StatusOK, assertion)
		})

		return e.Next()
	})
}

// IssueIdentityStatusFor resolves a fingerprint and signs the answer.
//
// An unknown fingerprint gets a signed "unknown" rather than a 404: answering
// uniformly keeps the endpoint from being an existence oracle, and a signed
// "I have no record of this" is itself useful — it is how a verifier tells a
// server that disclaims an identity apart from a server it could not reach.
func IssueIdentityStatusFor(app core.App, root *server.RootKey, fingerprint string, now time.Time) (server.IdentityStatusAssertion, error) {
	status, err := services.LookupIdentityStatus(app, fingerprint)
	if err != nil {
		return server.IdentityStatusAssertion{}, err
	}

	wire := server.IdentityStatusUnknown
	switch {
	case status.Known && status.Status == util.StatusActive:
		wire = server.IdentityStatusActive
	case status.Known:
		wire = server.IdentityStatusRevoked
	}

	return root.IssueIdentityStatus(fingerprint, wire, status.Reason, status.RevokedAt, now)
}

// stapleIdentityStatus attaches this server's signed answer about an identity to
// a probe payload.
//
// Stapling rather than making every viewer fetch it: the probe already comes
// from the server being asked about, so the common case costs no extra
// round-trip, and a relay passing on a foreign identity can carry the issuer's
// current word with it instead of leaving each client to go and ask.
func stapleIdentityStatus(app core.App, root *server.RootKey, block map[string]any, fingerprint string) {
	if !server.ValidIdentityFingerprint(fingerprint) {
		return
	}
	assertion, err := IssueIdentityStatusFor(app, root, fingerprint, time.Now())
	if err != nil {
		app.Logger().Error("Failed to staple an identity status", "error", err)
		return
	}
	block["statusAssertion"] = assertion
}
