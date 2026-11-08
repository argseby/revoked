package routes

import (
	"net/http"
	"strings"
	"sync/atomic"
	"time"

	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/hook"
	"github.com/pocketbase/pocketbase/tools/types"
)

const envLimitTwoFactor = "RATELIMIT_2FA_ATTEMPTS"

// twoFactorLimiter bounds code attempts per account, wherever they come from:
// six digits are a million guesses, and switching addresses must not buy more
// of them.
var twoFactorLimiter = util.NewRateLimiter(util.LimitFromEnv(envLimitTwoFactor, 10), 5*time.Minute)

// ConfigureTwoFactorRateLimit replaces the per-account code limiter (0
// disables it). For the test harness only.
func ConfigureTwoFactorRateLimit(attempts int) {
	twoFactorLimiter = util.NewRateLimiter(attempts, 5*time.Minute)
}

// twoFactorMaxAttempts is how many codes one sign-in may try before it has to
// start again with the passkey.
const twoFactorMaxAttempts = 5

// twoFactorChallenge is a passkey sign-in that has proven the passkey and now
// waits for the code from the authenticator app.
type twoFactorChallenge struct {
	user     string
	meta     map[string]any
	attempts atomic.Int32
}

var twoFactorChallenges passkeyVault[twoFactorChallenge]

// twoFactorClock is the time codes are checked against. A code works once, so
// a test that signs in twice moves it forward instead of waiting 30 seconds.
var twoFactorClock = time.Now

// ConfigureTwoFactorClock replaces the time codes are checked against (nil
// restores the real one). For the test harness only.
func ConfigureTwoFactorClock(now func() time.Time) {
	if now == nil {
		now = time.Now
	}
	twoFactorClock = now
}

