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
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func testRoot(t *testing.T, domain string) *RootKey {
	t.Helper()
	r, err := Load(domain, filepath.Join(t.TempDir(), "server_root.pem"))
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	return r
}

const sampleFingerprint = "3fa2c1b0d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f"

func TestIdentityStatusRoundTrip(t *testing.T) {
	root := testRoot(t, "bmw.example")
	now := time.Unix(1_700_000_000, 0)

	assertion, err := root.IssueIdentityStatus(sampleFingerprint, IdentityStatusActive, "", time.Time{}, now)
	if err != nil {
		t.Fatalf("IssueIdentityStatus: %v", err)
	}

	body, err := VerifyIdentityStatus(assertion, root.PublicKeyPEM(), "bmw.example", sampleFingerprint, now)
	if err != nil {
		t.Fatalf("a freshly issued status did not verify: %v", err)
	}
	if body.Status != IdentityStatusActive || body.Fingerprint != sampleFingerprint {
		t.Fatalf("verified body does not describe what was issued: %+v", body)
	}
}

// A status answer is only as good as its freshness — that is the entire reason
// it exists, since the certificate it describes stays signed for ten years.
func TestIdentityStatusExpires(t *testing.T) {
	root := testRoot(t, "bmw.example")
	now := time.Unix(1_700_000_000, 0)

	assertion, err := root.IssueIdentityStatus(sampleFingerprint, IdentityStatusActive, "", time.Time{}, now)
	if err != nil {
		t.Fatalf("IssueIdentityStatus: %v", err)
	}

	later := now.Add(IdentityStatusTTL + time.Second)
	if _, err := VerifyIdentityStatus(assertion, root.PublicKeyPEM(), "bmw.example", sampleFingerprint, later); err == nil {
		t.Fatal("a stale status answer was accepted")
	}
}

// The answer names the identity it is about, so a valid "active" for one
// fingerprint cannot be replayed as cover for another.
func TestIdentityStatusIsBoundToItsSubject(t *testing.T) {
	root := testRoot(t, "bmw.example")
	now := time.Unix(1_700_000_000, 0)

	assertion, err := root.IssueIdentityStatus(sampleFingerprint, IdentityStatusActive, "", time.Time{}, now)
	if err != nil {
		t.Fatalf("IssueIdentityStatus: %v", err)
	}

	other := strings.Repeat("ab", 32)
	if _, err := VerifyIdentityStatus(assertion, root.PublicKeyPEM(), "bmw.example", other, now); err == nil {
		t.Fatal("a status answer verified against a different fingerprint")
	}
	if _, err := VerifyIdentityStatus(assertion, root.PublicKeyPEM(), "audi.example", sampleFingerprint, now); err == nil {
		t.Fatal("a status answer verified against a different domain")
	}
}

// One key signs three different things, and this endpoint is the only one that
// signs a payload the caller chose. If a status body could ever be read as a
// bare fingerprint, obtaining one would forge a parentSignature — a credential
// claiming to be issued by this domain. The type tag is what prevents that, so
// it is pinned here rather than left to the shape of the JSON.
func TestIdentityStatusCannotForgeAParentSignature(t *testing.T) {
	root := testRoot(t, "bmw.example")
	now := time.Unix(1_700_000_000, 0)

	assertion, err := root.IssueIdentityStatus(sampleFingerprint, IdentityStatusActive, "", time.Time{}, now)
	if err != nil {
		t.Fatalf("IssueIdentityStatus: %v", err)
	}

	sig, err := hex.DecodeString(assertion.Signature)
	if err != nil {
		t.Fatalf("decode signature: %v", err)
	}

	block, _ := pem.Decode([]byte(root.PublicKeyPEM()))
	pubAny, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		t.Fatalf("parse root key: %v", err)
	}
	pub := pubAny.(*rsa.PublicKey)

	// The exact check hooks/identities.go makes when anchoring an identity.
	digest := sha256.Sum256([]byte(sampleFingerprint))
	if err := rsa.VerifyPKCS1v15(pub, crypto.SHA256, digest[:], sig); err == nil {
		t.Fatal("a status signature verified as a parentSignature over the bare fingerprint")
	}

	// And the signed bytes are unmistakable for an /api/server assertion body.
	signed, err := base64.RawURLEncoding.DecodeString(assertion.Payload)
	if err != nil {
		t.Fatalf("decode payload: %v", err)
	}
	if !strings.HasPrefix(string(signed), `{"type":"`+IdentityStatusType+`"`) {
		t.Fatal("the type tag is not the leading field of the signed representation")
	}
}

