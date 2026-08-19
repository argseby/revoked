package server

import (
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"time"
)

// AssertionTTL bounds the validity of an /api/server assertion. It is
// deliberately short: the server re-signs on every hit, so a compromised key
// cannot be exploited long after rotation.
const AssertionTTL = 24 * time.Hour

// AssertionBody is what gets signed. Field order is load-bearing: the JSON
// encoding is the signed representation, so reordering invalidates every
// existing signature.
type AssertionBody struct {
	Domain      string `json:"domain"`
	PublicKey   string `json:"publicKey"`
	Fingerprint string `json:"fingerprint"`
	IssuedAt    int64  `json:"issuedAt"`
	ExpiresAt   int64  `json:"expiresAt"`
}

// Assertion is the wire format returned by /api/server.
type Assertion struct {
	Body      AssertionBody `json:"body"`
	Signature string        `json:"signature"`
}

// IssueAssertion mints a fresh assertion signed by the root key; now is a
// parameter so tests can pin time without touching globals.
func (r *RootKey) IssueAssertion(now time.Time) (Assertion, error) {
	body := AssertionBody{
		Domain:      r.domain,
		PublicKey:   r.pubPEM,
		Fingerprint: r.fingerprint,
		IssuedAt:    now.Unix(),
		ExpiresAt:   now.Add(AssertionTTL).Unix(),
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return Assertion{}, fmt.Errorf("server: marshal assertion: %w", err)
	}
	sig, err := r.Sign(payload)
	if err != nil {
		return Assertion{}, fmt.Errorf("server: sign assertion: %w", err)
	}
	return Assertion{
		Body:      body,
		Signature: hex.EncodeToString(sig),
	}, nil
}

// VerifyAssertion is the receiver-side counterpart to IssueAssertion, kept in
// this package so both sides agree on the signed representation.
func VerifyAssertion(a Assertion, now time.Time) error {
	if a.Body.Domain == "" {
		return errors.New("assertion: missing domain")
	}
	if a.Body.IssuedAt > now.Unix() {
		return errors.New("assertion: issued in the future")
	}
	if a.Body.ExpiresAt < now.Unix() {
		return errors.New("assertion: expired")
	}
	block, _ := pem.Decode([]byte(a.Body.PublicKey))
	if block == nil {
		return errors.New("assertion: publicKey is not PEM")
	}
	pubAny, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return fmt.Errorf("assertion: parse pubkey: %w", err)
	}
	pub, ok := pubAny.(*rsa.PublicKey)
	if !ok {
		return errors.New("assertion: pubkey is not RSA")
	}

	// Rejects a pubkey swapped in behind the DNS-pinned fingerprint.
	if got := fingerprintPEM(a.Body.PublicKey); got != a.Body.Fingerprint {
		return errors.New("assertion: fingerprint does not match embedded publicKey")
	}

	sig, err := hex.DecodeString(a.Signature)
	if err != nil {
		return fmt.Errorf("assertion: decode signature: %w", err)
	}
	payload, err := json.Marshal(a.Body)
	if err != nil {
		return fmt.Errorf("assertion: marshal body: %w", err)
	}
	digest := sha256.Sum256(payload)
	return rsa.VerifyPKCS1v15(pub, crypto.SHA256, digest[:], sig)
}
