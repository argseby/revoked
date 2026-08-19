package util

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"

	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/pocketbase/pocketbase/core"
	"golang.org/x/crypto/bcrypt"
)

// RestrictFields rejects a request whose body carries any of the given fields.
// An `isset` rule can do the same, but without a usable error code.
func RestrictFields(e *core.RecordRequestEvent, fields ...string) error {
	info, err := e.RequestInfo()
	if err != nil {
		return nil // no request info: defer to the next handler
	}

	if info.HasSuperuserAuth() {
		return nil
	}

	errs := validation.Errors{}
	for _, field := range fields {
		if _, ok := info.Body[field]; ok {
			errs[field] = validation.NewError(Errors.ValidationFieldRestricted.ErrorCode, Errors.ValidationFieldRestricted.ErrorText)
		}
	}

	if len(errs) > 0 {
		return errs
	}

	return nil
}

// HashToken returns the SHA-256 hash of a token. SHA-256 rather than bcrypt is
// deliberate: these are high-entropy tokens (API keys, handshakes) needing fast
// lookup.
func HashToken(token string) string {
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:])
}

// HashPassword returns a salted bcrypt hash of a user-provided password.
func HashPassword(password string) (string, error) {
	if password == "" {
		return "", nil
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

// VerifyPassword compares a plaintext password against a stored bcrypt hash.
func VerifyPassword(hash string, password string) bool {
	if hash == "" {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}

// GenerateToken returns a cryptographically secure random hex token of n bytes.
func GenerateToken(numBytes int) (string, error) {
	b := make([]byte, numBytes)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