// A malformed fingerprint is refused before anything is signed, so the endpoint
// cannot be walked outside its fixed vocabulary.
func TestIdentityStatusRefusesMalformedFingerprints(t *testing.T) {
	root := testRoot(t, "bmw.example")
	now := time.Unix(1_700_000_000, 0)

	for _, bad := range []string{
		"",
		"not-hex",
		strings.ToUpper(sampleFingerprint),
		sampleFingerprint + "0",
		sampleFingerprint[:63],
		`","publicKey":"injected`,
	} {
		if _, err := root.IssueIdentityStatus(bad, IdentityStatusActive, "", time.Time{}, now); err == nil {
			t.Fatalf("signed a statement about a malformed fingerprint %q", bad)
		}
	}
}

// Tampering with any field invalidates the signature, including the status word
// itself — the one an attacker most wants to flip back to active.
func TestIdentityStatusDetectsTampering(t *testing.T) {
	root := testRoot(t, "bmw.example")
	now := time.Unix(1_700_000_000, 0)

	revokedAt := now.Add(-time.Hour)
	assertion, err := root.IssueIdentityStatus(
		sampleFingerprint, IdentityStatusRevoked, "membership_ended", revokedAt, now,
	)
	if err != nil {
		t.Fatalf("IssueIdentityStatus: %v", err)
	}

	// Rewriting the payload is the only way to change what the answer says, and
	// the signature is checked over those bytes before anything reads them.
	repayload := func(mutate func(*IdentityStatusBody)) IdentityStatusAssertion {
		t.Helper()
		body, err := assertion.Body()
		if err != nil {
			t.Fatalf("decode payload: %v", err)
		}
		mutate(&body)
		raw, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal: %v", err)
		}
		return IdentityStatusAssertion{
			Payload:   base64.RawURLEncoding.EncodeToString(raw),
			Signature: assertion.Signature,
		}
	}

	flipped := repayload(func(b *IdentityStatusBody) { b.Status = IdentityStatusActive })
	if _, err := VerifyIdentityStatus(flipped, root.PublicKeyPEM(), "bmw.example", sampleFingerprint, now); err == nil {
		t.Fatal("a revoked answer was flipped to active without breaking the signature")
	}

	stretched := repayload(func(b *IdentityStatusBody) {
		b.ExpiresAt = now.Add(100 * 24 * time.Hour).Unix()
	})
	if _, err := VerifyIdentityStatus(stretched, root.PublicKeyPEM(), "bmw.example", sampleFingerprint, now); err == nil {
		t.Fatal("the expiry was extended without breaking the signature")
	}
}

// A different server's key must not be able to answer for this domain.
func TestIdentityStatusRejectsAForeignSigner(t *testing.T) {
	issuer := testRoot(t, "bmw.example")
	impostor := testRoot(t, "bmw.example")
	now := time.Unix(1_700_000_000, 0)

	assertion, err := impostor.IssueIdentityStatus(sampleFingerprint, IdentityStatusActive, "", time.Time{}, now)
	if err != nil {
		t.Fatalf("IssueIdentityStatus: %v", err)
	}
	if _, err := VerifyIdentityStatus(assertion, issuer.PublicKeyPEM(), "bmw.example", sampleFingerprint, now); err == nil {
		t.Fatal("a status answer signed by another key verified under this root")
	}
}
