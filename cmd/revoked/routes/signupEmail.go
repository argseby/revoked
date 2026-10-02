package routes

import (
	"crypto/subtle"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"

	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/go-ozzo/ozzo-validation/v4/is"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/security"
)

// Confirming a new account's address, where the operator asks for it
// (SIGNUP_VERIFY_EMAIL). Before the passkey is made, the page asks for a code
// sent to the address, and trades the right code for a proof the
// registration then has to carry:
//
//	POST /api/passkeys/register/email   {email}         -> {expiresAt, resendAfter}
//	POST /api/passkeys/register/verify  {email, code}   -> {proof}
//	POST /api/passkeys/register/begin   {email, proof, ...}
//
// The proof is checked when the ceremony begins and spent when the account is
// written, so a dismissed system sheet does not cost a new code.
func SignupEmailRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		bindSignupEmailRoutes(app, e, root)
		return e.Next()
	})
}

func bindSignupEmailRoutes(app core.App, e *core.ServeEvent, root *server.RootKey) {
	e.Router.POST("/api/passkeys/register/email", func(re *core.RequestEvent) error {
		if !allowRequest(re, passkeyLimiter, "") {
			return rateLimitedResponse(re)
		}
		var body struct {
			Email string `json:"email"`
		}
		if err := re.BindBody(&body); err != nil {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyRequestInvalid)
		}
		if !util.SignupsAllowed() {
			return appErrorResponse(re, http.StatusForbidden, &util.Errors.SignupsDisabled)
		}
		if !util.SignupEmailVerification() {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.EmailVerificationOff)
		}
		email, ok := signupEmail(body.Email)
		if !ok {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyEmailInvalid)
		}
		if taken, err := emailTaken(app, email); err != nil {
			return re.InternalServerError("Failed to send the code", err)
		} else if taken {
			return appErrorResponse(re, http.StatusConflict, &util.Errors.PasskeyEmailTaken)
		}

		code := security.RandomStringWithAlphabet(util.EmailCodeLength, "0123456789")
		expires, refusal := signupCodes.issue(email, code, time.Now())
		if refusal != nil {
			re.Response.Header().Set("Retry-After", "60")
			return appErrorResponse(re, http.StatusTooManyRequests, refusal)
		}
		// Counted only once a code is actually going out: the checks above
		// cost the caller nothing but the request.
		if !allowRequest(re, signupMailLimiter, "") {
			signupCodes.forget(email)
			return rateLimitedResponse(re)
		}
		if err := services.SendSignupCode(app, email, code, pageOrigin(re, root)); err != nil {
			signupCodes.forget(email)
			app.Logger().Error("Failed to send a confirmation code", "error", err, "ip", re.RealIP())
			return appErrorResponse(re, http.StatusBadGateway, &util.Errors.EmailSendFailed)
		}
		app.Logger().Info("Confirmation code sent", "ip", re.RealIP())
		return re.JSON(http.StatusOK, map[string]any{
			"expiresAt":   expires.UTC().Format(time.RFC3339),
			"resendAfter": int(util.EmailCodeResendAfter.Seconds()),
		})
	})

	e.Router.POST("/api/passkeys/register/verify", func(re *core.RequestEvent) error {
		if !allowRequest(re, passkeyLimiter, "") {
			return rateLimitedResponse(re)
		}
		var body struct {
			Email string `json:"email"`
			Code  string `json:"code"`
		}
		if err := re.BindBody(&body); err != nil {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyRequestInvalid)
		}
		email, ok := signupEmail(body.Email)
		code := strings.TrimSpace(body.Code)
		if !ok || !emailCodePattern.MatchString(code) || !signupCodes.redeem(email, code, time.Now()) {
			return appErrorResponse(re, http.StatusBadRequest, &util.Errors.EmailCodeInvalid)
		}
		return re.JSON(http.StatusOK, map[string]any{
			"proof": emailProofs.put(&emailProof{email: email}, util.EmailProofTTL),
		})
	})
}

