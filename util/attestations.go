package util

import (
	"os"
	"regexp"
	"strings"
	"time"
)

// AllowAttestationsEnv opts a deployment into issuing attestations.
const AllowAttestationsEnv = "ALLOW_ATTESTATIONS"

// AttestationsAllowed reports whether this server issues attestations.
//
// Off unless explicitly enabled, for the reason signups are: an attestation is
// a statement in the name of the server's domain, and whoever trusts the
// domain trusts everything issued under it. On a server several people share,
// that is the operator's call, not something a new account receives with its
// workspace. Holding and verifying credentials do not depend on it.
func AttestationsAllowed() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(AllowAttestationsEnv))) {
	case "1", "true", "yes":
		return true
	default:
		return false
	}
}

const (
	// AttestationOfferTTL is how long an offer waits to be accepted when its
	// issuer sets no date.
	AttestationOfferTTL = 14 * 24 * time.Hour

	// AttestationCheckTTL is how long a request to see an attestation can be
	// answered. Short, because it is shown as a QR code to someone present: a
	// photo of it taken later must be useless.
	AttestationCheckTTL = 10 * time.Minute

	// MaxAttestationClaims bounds how many claims one attestation states.
	MaxAttestationClaims = 50

	// MaxAttestationClaimLength bounds one text value.
	MaxAttestationClaimLength = 1000

	// MaxCredentialLength bounds a credential a person may hold, and a
	// presentation the verify endpoint reads.
	MaxCredentialLength = 64 << 10

	// CredentialStatusListPath is where the status list of every credential
	// this server issued is published.
	CredentialStatusListPath = "/api/attestations/status"

	// CredentialIssuerMetadataPath is where the key credentials are signed
	// with is published, as SD-JWT VC defines it.
	CredentialIssuerMetadataPath = "/.well-known/jwt-vc-issuer"

	// ClaimHolder is the always-disclosed claim naming the identity a
	// credential is about: its fingerprint and the domain that issued it.
	ClaimHolder = "revoked_holder"
)

// attestationTypePattern accepts a credential type: a short key such as
// "membership", or a URI. No whitespace or control characters either way.
var attestationTypePattern = regexp.MustCompile(`^[\x21-\x7e]{1,255}$`)

// attestationClaimPattern accepts a claim name.
var attestationClaimPattern = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9_]{0,63}$`)

// reservedCredentialClaims are the names the credential format and this
// server set themselves. An attester's claim under one of them would either
// be overwritten or change what the credential means.
var reservedCredentialClaims = map[string]bool{
	"iss": true, "sub": true, "aud": true, "exp": true, "nbf": true, "iat": true, "jti": true,
	"vct": true, "cnf": true, "status": true, "_sd": true, "_sd_alg": true,
	ClaimHolder: true,
}

// ValidAttestationType reports whether a credential type is well-formed.
func ValidAttestationType(t string) bool {
	return attestationTypePattern.MatchString(t)
}

// ValidAttestationClaimName reports whether a claim name is well-formed, and
// whether it is one of the reserved names.
func ValidAttestationClaimName(name string) (ok, reserved bool) {
	if reservedCredentialClaims[name] || strings.HasPrefix(name, "_") {
		return false, true
	}
	return attestationClaimPattern.MatchString(name), false
}

// ValidAttestationClaimValue reports whether a claim value is one a
// credential states: text, a number, or true/false. Nested values are left
// out on purpose — each claim is disclosed or withheld as a whole, and a
// nested one would hide what is being given away.
func ValidAttestationClaimValue(v any) bool {
	switch t := v.(type) {
	case string:
		return t != "" && len(t) <= MaxAttestationClaimLength
	case bool, float64, int, int64:
		return true
	default:
		return false
	}
}
