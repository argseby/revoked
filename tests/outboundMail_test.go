package tests

import (
	"net/http"
	"testing"

	"revoked/cmd/revoked/hooks"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// PocketBase's own mail endpoints would let anyone have this server mail an
// address of their choosing; none of them sends anything for a users account.
func TestPocketBaseMailEndpointsSendNothing(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	box := catchMail(t, app)

	email := passkeyEmail()
	device := testutils.NewPasskeyDevice(baseURL)
	session, err := device.Register(map[string]any{"email": email})
	if err != nil {
		t.Fatalf("register: %v", err)
	}

	t.Run("verification answers like an unknown address, and mails nothing", func(t *testing.T) {
		api := api.T(t)
		for _, address := range []string{email, passkeyEmail()} {
			api.Request("POST", util.Coll.Users, "/request-verification").
				WithJSON(map[string]any{"email": address}).
				Expect().Status(http.StatusNoContent)
		}
		if n := box.count(email); n != 0 {
			t.Fatalf("%d mails sent to an unverified account, want 0", n)
		}
	})

	t.Run("an email change is refused, and mails nothing", func(t *testing.T) {
		target := passkeyEmail()
		api.T(t).Request("POST", util.Coll.Users, "/request-email-change").
			WithHeader("Authorization", session.Token).
			WithJSON(map[string]any{"newEmail": target}).
			Expect().Status(http.StatusForbidden)
		if n := box.count(target); n != 0 {
			t.Fatalf("%d mails sent to the new address, want 0", n)
		}
	})

	t.Run("signing in from a new location mails nothing", func(t *testing.T) {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			t.Fatal(err)
		}
		// Every earlier sign-in now looks like it came from somewhere else.
		elsewhere := core.NewAuthOrigin(app)
		elsewhere.SetCollectionRef(users.Id)
		elsewhere.SetRecordRef(session.UserID)
		elsewhere.SetFingerprint("another-device")
		origins, _ := app.FindAllAuthOriginsByRecord(mustFindUser(t, app, session.UserID))
		for _, o := range origins {
			if err := app.Delete(o); err != nil {
				t.Fatal(err)
			}
		}
		if err := app.Save(elsewhere); err != nil {
			t.Fatal(err)
		}
		if _, err := device.SignIn(); err != nil {
			t.Fatalf("sign in: %v", err)
		}
		if n := box.count(email); n != 0 {
			t.Fatalf("%d login alerts sent, want 0", n)
		}
	})
}

// One hourly budget covers everything the server mails, so spreading requests
// over addresses and IPs cannot spend the operator's mail quota.
func TestOutboundMailIsCappedPerHour(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	box := catchMail(t, app)
	setEnvForTest(t, util.SignupVerifyEmailEnv, "true")
	hooks.ConfigureOutboundMailLimit(2)
	t.Cleanup(func() { hooks.ConfigureOutboundMailLimit(0) })

	device := testutils.NewPasskeyDevice(baseURL)
	sendCode := func(address string) error {
		return device.Post("/api/passkeys/register/email", map[string]any{"email": address}, nil)
	}

	for i := 0; i < 2; i++ {
		if err := sendCode(passkeyEmail()); err != nil {
			t.Fatalf("send code %d: %v", i+1, err)
		}
	}

	over := passkeyEmail()
	passkeyRefusal(t, sendCode(over), http.StatusTooManyRequests, util.Errors.RateLimited)
	if n := box.count(over); n != 0 {
		t.Fatalf("%d mails sent past the cap, want 0", n)
	}

	t.Run("a refused send does not cost the address its code budget", func(t *testing.T) {
		hooks.ConfigureOutboundMailLimit(0)
		if err := sendCode(over); err != nil {
			t.Fatalf("send code once the cap lifts: %v", err)
		}
		if n := box.count(over); n != 1 {
			t.Fatalf("%d mails sent, want 1", n)
		}
	})
}

func mustFindUser(t *testing.T, app core.App, id string) *core.Record {
	t.Helper()
	record, err := app.FindRecordById(util.Coll.Users, id)
	if err != nil {
		t.Fatal(err)
	}
	return record
}
