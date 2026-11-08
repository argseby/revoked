package util

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"crypto/subtle"
	"encoding/base32"
	"encoding/binary"
	"fmt"
	"net/url"
	"os"
	"strings"
	"time"
)

// RequireTwoFactorEnv makes an authenticator app mandatory for every account
// on this server.
const RequireTwoFactorEnv = "REQUIRE_2FA"

const (
	// TotpDigits, TotpPeriod and TotpSkew are RFC 6238 as every authenticator
	// app reads an otpauth URI without parameters: SHA-1, six digits, thirty
	// seconds, and one step either side for a clock that is slightly off.
	TotpDigits = 6
	TotpPeriod = 30 * time.Second
	TotpSkew   = 1

	// TotpSecretBytes is the secret's length: 160 bits, as RFC 4226 recommends
	// for HMAC-SHA1.
	TotpSecretBytes = 20

	// TwoFactorChallengeTTL is how long a passkey sign-in waits for the code
	// from the authenticator app.
	TwoFactorChallengeTTL = 5 * time.Minute

	// TotpIssuer names the server in the authenticator app's list.
	TotpIssuer = "Revoked"
)

// TwoFactorRequired reports whether this server requires every account to
// have an authenticator app.
//
// Off unless explicitly enabled. With it on, an account without one is still
// signed in by its passkey — the app then asks for one to be set up before
// anything else — and an account cannot turn its own off.
func TwoFactorRequired() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(RequireTwoFactorEnv))) {
	case "1", "true", "yes":
		return true
	default:
		return false
	}
}

var totpEncoding = base32.StdEncoding.WithPadding(base32.NoPadding)

// NewTotpSecret returns a fresh random secret, base32 without padding, the
// form authenticator apps take.
func NewTotpSecret() (string, error) {
	raw := make([]byte, TotpSecretBytes)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	return totpEncoding.EncodeToString(raw), nil
}

// TotpURI is the otpauth:// URI an authenticator app scans: the issuer and
// account name the person sees there, and the secret.
func TotpURI(secret, account string) string {
	label := url.PathEscape(TotpIssuer + ":" + account)
	q := url.Values{}
	q.Set("secret", secret)
	q.Set("issuer", TotpIssuer)
	q.Set("algorithm", "SHA1")
	q.Set("digits", fmt.Sprint(TotpDigits))
	q.Set("period", fmt.Sprint(int(TotpPeriod/time.Second)))
	return "otpauth://totp/" + label + "?" + q.Encode()
}

func decodeTotpSecret(secret string) ([]byte, bool) {
	s := strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(secret), " ", ""))
	s = strings.TrimRight(s, "=")
	raw, err := totpEncoding.DecodeString(s)
	if err != nil || len(raw) == 0 {
		return nil, false
	}
	return raw, true
}

// hotp is RFC 4226 with SHA-1, truncated to digits.
func hotp(key []byte, counter uint64, digits int) string {
	var msg [8]byte
	binary.BigEndian.PutUint64(msg[:], counter)
	mac := hmac.New(sha1.New, key)
	mac.Write(msg[:])
	sum := mac.Sum(nil)
	offset := sum[len(sum)-1] & 0x0f
	code := binary.BigEndian.Uint32(sum[offset:offset+4]) & 0x7fffffff
	mod := uint32(1)
	for i := 0; i < digits; i++ {
		mod *= 10
	}
	return fmt.Sprintf("%0*d", digits, code%mod)
}

// totpAt is the code for raw key at t with the given number of digits.
func totpAt(key []byte, t time.Time, digits int) string {
	return hotp(key, uint64(t.Unix())/uint64(TotpPeriod/time.Second), digits)
}

// TotpCode is the six-digit code for secret at t. It reports !ok for a secret
// that is not base32.
func TotpCode(secret string, t time.Time) (string, bool) {
	key, ok := decodeTotpSecret(secret)
	if !ok {
		return "", false
	}
	return totpAt(key, t, TotpDigits), true
}

// NormalizeTotpCode strips the spaces and dashes people type or paste into a
// code. It reports !ok unless exactly TotpDigits digits remain.
func NormalizeTotpCode(code string) (string, bool) {
	var b strings.Builder
	for _, r := range code {
		switch {
		case r >= '0' && r <= '9':
			b.WriteRune(r)
		case r == ' ' || r == '-' || r == '\t':
		default:
			return "", false
		}
	}
	out := b.String()
	return out, len(out) == TotpDigits
}

// VerifyTotp reports whether code is the code for secret at now, or one step
// before or after it.
func VerifyTotp(secret, code string, now time.Time) bool {
	_, ok := MatchTotp(secret, code, now)
	return ok
}

// MatchTotp is VerifyTotp that also says which time step the code belongs to,
// so a caller can refuse a code that was already used: within its window, a
// code seen over someone's shoulder would otherwise work a second time.
func MatchTotp(secret, code string, now time.Time) (int64, bool) {
	key, ok := decodeTotpSecret(secret)
	if !ok {
		return 0, false
	}
	code, ok = NormalizeTotpCode(code)
	if !ok {
		return 0, false
	}
	current := now.Unix() / int64(TotpPeriod/time.Second)
	var matched int64
	found := 0
	for step := -TotpSkew; step <= TotpSkew; step++ {
		counter := current + int64(step)
		want := hotp(key, uint64(counter), TotpDigits)
		// Every step compared, so the time taken says nothing of which matched.
		hit := subtle.ConstantTimeCompare([]byte(want), []byte(code))
		if hit == 1 && found == 0 {
			matched = counter
		}
		found |= hit
	}
	return matched, found == 1
}