var emailCodePattern = regexp.MustCompile(`^[0-9]{6}$`)

// signupEmail normalizes an address the way accounts are looked up by.
func signupEmail(raw string) (string, bool) {
	email := strings.ToLower(strings.TrimSpace(raw))
	if validation.Validate(email, validation.Required, validation.Length(3, 255), is.EmailFormat) != nil {
		return "", false
	}
	return email, true
}

func emailTaken(app core.App, email string) (bool, error) {
	users, err := app.FindCollectionByNameOrId(util.Coll.Users)
	if err != nil {
		return false, err
	}
	taken, _ := app.FindAuthRecordByEmail(users, email)
	return taken != nil, nil
}

// emailProof says an address was confirmed by whoever holds it.
type emailProof struct {
	email string
}

// emailCodeStore holds the code last sent to each address, hashed. In memory,
// like the ceremonies: a restart costs a code in flight and nothing else.
type emailCodeStore struct {
	mu    sync.Mutex
	items map[string]*emailCode
	// sends remembers when each address was sent a code in the last hour,
	// outliving the codes themselves.
	sends map[string][]time.Time
}

type emailCode struct {
	hash     string
	sentAt   time.Time
	expires  time.Time
	attempts int
}

// issue records a new code for email, replacing any earlier one, unless the
// address was sent one too recently or too often.
func (s *emailCodeStore) issue(email, code string, now time.Time) (time.Time, *util.AppError) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.gcLocked(now)
	if c, ok := s.items[email]; ok && now.Sub(c.sentAt) < util.EmailCodeResendAfter {
		return time.Time{}, &util.Errors.EmailCodeTooSoon
	}
	if len(s.sends[email]) >= util.EmailCodesPerHour {
		return time.Time{}, &util.Errors.RateLimited
	}
	if len(s.items) >= passkeyVaultCap {
		return time.Time{}, &util.Errors.RateLimited
	}
	expires := now.Add(util.EmailCodeTTL)
	s.items[email] = &emailCode{hash: util.HashToken(code), sentAt: now, expires: expires}
	s.sends[email] = append(s.sends[email], now)
	return expires, nil
}

// forget withdraws a code that never went out, and the send it was counted as.
func (s *emailCodeStore) forget(email string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.items, email)
	if sends := s.sends[email]; len(sends) > 0 {
		s.sends[email] = sends[:len(sends)-1]
	}
}

// redeem reports whether code is the one sent to email. The right code is
// spent; a wrong one costs an attempt, and the last attempt costs the code.
func (s *emailCodeStore) redeem(email, code string, now time.Time) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	c, ok := s.items[email]
	if !ok || !c.expires.After(now) {
		delete(s.items, email)
		return false
	}
	if subtle.ConstantTimeCompare([]byte(util.HashToken(code)), []byte(c.hash)) != 1 {
		c.attempts++
		if c.attempts >= util.EmailCodeAttempts {
			delete(s.items, email)
		}
		return false
	}
	delete(s.items, email)
	return true
}

// gcLocked drops expired codes and sends older than an hour. The caller holds
// the mutex.
func (s *emailCodeStore) gcLocked(now time.Time) {
	if s.items == nil {
		s.items = map[string]*emailCode{}
		s.sends = map[string][]time.Time{}
	}
	for k, c := range s.items {
		if !c.expires.After(now) {
			delete(s.items, k)
		}
	}
	cutoff := now.Add(-time.Hour)
	for k, times := range s.sends {
		kept := times[:0]
		for _, t := range times {
			if t.After(cutoff) {
				kept = append(kept, t)
			}
		}
		if len(kept) == 0 {
			delete(s.sends, k)
		} else {
			s.sends[k] = kept
		}
	}
}

var (
	signupCodes emailCodeStore
	emailProofs passkeyVault[emailProof]
)
