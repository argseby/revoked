package tests

import (
	"net/http"
	"sync"
	"testing"
	"time"

	"revoked/cmd/revoked/routes"
	"revoked/cmd/revoked/services"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
)

// totpClock is the server's time for codes in these tests. A code works only
// once, so each new code moves it on by a period instead of waiting for one.
var totpClock struct {
	sync.Mutex
	now time.Time
}

// fakeTotpClock points the server's code checks at totpClock for this test.
func fakeTotpClock(t *testing.T) {
	t.Helper()
	totpClock.Lock()
	totpClock.now = time.Now()
	totpClock.Unlock()
	routes.ConfigureTwoFactorClock(func() time.Time {
		totpClock.Lock()
		defer totpClock.Unlock()
		return totpClock.now
	})
	t.Cleanup(func() { routes.ConfigureTwoFactorClock(nil) })
}

func totpTime() time.Time {
	totpClock.Lock()
	defer totpClock.Unlock()
	return totpClock.now
}

// totpNow is the code the authenticator app shows for secret in the next
// period, with the server's clock moved there: a code nobody has used yet.
func totpNow(t *testing.T, secret string) string {
	t.Helper()
	totpClock.Lock()
	totpClock.now = totpClock.now.Add(util.TotpPeriod)
	totpClock.Unlock()
	return totpAgain(t, secret)
}

// totpAgain is the code for the current period again, without moving on: the
// one last used.
func totpAgain(t *testing.T, secret string) string {
	t.Helper()
	code, ok := util.TotpCode(secret, totpTime())
	if !ok {
		t.Fatalf("secret %q does not decode", secret)
	}
	return code
}

// totpWrong is a well-formed code the server will not accept now: none of the
// steps in the window.
func totpWrong(t *testing.T, secret string) string {
	t.Helper()
	now := totpTime()
	for offset := 10; ; offset++ {
		code, _ := util.TotpCode(secret, now.Add(time.Duration(offset)*util.TotpPeriod))
		if !util.VerifyTotp(secret, code, now) {
			return code
		}
	}
}

// enableTotp sets up and confirms an authenticator for the session's account
// and returns its secret and the fresh session the confirmation hands back:
// turning it on ends every session the account had, token included.
func enableTotp(t *testing.T, e *httpexpect.Expect, token string) (secret, newToken string) {
	t.Helper()
	setup := e.POST("/api/2fa/totp/setup").WithHeader("Authorization", token).
		Expect().Status(http.StatusOK).JSON().Object()
	secret = setup.Value("secret").String().NotEmpty().Raw()
	setup.Value("otpauthUri").String().HasPrefix("otpauth://totp/Revoked:").Contains("secret=" + secret)
	confirmed := e.POST("/api/2fa/totp/confirm").WithHeader("Authorization", token).
		WithJSON(map[string]any{"code": totpNow(t, secret)}).
		Expect().Status(http.StatusOK).JSON().Object()
	confirmed.Value("enabled").Boolean().IsTrue()
	return secret, confirmed.Value("token").String().NotEmpty().Raw()
}

// passkeyCode runs the passkey ceremony and returns the code and verifier the
// app would hold.
func passkeyCode(t *testing.T, device *testutils.PasskeyDevice) (code, verifier string) {
	t.Helper()
	verifier, challenge := testutils.PKCEPair()
	code, err := device.SignInCode(challenge)
	if err != nil {
		t.Fatalf("sign in: %v", err)
	}
	return code, verifier
}

