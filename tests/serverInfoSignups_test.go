package tests

import (
	"net/http"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"
)

// The app tells someone how many steps creating an account takes before it
// opens the passkey page, so the public server info carries the same two
// facts the page is rendered with: whether sign-ups are open, and whether a
// new account confirms its address with a mailed code.
func TestServerInfoSaysHowSignupWorks(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	for _, c := range []struct {
		signups, verify string
		open, code      bool
	}{
		{signups: "true", verify: "true", open: true, code: true},
		{signups: "true", verify: "false", open: true, code: false},
		{signups: "false", verify: "false", open: false, code: false},
	} {
		t.Setenv(util.AllowSignupsEnv, c.signups)
		t.Setenv(util.SignupVerifyEmailEnv, c.verify)

		signups := api.E.GET("/api/server").Expect().Status(http.StatusOK).
			JSON().Object().Value("signups").Object()
		signups.Value("open").Boolean().IsEqual(c.open)
		signups.Value("verifyEmail").Boolean().IsEqual(c.code)
	}
}