// TwoFactorRoute is the second factor after the passkey: a code from an
// authenticator app (RFC 6238). The secret lives on this server, so the server
// can require it (REQUIRE_2FA) and an operator can reset it
// (`revoked user reset-2fa`).
//
//	GET    /api/2fa                    -> {enabled, required, setupRequired, enabledAt}
//	POST   /api/2fa/totp/setup         -> {secret, otpauthUri}
//	POST   /api/2fa/totp/confirm       {code}
//	DELETE /api/2fa/totp               {code}
//	POST   /api/passkeys/token/2fa     {challenge, code}   -> session
//
// The last one completes a sign-in that POST /api/passkeys/token answered with
// two_factor_required.
func TwoFactorRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/2fa", func(re *core.RequestEvent) error {
			account, ok := twoFactorAccount(app, re)
			if !ok {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			return re.JSON(http.StatusOK, twoFactorStatus(account))
		})

		e.Router.POST("/api/2fa/totp/setup", func(re *core.RequestEvent) error {
			account, ok := twoFactorAccount(app, re)
			if !ok {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			if !twoFactorLimiter.Allow(account.Id) {
				return rateLimitedResponse(re)
			}
			if services.TwoFactorEnabled(account) {
				return appErrorResponse(re, http.StatusConflict, &util.Errors.TwoFactorAlreadyEnabled)
			}
			secret, err := util.NewTotpSecret()
			if err != nil {
				return re.InternalServerError("Failed to make a secret", err)
			}
			// Pending until a code proves the app holds it: a scan that went
			// wrong must not lock the account out.
			account.Set(util.Fields.User.TotpPending, secret)
			if err := app.Save(account); err != nil {
				return re.InternalServerError("Failed to save the secret", err)
			}
			return re.JSON(http.StatusOK, map[string]any{
				"secret":     secret,
				"otpauthUri": util.TotpURI(secret, account.Email()),
			})
		})

		e.Router.POST("/api/2fa/totp/confirm", func(re *core.RequestEvent) error {
			account, ok := twoFactorAccount(app, re)
			if !ok {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			if !twoFactorLimiter.Allow(account.Id) {
				return rateLimitedResponse(re)
			}
			var body struct {
				Code string `json:"code"`
			}
			_ = re.BindBody(&body)
			if services.TwoFactorEnabled(account) {
				return appErrorResponse(re, http.StatusConflict, &util.Errors.TwoFactorAlreadyEnabled)
			}
			pending := account.GetString(util.Fields.User.TotpPending)
			if pending == "" {
				return appErrorResponse(re, http.StatusConflict, &util.Errors.TwoFactorNotPending)
			}
			if !services.UseTotpCode(app, account, pending, body.Code, twoFactorClock()) {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.TwoFactorCodeInvalid)
			}
			f := util.Fields.User
			account.Set(f.TotpSecret, pending)
			account.Set(f.TotpPending, "")
			account.Set(f.TotpEnabledAt, types.NowDateTime())
			// Every other session was signed in with the passkey alone. A new
			// token key ends them; this device gets a fresh session below.
			account.RefreshTokenKey()
			if err := app.Save(account); err != nil {
				return re.InternalServerError("Failed to turn on two-factor authentication", err)
			}
			services.AuditTwoFactor(app, account, true, re.RealIP(), re.Request.UserAgent())
			app.Logger().Info("Two-factor authentication turned on", "user", account.Id, "ip", re.RealIP())
			token, err := account.NewAuthToken()
			if err != nil {
				return re.InternalServerError("Failed to renew the session", err)
			}
			out := twoFactorStatus(account)
			out["token"] = token
			return re.JSON(http.StatusOK, out)
		})

		e.Router.DELETE("/api/2fa/totp", func(re *core.RequestEvent) error {
			account, ok := twoFactorAccount(app, re)
			if !ok {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			if util.TwoFactorRequired() {
				return appErrorResponse(re, http.StatusForbidden, &util.Errors.TwoFactorEnforced)
			}
			if !twoFactorLimiter.Allow(account.Id) {
				return rateLimitedResponse(re)
			}
			var body struct {
				Code string `json:"code"`
			}
			_ = re.BindBody(&body)
			if !services.TwoFactorEnabled(account) {
				return appErrorResponse(re, http.StatusConflict, &util.Errors.TwoFactorNotEnabled)
			}
			// A session alone is not enough: whoever turns it off shows they
			// hold the authenticator too.
			if !services.UseTotpCode(app, account, account.GetString(util.Fields.User.TotpSecret), body.Code, twoFactorClock()) {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.TwoFactorCodeInvalid)
			}
			f := util.Fields.User
			account.Set(f.TotpSecret, "")
			account.Set(f.TotpPending, "")
			account.Set(f.TotpEnabledAt, "")
			if err := app.Save(account); err != nil {
				return re.InternalServerError("Failed to turn off two-factor authentication", err)
			}
			services.AuditTwoFactor(app, account, false, re.RealIP(), re.Request.UserAgent())
			app.Logger().Info("Two-factor authentication turned off", "user", account.Id, "ip", re.RealIP())
			return re.JSON(http.StatusOK, twoFactorStatus(account))
		})

		e.Router.POST("/api/passkeys/token/2fa", func(re *core.RequestEvent) error {
			if !allowRequest(re, passkeyLimiter, "") {
				return rateLimitedResponse(re)
			}
			var body struct {
				Challenge string `json:"challenge"`
				Code      string `json:"code"`
			}
			_ = re.BindBody(&body)
			invalid := func() error {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.TwoFactorChallengeInvalid)
			}
			challenge, ok := twoFactorChallenges.peek(body.Challenge)
			if !ok {
				return invalid()
			}
			if !twoFactorLimiter.Allow(challenge.user) {
				return rateLimitedResponse(re)
			}
			if challenge.attempts.Add(1) > twoFactorMaxAttempts {
				twoFactorChallenges.take(body.Challenge)
				return invalid()
			}
			account, err := app.FindRecordById(util.Coll.Users, challenge.user)
			if err != nil || account == nil {
				twoFactorChallenges.take(body.Challenge)
				return invalid()
			}
			secret := account.GetString(util.Fields.User.TotpSecret)
			if secret == "" {
				// Reset by the operator while this sign-in waited: the
				// passkey alone signs in now, but only through a new attempt.
				twoFactorChallenges.take(body.Challenge)
				return invalid()
			}
			if !services.UseTotpCode(app, account, secret, body.Code, twoFactorClock()) {
				app.Logger().Warn("Two-factor code refused", "user", account.Id, "ip", re.RealIP())
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.TwoFactorCodeInvalid)
			}
			// Spent on success; a concurrent success with the same challenge
			// loses here.
			if _, ok := twoFactorChallenges.take(body.Challenge); !ok {
				return invalid()
			}
			return apis.RecordAuthResponse(re, account, "passkey", challenge.meta)
		})

		return e.Next()
	})
}

