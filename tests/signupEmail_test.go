package tests

import (
	"net/http"
	"os"
	"regexp"
	"sync"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/hook"
)

// mailbox catches what the server mails instead of sending it.
type mailbox struct {
	mu   sync.Mutex
	sent map[string][]string // address -> subjects
}

func catchMail(t *testing.T, app *pocketbase.PocketBase) *mailbox {
	t.Helper()
	box := &mailbox{sent: map[string][]string{}}
	id := app.OnMailerSend().Bind(&hook.Handler[*core.MailerEvent]{
		Func: func(e *core.MailerEvent) error {
			box.mu.Lock()
			defer box.mu.Unlock()
			for _, to := range e.Message.To {
				box.sent[to.Address] = append(box.sent[to.Address], e.Message.Subject)
			}
			// Not e.Next(): nothing leaves the test machine.
			return nil
		},
	})
	t.Cleanup(func() { app.OnMailerSend().Unbind(id) })
	return box
}

var mailedCode = regexp.MustCompile(`\b[0-9]{6}\b`)

// code is the last confirmation code mailed to address.
func (b *mailbox) code(t *testing.T, address string) string {
	t.Helper()
	b.mu.Lock()
	defer b.mu.Unlock()
	subjects := b.sent[address]
	if len(subjects) == 0 {
		t.Fatalf("nothing was mailed to %s", address)
	}
	code := mailedCode.FindString(subjects[len(subjects)-1])
	if code == "" {
		t.Fatalf("no code in %q", subjects[len(subjects)-1])
	}
	return code
}

func (b *mailbox) count(address string) int {
	b.mu.Lock()
	defer b.mu.Unlock()
	return len(b.sent[address])
}

func setEnvForTest(t *testing.T, name, value string) {
	t.Helper()
	previous, had := os.LookupEnv(name)
	_ = os.Setenv(name, value)
	t.Cleanup(func() {
		if had {
			_ = os.Setenv(name, previous)
		} else {
			_ = os.Unsetenv(name)
		}
	})
}

// wrongCode is a well-formed code other than code.
func wrongCode(code string) string {
	if code == "000000" {
		return "111111"
	}
	return "000000"
}

// Where the operator asks for it, an address is confirmed with a mailed code
// before an account is made for it: anyone can type any address, and only its
// owner can read the code.
func TestSignupConfirmsTheEmailAddress(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	box := catchMail(t, app)
	setEnvForTest(t, util.SignupVerifyEmailEnv, "true")

	device := testutils.NewPasskeyDevice(baseURL)
	email := passkeyEmail()

	sendCode := func(address string) error {
		return device.Post("/api/passkeys/register/email", map[string]any{"email": address}, nil)
	}
	verify := func(address, code string) (string, error) {
		var out struct {
			Proof string `json:"proof"`
		}
		err := device.Post("/api/passkeys/register/verify", map[string]any{"email": address, "code": code}, &out)
		return out.Proof, err
	}

	t.Run("no account without a confirmed address", func(t *testing.T) {
		_, err := testutils.NewPasskeyDevice(baseURL).Register(map[string]any{"email": email})
		passkeyRefusal(t, err, http.StatusForbidden, util.Errors.EmailVerificationRequired)
		_, err = testutils.NewPasskeyDevice(baseURL).Register(map[string]any{"email": email, "proof": "made-up"})
		passkeyRefusal(t, err, http.StatusForbidden, util.Errors.EmailVerificationRequired)
	})

	if err := sendCode(email); err != nil {
		t.Fatalf("send code: %v", err)
	}
	code := box.code(t, email)

	t.Run("a second code waits a minute", func(t *testing.T) {
		passkeyRefusal(t, sendCode(email), http.StatusTooManyRequests, util.Errors.EmailCodeTooSoon)
		if n := box.count(email); n != 1 {
			t.Fatalf("%d mails sent, want 1", n)
		}
	})

	t.Run("a wrong code buys nothing", func(t *testing.T) {
		_, err := verify(email, wrongCode(code))
		passkeyRefusal(t, err, http.StatusBadRequest, util.Errors.EmailCodeInvalid)
		_, err = verify(passkeyEmail(), code)
		passkeyRefusal(t, err, http.StatusBadRequest, util.Errors.EmailCodeInvalid)
	})

	proof, err := verify(email, code)
	if err != nil || proof == "" {
		t.Fatalf("verify: %v", err)
	}

	t.Run("the code works once", func(t *testing.T) {
		_, err := verify(email, code)
		passkeyRefusal(t, err, http.StatusBadRequest, util.Errors.EmailCodeInvalid)
	})

	t.Run("the proof is for its own address only", func(t *testing.T) {
		_, err := testutils.NewPasskeyDevice(baseURL).Register(map[string]any{"email": passkeyEmail(), "proof": proof})
		passkeyRefusal(t, err, http.StatusForbidden, util.Errors.EmailVerificationRequired)
	})

	t.Run("the confirmed address gets a verified account, once", func(t *testing.T) {
		api := api.T(t)
		session, err := device.Register(map[string]any{"email": email, "proof": proof})
		if err != nil {
			t.Fatalf("register: %v", err)
		}
		api.Get(util.Coll.Users, session.UserID, session.Token).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.User.Verified).Boolean().IsTrue()

		other := passkeyEmail()
		_, err = testutils.NewPasskeyDevice(baseURL).Register(map[string]any{"email": other, "proof": proof})
		passkeyRefusal(t, err, http.StatusForbidden, util.Errors.EmailVerificationRequired)
		// And the address is now taken, so no code is sent for it.
		passkeyRefusal(t, sendCode(email), http.StatusConflict, util.Errors.PasskeyEmailTaken)
	})

	t.Run("guessing costs the code", func(t *testing.T) {
		address := passkeyEmail()
		if err := sendCode(address); err != nil {
			t.Fatalf("send code: %v", err)
		}
		right := box.code(t, address)
		for i := 0; i < util.EmailCodeAttempts; i++ {
			_, err := verify(address, wrongCode(right))
			passkeyRefusal(t, err, http.StatusBadRequest, util.Errors.EmailCodeInvalid)
		}
		_, err := verify(address, right)
		passkeyRefusal(t, err, http.StatusBadRequest, util.Errors.EmailCodeInvalid)
	})

	t.Run("nothing is mailed to an address that is not one", func(t *testing.T) {
		passkeyRefusal(t, sendCode("not an address"), http.StatusBadRequest, util.Errors.PasskeyEmailInvalid)
	})

	t.Run("without the setting there is nothing to confirm", func(t *testing.T) {
		setEnvForTest(t, util.SignupVerifyEmailEnv, "false")
		passkeyRefusal(t, sendCode(passkeyEmail()), http.StatusBadRequest, util.Errors.EmailVerificationOff)
		session, err := testutils.NewPasskeyDevice(baseURL).Register(map[string]any{"email": passkeyEmail()})
		if err != nil {
			t.Fatalf("register: %v", err)
		}
		api.T(t).Get(util.Coll.Users, session.UserID, session.Token).Expect().Status(http.StatusOK).
			JSON().Object().Value(util.Fields.User.Verified).Boolean().IsFalse()
	})

	t.Run("with signups off nothing is mailed", func(t *testing.T) {
		setEnvForTest(t, util.AllowSignupsEnv, "false")
		passkeyRefusal(t, sendCode(passkeyEmail()), http.StatusForbidden, util.Errors.SignupsDisabled)
	})
}
