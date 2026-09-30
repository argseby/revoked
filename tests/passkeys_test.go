package tests

import (
	"errors"
	"fmt"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"revoked/cmd/revoked/services"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/google/uuid"
)

func passkeyEmail() string {
	return fmt.Sprintf("passkey-%s@example.com", uuid.New().String()[:8])
}

func passkeyRefusal(t *testing.T, err error, status int, want util.AppError) {
	t.Helper()
	var refusal *testutils.PasskeyError
	if !errors.As(err, &refusal) || refusal.Status != status || refusal.Code != want.ErrorCode {
		t.Fatalf("want %d %s, got %v", status, want.ErrorCode, err)
	}
}

func TestSigningInWithAPasskey(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	email := passkeyEmail()
	device := testutils.NewPasskeyDevice(baseURL)

	created, err := device.Register(map[string]any{"email": email})
	if err != nil {
		t.Fatalf("register: %v", err)
	}

	t.Run("the passkey signs its account in, without naming it", func(t *testing.T) {
		api := api.T(t)
		session, err := device.SignIn()
		if err != nil {
			t.Fatalf("sign in: %v", err)
		}
		if session.UserID != created.UserID {
			t.Fatalf("signed in as %s, registered as %s", session.UserID, created.UserID)
		}
		api.Get(util.Coll.Users, session.UserID, session.Token).Expect().Status(http.StatusOK).
			JSON().Object().Value("email").String().IsEqual(email)
	})

	t.Run("an address is one account", func(t *testing.T) {
		_, err := testutils.NewPasskeyDevice(baseURL).Register(map[string]any{"email": strings.ToUpper(email)})
		passkeyRefusal(t, err, http.StatusConflict, util.Errors.PasskeyEmailTaken)
		_, err = testutils.NewPasskeyDevice(baseURL).Register(map[string]any{"email": "not an address"})
		passkeyRefusal(t, err, http.StatusBadRequest, util.Errors.PasskeyEmailInvalid)
	})

	t.Run("a code works once, and only with its verifier", func(t *testing.T) {
		code, err := device.SignInCode(util.PKCEChallenge(strings.Repeat("a", 43)))
		if err != nil {
			t.Fatalf("sign in: %v", err)
		}
		_, err = device.Exchange(code, strings.Repeat("b", 43))
		passkeyRefusal(t, err, http.StatusBadRequest, util.Errors.PasskeyGrantInvalid)
		// Spent by the wrong attempt: the right verifier no longer helps.
		_, err = device.Exchange(code, strings.Repeat("a", 43))
		passkeyRefusal(t, err, http.StatusBadRequest, util.Errors.PasskeyGrantInvalid)
	})

	t.Run("another account's passkey is not this one's", func(t *testing.T) {
		other := testutils.NewPasskeyDevice(baseURL)
		session, err := other.Register(map[string]any{"email": passkeyEmail()})
		if err != nil {
			t.Fatalf("register: %v", err)
		}
		if session.UserID == created.UserID {
			t.Fatal("two registrations share an account")
		}
		// A device that answers with a key the server never saw is refused.
		stranger := testutils.NewPasskeyDevice(baseURL)
		stranger.Authenticator, stranger.Credential = device.Authenticator, other.Credential
		_, err = stranger.SignIn()
		passkeyRefusal(t, err, http.StatusUnauthorized, util.Errors.PasskeyVerificationFailed)
	})

	t.Run("there is no password to sign in with, and no account without a passkey", func(t *testing.T) {
		api := api.T(t)
		api.Request("POST", util.Coll.Users, "/auth-with-password").WithJSON(map[string]any{
			"identity": email, "password": "password12345",
		}).Expect().Status(http.StatusForbidden)
		api.AssertStatus(api.Create(util.Coll.Users, "", map[string]any{
			"email": passkeyEmail(), "password": "password12345", "passwordConfirm": "password12345",
		}), http.StatusForbidden).JSON().Object().Value("data").Object().
			Value("signup").Object().Value("code").String().IsEqual(util.Errors.PasskeySignupOnly.ErrorCode)
	})

	t.Run("a passkey only works at the server's own address", func(t *testing.T) {
		api := api.T(t)
		// The suite's own address is a loopback IP, which nothing can be bound to.
		api.E.POST("/api/passkeys/login/begin").
			WithJSON(map[string]any{"challenge": util.PKCEChallenge(strings.Repeat("a", 43))}).
			Expect().Status(http.StatusBadRequest).
			JSON().Object().Value("code").String().IsEqual(util.Errors.PasskeyOriginInvalid.ErrorCode)
	})
}

