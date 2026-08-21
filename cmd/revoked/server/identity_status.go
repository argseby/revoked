package server

import (
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"
)

// IdentityStatusType is the domain separator for a status body, and the reason
// it is the first field of the signed JSON.
//
// The root key already signs two other things: an assertion body (JSON) and a
// bare identity fingerprint (64 hex characters, no envelope) — the latter being
// exactly what parentSignature is. This endpoint signs a payload containing a
// fingerprint the CALLER chose, so without a separator it would be a signing
// oracle: coax the server into signing a bare fingerprint and you have minted a
// parentSignature for an identity that claims to come from this domain. The
// leading type tag makes a status body unmistakable for either of the others.
const IdentityStatusType = "identity-status-v1"

// Wire vocabulary for a status answer. Unknown is not a synonym for revoked: a
// restored backup or a reinstall answers that way about identities that were
// perfectly valid, so a verifier must treat it as "no information".
const (
	IdentityStatusActive  = "active"
	IdentityStatusRevoked = "revoked"
	IdentityStatusUnknown = "unknown"
)

// IdentityStatusTTL bounds how long a status answer may be relied on. It is much
// shorter than AssertionTTL because it is the revocation latency: a compromised
// key stays honoured for at most this long after it is withdrawn.
const IdentityStatusTTL = time.Hour

// fingerprintPattern is the only input this endpoint will sign a statement
// about. Constraining the shape keeps the signing oracle to a fixed vocabulary.
var fingerprintPattern = regexp.MustCompile(`^[0-9a-f]{64}$`)

// IdentityStatusBody is what gets signed. Field order is load-bearing: the JSON
// encoding is the signed representation, so reordering invalidates every
// existing signature.
type IdentityStatusBody struct {
	Type        string `json:"type"`
	Domain      string `json:"domain"`
	Fingerprint string `json:"fingerprint"`
	Status      string `json:"status"`
	Reason      string `json:"reason,omitempty"`
	RevokedAt   int64  `json:"revokedAt,omitempty"`
	IssuedAt    int64  `json:"issuedAt"`
	ExpiresAt   int64  `json:"expiresAt"`
}

// IdentityStatusAssertion is the wire format returned by
// GET /api/identities/{fingerprint}/status, and stapled into public probes.
//
// Payload carries the exact bytes that were signed, base64url without padding,
// and the body is read back out of it. Transmitting the encoding rather than the
// decoded object is what keeps signer and verifier from having to agree on JSON
// field order and which empty fields are omitted — a disagreement between the Go
// server and the Dart client would present as a valid key that signs nothing
// anyone can check, which is precisely how the SHA-1/SHA-256 mismatch presented.
type IdentityStatusAssertion struct {
	Payload   string `json:"payload"`
	Signature string `json:"signature"`
}

// Body decodes the payload WITHOUT checking the signature. Only for rendering
// something already verified, or for diagnostics; anything that acts on the
// answer must go through [VerifyIdentityStatus], which returns the body it
// verified so an unchecked one is never in reach.
func (a IdentityStatusAssertion) Body() (IdentityStatusBody, error) {
	raw, err := base64.RawURLEncoding.DecodeString(a.Payload)
	if err != nil {
		return IdentityStatusBody{}, fmt.Errorf("identity status: decode payload: %w", err)
	}
	var body IdentityStatusBody
	if err := json.Unmarshal(raw, &body); err != nil {
		return IdentityStatusBody{}, fmt.Errorf("identity status: parse payload: %w", err)
	}
	return body, nil
}

// ValidIdentityFingerprint reports whether a fingerprint is well-formed enough
// to be worth answering about.
func ValidIdentityFingerprint(fingerprint string) bool {
	return fingerprintPattern.MatchString(fingerprint)
}