func TestTwoFactorSetupAndSignIn(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	fakeTotpClock(t)
	userID, token, device, err := testutils.CreateRandomUserWithDevice(baseURL)
	if err != nil {
		t.Fatalf("user: %v", err)
	}
	e := testutils.NewExpect(t, baseURL)

	t.Run("off until set up", func(t *testing.T) {
		status := e.GET("/api/2fa").WithHeader("Authorization", token).
			Expect().Status(http.StatusOK).JSON().Object()
		status.Value("enabled").Boolean().IsFalse()
		status.Value("required").Boolean().IsFalse()
		status.Value("setupRequired").Boolean().IsFalse()
		e.GET("/api/2fa").Expect().Status(http.StatusUnauthorized)
	})

	t.Run("a pending secret is not active, and a wrong code does not confirm it", func(t *testing.T) {
		secret := e.POST("/api/2fa/totp/setup").WithHeader("Authorization", token).
			Expect().Status(http.StatusOK).JSON().Object().Value("secret").String().Raw()
		e.POST("/api/2fa/totp/confirm").WithHeader("Authorization", token).
			WithJSON(map[string]any{"code": totpWrong(t, secret)}).
			Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("code").String().IsEqual(util.Errors.TwoFactorCodeInvalid.ErrorCode)
		// Still signs in with the passkey alone.
		if _, err := device.SignIn(); err != nil {
			t.Fatalf("sign in while pending: %v", err)
		}
	})

	var secret string
	t.Run("the secret never leaves through the collection API", func(t *testing.T) {
		secret, token = enableTotp(t, e, token)
		user := e.GET("/api/collections/users/records/"+userID).WithHeader("Authorization", token).
			Expect().Status(http.StatusOK).JSON().Object()
		user.NotContainsKey(util.Fields.User.TotpSecret)
		user.NotContainsKey(util.Fields.User.TotpPending)
		// Nor can it be cleared or replaced through it.
		e.PATCH("/api/collections/users/records/"+userID).WithHeader("Authorization", token).
			WithJSON(map[string]any{util.Fields.User.TotpSecret: "", util.Fields.User.TotpPending: "AAAA"}).
			Expect()
		e.PATCH("/api/collections/users/records/"+userID).WithHeader("Authorization", token).
			WithJSON(map[string]any{util.Fields.User.TotpEnabledAt: ""}).
			Expect().Status(http.StatusBadRequest)
		status := e.GET("/api/2fa").WithHeader("Authorization", token).
			Expect().Status(http.StatusOK).JSON().Object()
		status.Value("enabled").Boolean().IsTrue()
		status.Value("enabledAt").String().NotEmpty()
		e.POST("/api/2fa/totp/setup").WithHeader("Authorization", token).
			Expect().Status(http.StatusConflict)
	})

	t.Run("the passkey alone no longer signs in", func(t *testing.T) {
		code, verifier := passkeyCode(t, device)
		refusal := e.POST("/api/passkeys/token").WithJSON(map[string]any{"code": code, "verifier": verifier}).
			Expect().Status(http.StatusUnauthorized).JSON().Object()
		refusal.Value("code").String().IsEqual(util.Errors.TwoFactorRequired.ErrorCode)
		refusal.NotContainsKey("token")
		challenge := refusal.Value("challenge").String().NotEmpty().Raw()

		// A wrong code is refused and the challenge survives it.
		e.POST("/api/passkeys/token/2fa").WithJSON(map[string]any{"challenge": challenge, "code": totpWrong(t, secret)}).
			Expect().Status(http.StatusUnauthorized).JSON().Object().
			Value("code").String().IsEqual(util.Errors.TwoFactorCodeInvalid.ErrorCode)

		session := e.POST("/api/passkeys/token/2fa").WithJSON(map[string]any{"challenge": challenge, "code": totpNow(t, secret)}).
			Expect().Status(http.StatusOK).JSON().Object()
		session.Value("token").String().NotEmpty()
		session.Value("record").Object().Value("id").String().IsEqual(userID)
		session.Value("meta").Object().Value("passkey").Object().Value("credentialId").String().
			IsEqual(services.PasskeyCredentialID(device.Credential.ID))

		// Spent.
		e.POST("/api/passkeys/token/2fa").WithJSON(map[string]any{"challenge": challenge, "code": totpNow(t, secret)}).
			Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("code").String().IsEqual(util.Errors.TwoFactorChallengeInvalid.ErrorCode)
	})

	t.Run("a challenge allows five codes", func(t *testing.T) {
		code, verifier := passkeyCode(t, device)
		challenge := e.POST("/api/passkeys/token").WithJSON(map[string]any{"code": code, "verifier": verifier}).
			Expect().Status(http.StatusUnauthorized).JSON().Object().Value("challenge").String().Raw()
		for i := 0; i < 5; i++ {
			e.POST("/api/passkeys/token/2fa").WithJSON(map[string]any{"challenge": challenge, "code": totpWrong(t, secret)}).
				Expect().Status(http.StatusUnauthorized)
		}
		e.POST("/api/passkeys/token/2fa").WithJSON(map[string]any{"challenge": challenge, "code": totpNow(t, secret)}).
			Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("code").String().IsEqual(util.Errors.TwoFactorChallengeInvalid.ErrorCode)
	})

	t.Run("turning it off takes a current code", func(t *testing.T) {
		e.DELETE("/api/2fa/totp").WithHeader("Authorization", token).
			WithJSON(map[string]any{"code": totpWrong(t, secret)}).
			Expect().Status(http.StatusBadRequest)
		e.DELETE("/api/2fa/totp").WithHeader("Authorization", token).
			WithJSON(map[string]any{"code": totpNow(t, secret)}).
			Expect().Status(http.StatusOK).JSON().Object().Value("enabled").Boolean().IsFalse()
		if _, err := device.SignIn(); err != nil {
			t.Fatalf("sign in after turning off: %v", err)
		}
		e.DELETE("/api/2fa/totp").WithHeader("Authorization", token).
			WithJSON(map[string]any{"code": totpNow(t, secret)}).
			Expect().Status(http.StatusConflict)
	})
}