// twoFactorAccount is the signed-in person, fresh from the database: the
// session's record does not carry hidden fields reliably. Users only: an API
// key must not change how the person behind it signs in.
func twoFactorAccount(app core.App, re *core.RequestEvent) (*core.Record, bool) {
	if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
		return nil, false
	}
	account, err := app.FindRecordById(util.Coll.Users, re.Auth.Id)
	if err != nil || account == nil {
		return nil, false
	}
	return account, true
}

func twoFactorStatus(account *core.Record) map[string]any {
	enabled := services.TwoFactorEnabled(account)
	required := util.TwoFactorRequired()
	out := map[string]any{
		"enabled":       enabled,
		"required":      required,
		"setupRequired": required && !enabled,
		"enabledAt":     nil,
	}
	if enabled {
		if at := account.GetDateTime(util.Fields.User.TotpEnabledAt); !at.IsZero() {
			out["enabledAt"] = at.Time().UTC().Format(time.RFC3339)
		}
	}
	return out
}

// twoFactorChallengeResponse answers a passkey sign-in whose account has an
// authenticator app: no session yet, only a challenge the code completes.
func twoFactorChallengeResponse(re *core.RequestEvent, account *core.Record, meta map[string]any) error {
	id := twoFactorChallenges.put(&twoFactorChallenge{user: account.Id, meta: meta}, util.TwoFactorChallengeTTL)
	e := util.Errors.TwoFactorRequired
	return re.JSON(http.StatusUnauthorized, map[string]any{
		"code":      e.ErrorCode,
		"message":   e.ErrorText,
		"status":    http.StatusUnauthorized,
		"challenge": id,
		"expiresAt": time.Now().Add(util.TwoFactorChallengeTTL).UTC().Format(time.RFC3339),
	})
}

// BindTwoFactorGate holds an account that has not set up its authenticator
// app, while REQUIRE_2FA is on, to the few routes that set one up. The app
// sends such an account to its enrolment screen, but the session itself is
// what the server trusts: without this, a passkey alone would still reach the
// vault through the API.
//
// API keys and superusers are not users and pass; an API key made before the
// policy was turned on keeps working until it is revoked.
func BindTwoFactorGate(app core.App) {
	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		se.Router.Bind(&hook.Handler[*core.RequestEvent]{
			Id: "revokedTwoFactorGate",
			// After the auth loaders, so e.Auth is resolved.
			Priority: apis.DefaultLoadAuthTokenMiddlewarePriority + 3,
			Func: func(e *core.RequestEvent) error {
				if !util.TwoFactorRequired() || e.Auth == nil || e.Auth.Collection().Name != util.Coll.Users {
					return e.Next()
				}
				if services.TwoFactorEnabled(e.Auth) || twoFactorGateExempt(e.Request.Method, e.Request.URL.Path, e.Auth.Id) {
					return e.Next()
				}
				return appErrorResponse(e, http.StatusForbidden, &util.Errors.TwoFactorSetupRequired)
			},
		})
		return se.Next()
	})
}

// twoFactorGateExempt lists what an account without its authenticator app
// may still do: set one up, keep its session alive, read its own account and
// the server's policy, and manage its passkeys. Pages outside /api pass, so
// the passkey page keeps working.
func twoFactorGateExempt(method, path, userID string) bool {
	if !strings.HasPrefix(path, "/api/") {
		return true
	}
	users := "/api/collections/" + util.Coll.Users
	switch {
	case path == "/api/2fa", strings.HasPrefix(path, "/api/2fa/"),
		strings.HasPrefix(path, "/api/passkeys"),
		path == "/api/server", path == "/api/features", path == "/api/health",
		path == users+"/auth-refresh":
		return true
	case method == http.MethodGet && path == users+"/records/"+userID:
		return true
	}
	return false
}
