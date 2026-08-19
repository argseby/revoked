package routes

import (
	"net/http"
	"os"
	"revoked/util"
	"strconv"
	"strings"
	"time"

	"github.com/pocketbase/pocketbase/core"
)

// Throttles for the credential-free public surface: the slug is the only capability
// guarding a link or request, so these bound slug enumeration and brute force against
// the gate passwords. Each is env-overridable for a busy NAT or an exposed host; 0
// disables that limiter, which is only ever safe outside a public deployment.
const (
	envLimitGate      = "RATELIMIT_GATE_ATTEMPTS"
	envLimitProbe     = "RATELIMIT_PROBE_REQUESTS"
	envLimitChallenge = "RATELIMIT_CHALLENGE_REQUESTS"
)

var (
	// gatePasswordLimiter covers password/identifier attempts, keyed by IP+slug so
	// hammering one link cannot lock out the others.
	gatePasswordLimiter = util.NewRateLimiter(limitFromEnv(envLimitGate, 10), 5*time.Minute)

	// probeLimiter covers metadata probes and short-link reads, keyed by IP only —
	// the enumeration budget across all slugs.
	probeLimiter = util.NewRateLimiter(limitFromEnv(envLimitProbe, 120), time.Minute)

	// challengeLimiter covers nonce issuance, keyed by IP.
	challengeLimiter = util.NewRateLimiter(limitFromEnv(envLimitChallenge, 60), time.Minute)
)

// ConfigureRateLimits replaces the public-surface limiters (0 disables one). For the
// test harness only: the limiters are built at package init, so env tuning cannot
// reach them from a binary that has already imported this package.
func ConfigureRateLimits(gateAttempts, probeRequests, challengeRequests int) {
	gatePasswordLimiter = util.NewRateLimiter(gateAttempts, 5*time.Minute)
	probeLimiter = util.NewRateLimiter(probeRequests, time.Minute)
	challengeLimiter = util.NewRateLimiter(challengeRequests, time.Minute)
}

// limitFromEnv reads a non-negative integer limit from the environment,
// falling back to def when unset or malformed.
func limitFromEnv(name string, def int) int {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return def
	}
	v, err := strconv.Atoi(raw)
	if err != nil || v < 0 {
		return def
	}
	return v
}

// rateLimitKey keys the limiter by client IP plus optional scope. RealIP is the
// client rather than the proxy only when the trusted-proxy config is correct.
func rateLimitKey(re *core.RequestEvent, scope string) string {
	ip := re.RealIP()
	if ip == "" {
		ip = re.Request.RemoteAddr
	}
	if scope == "" {
		return ip
	}
	return ip + "|" + scope
}

// allowRequest reports whether the caller is still within limiter's budget. It
// returns a bool, not an error, because writing a response returns nil here — a
// helper that both wrote the 429 and returned it would let the handler sail on and
// run the very code the limit protects. Callers must pair it with an early return.
func allowRequest(re *core.RequestEvent, limiter *util.RateLimiter, scope string) bool {
	return limiter.Allow(rateLimitKey(re, scope))
}

// rateLimitedResponse writes the 429 envelope and returns nil, so
// `return rateLimitedResponse(re)` ends the handler.
func rateLimitedResponse(re *core.RequestEvent) error {
	re.Response.Header().Set("Retry-After", "60")
	return appErrorResponse(re, http.StatusTooManyRequests, &util.Errors.RateLimited)
}
