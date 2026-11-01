package routes

import (
	"net/http"
	"strconv"
	"strings"
	"sync"
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

			assertion, err := identityStatusFor(app, root, fingerprint, time.Now())
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

// identityStatusFor resolves a fingerprint and signs the answer, reusing a
// signature it has already made for the same answer.
//
// An unknown fingerprint gets a signed "unknown" rather than a 404: answering
// uniformly keeps the endpoint from being an existence oracle, and a signed
// "I have no record of this" is itself useful — it is how a verifier tells a
// server that disclaims an identity apart from a server it could not reach.
//
// Signing is RSA, about a millisecond, and this runs on the unauthenticated
// read path: a signature per probe caps one core at roughly a thousand of them
// however little else the handler does. The status itself is read fresh every
// time — it is an indexed lookup — and only the signature is reused, keyed by
// the answer it signs. So a revocation changes the key and is stapled on the
// very next probe, with no cache to invalidate from the paths that revoke.
func identityStatusFor(app core.App, root *server.RootKey, fingerprint string, now time.Time) (server.IdentityStatusAssertion, error) {
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

	// The payload carries its own issue time, so it is stamped at the start of
	// the window rather than at the instant of the request: without that every
	// second would need its own signature. The stamp only ever moves earlier,
	// which no verifier minds.
	issuedAt := now.Truncate(statusAssertionTTL)
	key := strings.Join([]string{
		fingerprint, wire, status.Reason,
		strconv.FormatInt(status.RevokedAt.Unix(), 10),
		strconv.FormatInt(issuedAt.Unix(), 10),
	}, "\x00")

	if cached, ok := statusAssertions.lookup(key); ok {
		return cached, nil
	}

	assertion, err := root.IssueIdentityStatus(fingerprint, wire, status.Reason, status.RevokedAt, issuedAt)
	if err != nil {
		return server.IdentityStatusAssertion{}, err
	}
	// Only answers about identities this server knows. The fingerprint comes
	// from the caller, so keeping "unknown" would let anyone fill the map with
	// fingerprints of their own invention; those still cost a signature each,
	// bounded by the probe rate limiter as before.
	if status.Known {
		statusAssertions.keep(key, assertion, issuedAt.Add(statusAssertionTTL))
	}
	return assertion, nil
}

// statusAssertionTTL is how long one signature is reused. Two orders of
// magnitude under server.IdentityStatusTTL, and it does not bound how stale an
// answer can be — the answer is re-read every time — only how often an
// unchanged one is re-signed.
const statusAssertionTTL = time.Minute

// statusAssertionCap bounds the map: an instance with more live identities
// being probed at once than this stops taking new ones rather than growing
// without end.
const statusAssertionCap = 4096

// statusAssertions is deliberately in-process, like the challenge and download
// registries: every entry is a copy of something this server can mint again,
// so losing the map on restart costs one signature per answer.
var statusAssertions = &statusAssertionCache{entries: make(map[string]statusAssertionEntry)}

type statusAssertionEntry struct {
	Assertion server.IdentityStatusAssertion
	ExpiresAt time.Time
}

type statusAssertionCache struct {
	mu      sync.Mutex
	entries map[string]statusAssertionEntry
}

func (c *statusAssertionCache) lookup(key string) (server.IdentityStatusAssertion, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	entry, ok := c.entries[key]
	if !ok {
		return server.IdentityStatusAssertion{}, false
	}
	return entry.Assertion, true
}

func (c *statusAssertionCache) keep(key string, assertion server.IdentityStatusAssertion, expiresAt time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.gcLocked(expiresAt)

	if _, replacing := c.entries[key]; !replacing && len(c.entries) >= statusAssertionCap {
		return
	}
	c.entries[key] = statusAssertionEntry{Assertion: assertion, ExpiresAt: expiresAt}
}

// gcLocked drops every entry whose window ends before upTo. Callers pass the
// window they are about to write, so entries from earlier windows go and the
// current one's stay: a key carries the window it was minted in, so an older
// entry can never be read again and is only holding memory.
func (c *statusAssertionCache) gcLocked(upTo time.Time) {
	for key, entry := range c.entries {
		if upTo.After(entry.ExpiresAt) {
			delete(c.entries, key)
		}
	}
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
	assertion, err := identityStatusFor(app, root, fingerprint, time.Now())
	if err != nil {
		app.Logger().Error("Failed to staple an identity status", "error", err)
		return
	}
	block["statusAssertion"] = assertion
}