func TestAddingAndRemovingPasskeys(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	first := testutils.NewPasskeyDevice(baseURL)
	owner, err := first.Register(map[string]any{"email": passkeyEmail()})
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	list := func(api *testutils.PBClient) []any {
		return api.List(util.Coll.Passkeys, owner.Token).Expect().Status(http.StatusOK).
			JSON().Object().Value("items").Array().Raw()
	}

	t.Run("the owner sees their passkeys, never the key material", func(t *testing.T) {
		items := list(api.T(t))
		if len(items) != 1 {
			t.Fatalf("%d passkeys, want 1", len(items))
		}
		row := items[0].(map[string]any)
		if row["name"] != "Test device" {
			t.Errorf("name = %v", row["name"])
		}
		if _, leaked := row[util.Fields.Passkey.Credential]; leaked {
			t.Error("the credential is exposed")
		}
		// Nobody else's.
		_, stranger, _ := testutils.CreateRandomUser(baseURL)
		api.T(t).List(util.Coll.Passkeys, stranger).Expect().Status(http.StatusOK).
			JSON().Object().Value("items").Array().Length().IsEqual(1)
	})

	t.Run("the only passkey cannot be removed", func(t *testing.T) {
		api := api.T(t)
		id := list(api)[0].(map[string]any)["id"].(string)
		api.E.DELETE("/api/passkeys/"+id).WithHeader("Authorization", owner.Token).
			Expect().Status(http.StatusConflict).
			JSON().Object().Value("code").String().IsEqual(util.Errors.PasskeyLast.ErrorCode)
		// Nor through the collection.
		api.AssertStatus(api.Delete(util.Coll.Passkeys, id, owner.Token), http.StatusForbidden)
	})

	var second *testutils.PasskeyDevice
	t.Run("a signed-in person adds a device with a one-time link", func(t *testing.T) {
		api := api.T(t)
		api.E.POST("/api/passkeys/tickets").Expect().Status(http.StatusUnauthorized)
		link := api.E.POST("/api/passkeys/tickets").WithHeader("Authorization", owner.Token).
			Expect().Status(http.StatusOK).JSON().Object().Value("url").String().Raw()
		if !strings.Contains(link, util.PasskeyPagePath+"?mode=enroll&ticket=") {
			t.Fatalf("link = %s", link)
		}
		ticket := link[strings.Index(link, "ticket=")+len("ticket="):]

		second = testutils.NewPasskeyDevice(baseURL)
		session, err := second.Register(map[string]any{"ticket": ticket})
		if err != nil {
			t.Fatalf("redeem ticket: %v", err)
		}
		if session.UserID != owner.UserID {
			t.Fatalf("the ticket registered %s, not its owner %s", session.UserID, owner.UserID)
		}
		// Spent.
		_, err = testutils.NewPasskeyDevice(baseURL).Register(map[string]any{"ticket": ticket})
		passkeyRefusal(t, err, http.StatusBadRequest, util.Errors.PasskeyTicketInvalid)
		if _, err := second.SignIn(); err != nil {
			t.Fatalf("the new device cannot sign in: %v", err)
		}
	})

	t.Run("with two, one can go, and stops working", func(t *testing.T) {
		api := api.T(t)
		items := list(api)
		if len(items) != 2 {
			t.Fatalf("%d passkeys, want 2", len(items))
		}
		// A stranger cannot remove either.
		_, stranger, _ := testutils.CreateRandomUser(baseURL)
		var removed bool
		for _, item := range items {
			row := item.(map[string]any)
			id := row["id"].(string)
			api.E.DELETE("/api/passkeys/"+id).WithHeader("Authorization", stranger).
				Expect().Status(http.StatusNotFound)
			// Remove the first device's: it is the one never used to sign in.
			if row["lastUsedAt"] == "" && !removed {
				api.E.DELETE("/api/passkeys/"+id).WithHeader("Authorization", owner.Token).
					Expect().Status(http.StatusNoContent)
				removed = true
			}
		}
		if !removed {
			t.Fatal("no unused passkey to remove")
		}
		_, err := first.SignIn()
		passkeyRefusal(t, err, http.StatusUnauthorized, util.Errors.PasskeyVerificationFailed)
		if _, err := second.SignIn(); err != nil {
			t.Fatalf("the remaining passkey stopped working: %v", err)
		}
	})

	t.Run("the operator lets an account in where signups are closed", func(t *testing.T) {
		previous := os.Getenv(util.AllowSignupsEnv)
		t.Cleanup(func() { _ = os.Setenv(util.AllowSignupsEnv, previous) })
		_ = os.Setenv(util.AllowSignupsEnv, "false")

		email := passkeyEmail()
		account, created, err := services.EnsurePasskeyAccount(app, email)
		if err != nil || !created {
			t.Fatalf("ensure account: created=%v err=%v", created, err)
		}
		ticket, _, err := services.IssuePasskeyTicket(app, account.Id, time.Hour)
		if err != nil {
			t.Fatalf("issue ticket: %v", err)
		}
		device := testutils.NewPasskeyDevice(baseURL)
		session, err := device.Register(map[string]any{"ticket": ticket})
		if err != nil {
			t.Fatalf("redeem ticket: %v", err)
		}
		if session.UserID != account.Id {
			t.Fatalf("registered %s, want %s", session.UserID, account.Id)
		}

		// A ticket that ran out is worth nothing.
		stale, _, err := services.IssuePasskeyTicket(app, account.Id, -time.Minute)
		if err != nil {
			t.Fatalf("issue ticket: %v", err)
		}
		_, err = testutils.NewPasskeyDevice(baseURL).Register(map[string]any{"ticket": stale})
		passkeyRefusal(t, err, http.StatusBadRequest, util.Errors.PasskeyTicketInvalid)
	})
}

func TestThePasskeyPage(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	resp := api.E.GET(util.PasskeyPagePath).WithQuery("mode", "signin").Expect().Status(http.StatusOK)
	resp.Header("Content-Type").Contains("text/html")
	csp := resp.Header("Content-Security-Policy").Raw()
	for _, want := range []string{"default-src 'none'", "connect-src 'self'", "frame-ancestors 'none'", "script-src 'nonce-"} {
		if !strings.Contains(csp, want) {
			t.Errorf("CSP lacks %q: %s", want, csp)
		}
	}
	// A ticket in the address is never echoed into the page.
	body := api.E.GET(util.PasskeyPagePath).WithQuery("ticket", "<script>alert(1)</script>").
		Expect().Status(http.StatusOK).Body().Raw()
	if strings.Contains(body, "alert(1)") {
		t.Error("the page reflects its query")
	}
}
