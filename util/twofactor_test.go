package util

import (
	"encoding/base32"
	"strings"
	"testing"
	"time"
)

// RFC 6238 Appendix B, SHA-1 rows: the ASCII key "12345678901234567890" and
// eight-digit codes.
func TestTotpRFC6238Vectors(t *testing.T) {
	key := []byte("12345678901234567890")
	cases := []struct {
		unix int64
		want string
	}{
		{59, "94287082"},
		{1111111109, "07081804"},
		{1111111111, "14050471"},
		{1234567890, "89005924"},
		{2000000000, "69279037"},
		{20000000000, "65353130"},
	}
	for _, c := range cases {
		if got := totpAt(key, time.Unix(c.unix, 0), 8); got != c.want {
			t.Errorf("T=%d: got %s, want %s", c.unix, got, c.want)
		}
		// The six-digit code is the same value's last six digits.
		secret := base32.StdEncoding.EncodeToString(key)
		got, ok := TotpCode(secret, time.Unix(c.unix, 0))
		if !ok || got != c.want[2:] {
			t.Errorf("T=%d six digits: got %s, want %s", c.unix, got, c.want[2:])
		}
	}
}

func TestVerifyTotpWindow(t *testing.T) {
	secret, err := NewTotpSecret()
	if err != nil {
		t.Fatal(err)
	}
	if len(secret) != 32 || strings.Contains(secret, "=") {
		t.Fatalf("secret %q: want 32 base32 characters without padding", secret)
	}
	now := time.Unix(1_700_000_000, 0)
	code, ok := TotpCode(secret, now)
	if !ok {
		t.Fatal("secret did not decode")
	}
	for _, at := range []time.Duration{-TotpPeriod, 0, TotpPeriod} {
		if !VerifyTotp(secret, code, now.Add(at)) {
			t.Errorf("code refused at offset %v", at)
		}
	}
	for _, at := range []time.Duration{-2 * TotpPeriod, 2 * TotpPeriod} {
		if VerifyTotp(secret, code, now.Add(at)) {
			t.Errorf("code accepted at offset %v", at)
		}
	}
	if !VerifyTotp(secret, code[:3]+" "+code[3:], now) {
		t.Error("a code typed with a space was refused")
	}
	if !VerifyTotp(strings.ToLower(secret), code, now) {
		t.Error("a lower-case secret was refused")
	}
	for _, bad := range []string{"", "12345", "1234567", "abcdef", code + "0"} {
		if VerifyTotp(secret, bad, now) {
			t.Errorf("code %q accepted", bad)
		}
	}
	if VerifyTotp("not base32!", code, now) {
		t.Error("an invalid secret verified")
	}
}

func TestTotpURI(t *testing.T) {
	uri := TotpURI("JBSWY3DPEHPK3PXP", "ana@example.com")
	for _, part := range []string{
		"otpauth://totp/Revoked:ana@example.com?",
		"secret=JBSWY3DPEHPK3PXP",
		"issuer=Revoked",
		"digits=6",
		"period=30",
		"algorithm=SHA1",
	} {
		if !strings.Contains(uri, part) {
			t.Errorf("%s: missing %s", uri, part)
		}
	}
}

func TestTwoFactorRequired(t *testing.T) {
	for value, want := range map[string]bool{"": false, "false": false, "0": false, "true": true, "1": true, "YES": true} {
		t.Setenv(RequireTwoFactorEnv, value)
		if got := TwoFactorRequired(); got != want {
			t.Errorf("%q: got %v, want %v", value, got, want)
		}
	}
}

func TestMatchTotpSaysWhichStep(t *testing.T) {
	secret, err := NewTotpSecret()
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1_800_000_000, 0)
	current := now.Unix() / int64(TotpPeriod/time.Second)
	for offset := -TotpSkew; offset <= TotpSkew; offset++ {
		code, _ := TotpCode(secret, now.Add(time.Duration(offset)*TotpPeriod))
		step, ok := MatchTotp(secret, code, now)
		if !ok || step != current+int64(offset) {
			t.Fatalf("offset %d: step %d ok %v, want %d", offset, step, ok, current+int64(offset))
		}
	}
	if _, ok := MatchTotp(secret, "000000x", now); ok {
		t.Fatal("a malformed code matched")
	}
}