// IssueIdentityStatus mints a freshly signed answer about one fingerprint; now
// is a parameter so tests can pin time without touching globals.
func (r *RootKey) IssueIdentityStatus(fingerprint, status, reason string, revokedAt time.Time, now time.Time) (IdentityStatusAssertion, error) {
	if !ValidIdentityFingerprint(fingerprint) {
		return IdentityStatusAssertion{}, errors.New("server: identity status: malformed fingerprint")
	}
	switch status {
	case IdentityStatusActive, IdentityStatusRevoked, IdentityStatusUnknown:
	default:
		return IdentityStatusAssertion{}, fmt.Errorf("server: identity status: unknown status %q", status)
	}

	body := IdentityStatusBody{
		Type:        IdentityStatusType,
		Domain:      r.domain,
		Fingerprint: fingerprint,
		Status:      status,
		Reason:      reason,
		IssuedAt:    now.Unix(),
		ExpiresAt:   now.Add(IdentityStatusTTL).Unix(),
	}
	if status == IdentityStatusRevoked && !revokedAt.IsZero() {
		body.RevokedAt = revokedAt.Unix()
	}

	payload, err := json.Marshal(body)
	if err != nil {
		return IdentityStatusAssertion{}, fmt.Errorf("server: marshal identity status: %w", err)
	}
	sig, err := r.Sign(payload)
	if err != nil {
		return IdentityStatusAssertion{}, fmt.Errorf("server: sign identity status: %w", err)
	}
	return IdentityStatusAssertion{
		Payload:   base64.RawURLEncoding.EncodeToString(payload),
		Signature: hex.EncodeToString(sig),
	}, nil
}

// VerifyIdentityStatus is the receiver-side counterpart to IssueIdentityStatus,
// kept in this package so both sides agree on the signed representation.
//
// It returns the body it verified, so a caller cannot end up acting on one it
// did not check. rootPubPEM must be a root key already tied to expectDomain
// through the DNS pin — this checks that the key signed the statement, not that
// the key deserves to be believed.
//
// The signature is checked over the transmitted payload bytes before they are
// parsed, and every field test below reads the body that came out of those exact
// bytes.
func VerifyIdentityStatus(a IdentityStatusAssertion, rootPubPEM, expectDomain, expectFingerprint string, now time.Time) (IdentityStatusBody, error) {
	payload, err := base64.RawURLEncoding.DecodeString(a.Payload)
	if err != nil {
		return IdentityStatusBody{}, fmt.Errorf("identity status: decode payload: %w", err)
	}

	block, _ := pem.Decode([]byte(rootPubPEM))
	if block == nil {
		return IdentityStatusBody{}, errors.New("identity status: root key is not PEM")
	}
	pubAny, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return IdentityStatusBody{}, fmt.Errorf("identity status: parse root key: %w", err)
	}
	pub, ok := pubAny.(*rsa.PublicKey)
	if !ok {
		return IdentityStatusBody{}, errors.New("identity status: root key is not RSA")
	}

	sig, err := hex.DecodeString(a.Signature)
	if err != nil {
		return IdentityStatusBody{}, fmt.Errorf("identity status: decode signature: %w", err)
	}
	digest := sha256.Sum256(payload)
	if err := rsa.VerifyPKCS1v15(pub, crypto.SHA256, digest[:], sig); err != nil {
		return IdentityStatusBody{}, fmt.Errorf("identity status: signature: %w", err)
	}

	var body IdentityStatusBody
	if err := json.Unmarshal(payload, &body); err != nil {
		return IdentityStatusBody{}, fmt.Errorf("identity status: parse payload: %w", err)
	}

	if body.Type != IdentityStatusType {
		return IdentityStatusBody{}, errors.New("identity status: wrong or missing type")
	}
	if !strings.EqualFold(body.Domain, expectDomain) {
		return IdentityStatusBody{}, errors.New("identity status: answer is for a different domain")
	}
	if !strings.EqualFold(body.Fingerprint, expectFingerprint) {
		return IdentityStatusBody{}, errors.New("identity status: answer is about a different identity")
	}
	if body.IssuedAt > now.Unix() {
		return IdentityStatusBody{}, errors.New("identity status: issued in the future")
	}
	if body.ExpiresAt < now.Unix() {
		return IdentityStatusBody{}, errors.New("identity status: expired")
	}
	return body, nil
}