func TestTwoFactorRequiredByTheServer(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	fakeTotpClock(t)
	_, token, device, err := testutils.CreateRandomUserWithDevice(baseURL)
	if err != nil {
		t.Fatalf("user: %v", err)
	}
	e := testutils.NewExpect(t, baseURL)
	t.Setenv(util.RequireTwoFactorEnv, "true")

	t.Run("the server says so", func(t *testing.T) {
		e.GET("/api/server").Expect().Status(http.StatusOK).JSON().Object().
			Value("twoFactor").Object().Value("required").Boolean().IsTrue()
	})

	t.Run("an account without one is signed in and told to set one up", func(t *testing.T) {
		code, verifier := passkeyCode(t, device)
		session := e.POST("/api/passkeys/token").WithJSON(map[string]any{"code": code, "verifier": verifier}).
			Expect().Status(http.StatusOK).JSON().Object()
		session.Value("token").String().NotEmpty()
		session.Value("meta").Object().Value("twoFactorSetupRequired").Boolean().IsTrue()
		status := e.GET("/api/2fa").WithHeader("Authorization", token).
			Expect().Status(http.StatusOK).JSON().Object()
		status.Value("required").Boolean().IsTrue()
		status.Value("setupRequired").Boolean().IsTrue()
	})

	t.Run("it cannot be turned off", func(t *testing.T) {
		secret, token := enableTotp(t, e, token)
		e.GET("/api/2fa").WithHeader("Authorization", token).
			Expect().Status(http.StatusOK).JSON().Object().Value("setupRequired").Boolean().IsFalse()
		e.DELETE("/api/2fa/totp").WithHeader("Authorization", token).
			WithJSON(map[string]any{"code": totpNow(t, secret)}).
			Expect().Status(http.StatusForbidden).JSON().Object().
			Value("code").String().IsEqual(util.Errors.TwoFactorEnforced.ErrorCode)
	})
}

func TestTwoFactorCodeAttemptsAreLimited(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	fakeTotpClock(t)
	_, token, _, err := testutils.CreateRandomUserWithDevice(baseURL)
	if err != nil {
		t.Fatalf("user: %v", err)
	}
	e := testutils.NewExpect(t, baseURL)
	routes.ConfigureTwoFactorRateLimit(2)
	t.Cleanup(func() { routes.ConfigureTwoFactorRateLimit(0) })

	secret := e.POST("/api/2fa/totp/setup").WithHeader("Authorization", token).
		Expect().Status(http.StatusOK).JSON().Object().Value("secret").String().Raw()
	e.POST("/api/2fa/totp/confirm").WithHeader("Authorization", token).
		WithJSON(map[string]any{"code": totpWrong(t, secret)}).Expect().Status(http.StatusBadRequest)
	e.POST("/api/2fa/totp/confirm").WithHeader("Authorization", token).
		WithJSON(map[string]any{"code": totpNow(t, secret)}).Expect().Status(http.StatusTooManyRequests)
}

func TestTwoFactorOperatorReset(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	fakeTotpClock(t)
	userID, token, device, err := testutils.CreateRandomUserWithDevice(baseURL)
	if err != nil {
		t.Fatalf("user: %v", err)
	}
	e := testutils.NewExpect(t, baseURL)
	_, token = enableTotp(t, e, token)

	account, err := app.FindRecordById(util.Coll.Users, userID)
	if err != nil {
		t.Fatal(err)
	}
	reset, err := services.ResetTwoFactor(app, account.Email(), "test")
	if err != nil {
		t.Fatalf("reset: %v", err)
	}
	if !reset.Enabled || reset.UserID != userID {
		t.Fatalf("reset reported %+v", reset)
	}

	account, err = app.FindRecordById(util.Coll.Users, userID)
	if err != nil {
		t.Fatal(err)
	}
	f := util.Fields.User
	if account.GetString(f.TotpSecret) != "" || account.GetString(f.TotpPending) != "" ||
		!account.GetDateTime(f.TotpEnabledAt).IsZero() {
		t.Fatal("the reset left authenticator fields behind")
	}

	// Every session ended.
	e.GET("/api/2fa").WithHeader("Authorization", token).Expect().Status(http.StatusUnauthorized)

	// Audited.
	rows, err := app.FindRecordsByFilter(util.Coll.AuditLogs,
		util.Fields.AuditLog.RecordId+" = {:id} && "+util.Fields.AuditLog.UserAgent+" = 'test'", "", 0, 0,
		map[string]any{"id": userID})
	if err != nil || len(rows) == 0 {
		t.Fatalf("no audit entry for the reset: %v", err)
	}

	// The passkey alone signs in again.
	if _, err := device.SignIn(); err != nil {
		t.Fatalf("sign in after the reset: %v", err)
	}

	if _, err := services.ResetTwoFactor(app, "nobody-"+userID+"@example.com", "test"); err != services.ErrTwoFactorAccountMissing {
		t.Fatalf("an unknown address: %v", err)
	}
}

