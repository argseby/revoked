package routes

import (
	"net/http"
	"revoked/util"
	"time"

	"github.com/pocketbase/pocketbase/core"
)

// Throttles for the credential-free public surface: the slug is the only capability
// guarding a link or request, so these bound slug enumeration and brute force against
// the gate passwords. Each is env-overridable for a busy NAT or an exposed host; 0
// disables that limiter, which is only ever safe outside a public deployment.
const (
	envLimitGate       = "RATELIMIT_GATE_ATTEMPTS"
	envLimitProbe      = "RATELIMIT_PROBE_REQUESTS"
	envLimitChallenge  = "RATELIMIT_CHALLENGE_REQUESTS"
	envLimitCallback   = "RATELIMIT_CALLBACK_TESTS"
	envLimitStamp      = "RATELIMIT_STAMP_REQUESTS"
	envLimitSignupMail = "RATELIMIT_SIGNUP_EMAILS"
	envLimitGrantPeer  = "RATELIMIT_GRANT_REQUESTS"
)

var (
	// gatePasswordLimiter covers password/identifier attempts, keyed by IP+slug so
	// hammering one link cannot lock out the others.
	gatePasswordLimiter = util.NewRateLimiter(util.LimitFromEnv(envLimitGate, 10), 5*time.Minute)

	// probeLimiter covers metadata probes and short-link reads, keyed by IP only —
	// the enumeration budget across all slugs.
	probeLimiter = util.NewRateLimiter(util.LimitFromEnv(envLimitProbe, 120), time.Minute)

	// challengeLimiter covers nonce issuance, keyed by IP.
	challengeLimiter = util.NewRateLimiter(util.LimitFromEnv(envLimitChallenge, 60), time.Minute)

	// callbackTestLimiter covers the callback test button, keyed by the signed-in
	// caller. Not part of ConfigureRateLimits: that switches off the public
	// surface for the test harness, and a per-user budget this size is no
	// obstacle to a suite that fires a handful of tests.
	callbackTestLimiter = util.NewRateLimiter(util.LimitFromEnv(envLimitCallback, 20), time.Minute)

	// stampLimiter covers the owner's stamp previews and archives, keyed by the
	// signed-in caller alone: stamping is CPU work, and switching addresses
	// must not buy more of it.
	stampLimiter = util.NewRateLimiter(util.LimitFromEnv(envLimitStamp, 30), time.Minute)

	// signupMailLimiter covers confirmation codes sent to new addresses, keyed
	// by IP, per hour: each one is an email this server sends to whatever
	// address it is given. Each address has its own fixed budget on top.
	signupMailLimiter = util.NewRateLimiter(util.LimitFromEnv(envLimitSignupMail, 10), time.Hour)

	// grantPeerLimiter covers what other servers call: bulk grant reads,
	// grant events and relayed answers, keyed by IP. Each call carries up to
	// a batch of grants, so the budget is per call, not per grant.
	grantPeerLimiter = util.NewRateLimiter(util.LimitFromEnv(envLimitGrantPeer, 300), time.Minute)
)

// ConfigureRateLimits replaces the public-surface limiters (0 disables one). For the
// test harness only: the limiters are built at package init, so env tuning cannot
// reach them from a binary that has already imported this package.
func ConfigureRateLimits(gateAttempts, probeRequests, challengeRequests int) {
	gatePasswordLimiter = util.NewRateLimiter(gateAttempts, 5*time.Minute)
	probeLimiter = util.NewRateLimiter(probeRequests, time.Minute)
	challengeLimiter = util.NewRateLimiter(challengeRequests, time.Minute)
}

// ConfigurePasskeyRateLimit replaces the passkey limiter (0 disables it). For
// the test harness only, which registers every account it uses from one
// loopback address.
func ConfigurePasskeyRateLimit(requests int) {
	passkeyLimiter = util.NewRateLimiter(requests, time.Minute)
}

// ConfigureSignupMailRateLimit replaces the per-IP confirmation-code limiter
// (0 disables it). For the test harness only, for the same reason.
func ConfigureSignupMailRateLimit(perHour int) {
	signupMailLimiter = util.NewRateLimiter(perHour, time.Hour)
}

// ConfigureGrantRateLimit replaces the server-to-server limiter (0 disables
// it). For the test harness only, whose two "servers" share one address.
func ConfigureGrantRateLimit(requests int) {
	grantPeerLimiter = util.NewRateLimiter(requests, time.Minute)
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
