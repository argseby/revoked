package tests

import (
	"fmt"
	"net/http"
	"os"
	"revoked/tests/testutils"

	"github.com/gavv/httpexpect/v2"
	"revoked/util"
	"testing"
	"time"
)

// Self-service registration is refused unless the operator opts in. The
// default matters: a server nobody configured should be one only its operator
// can add people to, not one the internet can.
func TestSignups_DisabledByDefault(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	// The harness enables signups for the rest of the suite; this case is about
	// what happens when an operator has not.
	previous := os.Getenv(util.AllowSignupsEnv)
	t.Cleanup(func() { _ = os.Setenv(util.AllowSignupsEnv, previous) })

	register := func(api *testutils.PBClient) *httpexpect.Request {
		return api.Create(util.Coll.Users, "", map[string]any{
			"email":           fmt.Sprintf("signup-%d@test.com", time.Now().UnixNano()),
			"password":        "password12345",
			"passwordConfirm": "password12345",
		})
	}

	t.Run("unset refuses the registration", func(t *testing.T) {
		_ = os.Unsetenv(util.AllowSignupsEnv)
		api := api.T(t)
		body := api.AssertStatus(register(api), http.StatusForbidden)
		body.JSON().Object().Value("data").Object().
			Value("signup").Object().Value("code").String().
			IsEqual(util.Errors.SignupsDisabled.ErrorCode)
	})

	t.Run("an explicit false refuses it too", func(t *testing.T) {
		_ = os.Setenv(util.AllowSignupsEnv, "false")
		api := api.T(t)
		api.AssertStatus(register(api), http.StatusForbidden)
	})

	t.Run("opting in accepts it", func(t *testing.T) {
		_ = os.Setenv(util.AllowSignupsEnv, "true")
		api := api.T(t)
		api.AssertStatus(register(api), http.StatusOK)
	})
}
