package util

import (
	"os"
	"strconv"
	"strings"
	"time"
)

// Outbound mail, configured from the environment. PocketBase keeps its own
// SMTP settings in the database; these override them at every boot, so the
// .env stays the one place an operator looks.
const (
	SMTPHostEnv          = "SMTP_HOST"
	SMTPPortEnv          = "SMTP_PORT"
	SMTPUsernameEnv      = "SMTP_USERNAME"
	SMTPPasswordEnv      = "SMTP_PASSWORD"
	SMTPTLSEnv           = "SMTP_TLS"
	SMTPAuthMethodEnv    = "SMTP_AUTH_METHOD"
	SMTPSenderAddressEnv = "SMTP_SENDER_ADDRESS"
	SMTPSenderNameEnv    = "SMTP_SENDER_NAME"

	// SignupVerifyEmailEnv makes a new account confirm its address with a
	// code sent there before its passkey is registered.
	SignupVerifyEmailEnv = "SIGNUP_VERIFY_EMAIL"
)

const (
	// EmailCodeLength is how many digits a confirmation code has.
	EmailCodeLength = 6

	// EmailCodeTTL is how long a code may wait to be typed in.
	EmailCodeTTL = 10 * time.Minute

	// EmailCodeAttempts is how many wrong guesses a code survives. With a
	// million codes and a handful of codes an hour per address, guessing is
	// not a way in.
	EmailCodeAttempts = 5

	// EmailCodeResendAfter is how long an address waits between codes.
	EmailCodeResendAfter = time.Minute

	// EmailCodesPerHour is how many codes one address may be sent in an hour,
	// whoever asks: the server must not become a way to flood an inbox.
	EmailCodesPerHour = 5

	// EmailProofTTL is how long a confirmed address may wait for its passkey:
	// the registration that follows, including a dismissed system sheet or two.
	EmailProofTTL = 15 * time.Minute
)

// SMTPConfig is the outbound mail server named in the environment.
type SMTPConfig struct {
	Host, Username, Password, AuthMethod string
	Port                                 int
	TLS                                  bool
	SenderAddress, SenderName            string
}

// SMTPFromEnv reads the mail server from the environment; ok is false when
// SMTP_HOST is unset, which leaves PocketBase's own settings alone.
func SMTPFromEnv() (cfg SMTPConfig, ok bool) {
	cfg.Host = strings.TrimSpace(os.Getenv(SMTPHostEnv))
	if cfg.Host == "" {
		return cfg, false
	}
	cfg.TLS = envTrue(SMTPTLSEnv)
	cfg.Port = 587
	if cfg.TLS {
		cfg.Port = 465
	}
	if p, err := strconv.Atoi(strings.TrimSpace(os.Getenv(SMTPPortEnv))); err == nil && p > 0 {
		cfg.Port = p
	}
	cfg.Username = os.Getenv(SMTPUsernameEnv)
	cfg.Password = os.Getenv(SMTPPasswordEnv)
	cfg.AuthMethod = strings.ToUpper(strings.TrimSpace(os.Getenv(SMTPAuthMethodEnv)))
	cfg.SenderAddress = strings.TrimSpace(os.Getenv(SMTPSenderAddressEnv))
	cfg.SenderName = strings.TrimSpace(os.Getenv(SMTPSenderNameEnv))
	if cfg.SenderName == "" {
		cfg.SenderName = "Revoked"
	}
	return cfg, true
}

// SignupEmailVerification reports whether a new account must confirm its
// address before it is created. Read per request, like [SignupsAllowed].
func SignupEmailVerification() bool {
	return envTrue(SignupVerifyEmailEnv)
}

func envTrue(name string) bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(name))) {
	case "1", "true", "yes":
		return true
	default:
		return false
	}
}
