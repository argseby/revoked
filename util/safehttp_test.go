package util

import (
	"errors"
	"testing"
)

// The callback policy is invariant #6: default-deny for anything a forged
// callback could reach. ALLOW_PRIVATE_CALLBACKS widens it to loopback and
// private ranges — and to nothing else.
func TestCallbackPolicyDefaultDeny(t *testing.T) {
	for _, raw := range []string{
		"http://127.0.0.1:8000/hook",
		"http://10.0.0.5/hook",
		"http://192.168.1.20:9000/hook",
		"http://169.254.169.254/latest/meta-data/",
		"http://0.0.0.0/hook",
		"ftp://example.com/hook",
		"example.com/hook",
	} {
		if err := ValidateCallbackURL(raw); !errors.Is(err, ErrCallbackURLBlocked) {
			t.Errorf("%s: expected blocked, got %v", raw, err)
		}
	}
	if err := ValidateCallbackURL("https://hooks.example.com/x"); err != nil {
		t.Errorf("public https target should pass, got %v", err)
	}
}

func TestCallbackPolicyOperatorOptIn(t *testing.T) {
	t.Setenv(AllowPrivateCallbacksEnv, "true")

	for _, raw := range []string{
		"http://127.0.0.1:8000/hook",
		"http://192.168.1.20:9000/hook",
	} {
		if err := ValidateCallbackURL(raw); err != nil {
			t.Errorf("%s: flag should permit it, got %v", raw, err)
		}
	}

	// The flag must never open the metadata endpoint or the wildcard address.
	for _, raw := range []string{
		"http://169.254.169.254/latest/meta-data/",
		"http://0.0.0.0/hook",
	} {
		if err := ValidateCallbackURL(raw); !errors.Is(err, ErrCallbackURLBlocked) {
			t.Errorf("%s: must stay blocked under the flag, got %v", raw, err)
		}
	}
}