func TestTwoFactorCodeWorksOnce(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	fakeTotpClock(t)
	_, token, device, err := testutils.CreateRandomUserWithDevice(baseURL)
	if err != nil {
		t.Fatalf("user: %v", err)
	}
	e := testutils.NewExpect(t, baseURL)
	secret, _ := enableTotp(t, e, token)

	challenge := func() string {
		code, verifier := passkeyCode(t, device)
		return e.POST("/api/passkeys/token").WithJSON(map[string]any{"code": code, "verifier": verifier}).
			Expect().Status(http.StatusUnauthorized).JSON().Object().Value("challenge").String().Raw()
	}

	// The code that turned it on does not also sign in.
	e.POST("/api/passkeys/token/2fa").WithJSON(map[string]any{"challenge": challenge(), "code": totpAgain(t, secret)}).
		Expect().Status(http.StatusUnauthorized).JSON().Object().
		Value("code").String().IsEqual(util.Errors.TwoFactorCodeInvalid.ErrorCode)

	code := totpNow(t, secret)
	e.POST("/api/passkeys/token/2fa").WithJSON(map[string]any{"challenge": challenge(), "code": code}).
		Expect().Status(http.StatusOK)
	// Seen over a shoulder and typed again inside its window: refused.
	e.POST("/api/passkeys/token/2fa").WithJSON(map[string]any{"challenge": challenge(), "code": code}).
		Expect().Status(http.StatusUnauthorized)
	// Nor does the previous period's code, which the window would allow.
	earlier, _ := util.TotpCode(secret, totpTime().Add(-util.TotpPeriod))
	e.POST("/api/passkeys/token/2fa").WithJSON(map[string]any{"challenge": challenge(), "code": earlier}).
		Expect().Status(http.StatusUnauthorized)
	e.POST("/api/passkeys/token/2fa").WithJSON(map[string]any{"challenge": challenge(), "code": totpNow(t, secret)}).
		Expect().Status(http.StatusOK)
}

func TestTurningTwoFactorOnEndsOtherSessions(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	fakeTotpClock(t)
	_, token, device, err := testutils.CreateRandomUserWithDevice(baseURL)
	if err != nil {
		t.Fatalf("user: %v", err)
	}
	e := testutils.NewExpect(t, baseURL)
	other, err := device.SignIn()
	if err != nil {
		t.Fatalf("second session: %v", err)
	}
	e.GET("/api/2fa").WithHeader("Authorization", other.Token).Expect().Status(http.StatusOK)

	_, fresh := enableTotp(t, e, token)

	// Both sessions made with the passkey alone are over.
	e.GET("/api/2fa").WithHeader("Authorization", other.Token).Expect().Status(http.StatusUnauthorized)
	e.GET("/api/2fa").WithHeader("Authorization", token).Expect().Status(http.StatusUnauthorized)
	// The device that turned it on carries on with the session it was given.
	e.GET("/api/2fa").WithHeader("Authorization", fresh).
		Expect().Status(http.StatusOK).JSON().Object().Value("enabled").Boolean().IsTrue()
}

func TestRequiredTwoFactorHoldsTheSessionUntilSetUp(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	fakeTotpClock(t)
	userID, token, _, err := testutils.CreateRandomUserWithDevice(baseURL)
	if err != nil {
		t.Fatalf("user: %v", err)
	}
	e := testutils.NewExpect(t, baseURL)
	records := "/api/collections/" + util.Coll.Records + "/records"

	// Off: the session reaches the vault as before.
	e.GET(records).WithHeader("Authorization", token).Expect().Status(http.StatusOK)

	t.Setenv(util.RequireTwoFactorEnv, "true")
	e.GET(records).WithHeader("Authorization", token).
		Expect().Status(http.StatusForbidden).JSON().Object().
		Value("code").String().IsEqual(util.Errors.TwoFactorSetupRequired.ErrorCode)

	// What setting it up needs still works.
	e.GET("/api/2fa").WithHeader("Authorization", token).Expect().Status(http.StatusOK)
	e.GET("/api/server").WithHeader("Authorization", token).Expect().Status(http.StatusOK)
	e.GET("/api/collections/users/records/"+userID).WithHeader("Authorization", token).
		Expect().Status(http.StatusOK)
	e.POST("/api/collections/users/auth-refresh").WithHeader("Authorization", token).
		Expect().Status(http.StatusOK)

	_, fresh := enableTotp(t, e, token)
	e.GET(records).WithHeader("Authorization", fresh).Expect().Status(http.StatusOK)
}
