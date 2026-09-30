package tests

import (
	"errors"
	"fmt"
	"net/http"
	"os"
	"revoked/tests/testutils"

	"revoked/util"
	"testing"
	"time"
)

// Self-service registration is refused unless the operator opts in. The
// default matters: a server nobody configured should be one only its operator
// can add people to, not one the internet can.
func TestSignups_DisabledByDefault(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)

	// The harness enables signups for the rest of the suite; this case is about
	// what happens when an operator has not.
	previous := os.Getenv(util.AllowSignupsEnv)
	t.Cleanup(func() { _ = os.Setenv(util.AllowSignupsEnv, previous) })

	register := func() error {
		_, err := testutils.NewPasskeyDevice(baseURL).Register(map[string]any{
			"email": fmt.Sprintf("signup-%d@test.com", time.Now().UnixNano()),
		})
		return err
	}
	refused := func(t *testing.T, err error) {
		t.Helper()
		var refusal *testutils.PasskeyError
		if !errors.As(err, &refusal) || refusal.Status != http.StatusForbidden ||
			refusal.Code != util.Errors.SignupsDisabled.ErrorCode {
			t.Fatalf("registration was not refused as signups_disabled: %v", err)
		}
	}

	t.Run("unset refuses the registration", func(t *testing.T) {
		_ = os.Unsetenv(util.AllowSignupsEnv)
		refused(t, register())
	})

	t.Run("an explicit false refuses it too", func(t *testing.T) {
		_ = os.Setenv(util.AllowSignupsEnv, "false")
		refused(t, register())
	})

	t.Run("opting in accepts it", func(t *testing.T) {
		_ = os.Setenv(util.AllowSignupsEnv, "true")
		if err := register(); err != nil {
			t.Fatalf("registration refused: %v", err)
		}
	})
}
