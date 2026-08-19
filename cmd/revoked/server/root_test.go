package server

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestLoad_GeneratesAndPersists(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sub", "server_root.pem")

	r1, err := Load("example.com", path)
	if err != nil {
		t.Fatalf("first Load: %v", err)
	}
	if r1.Fingerprint() == "" {
		t.Fatal("fingerprint must not be empty")
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("expected key file at %s: %v", path, err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("expected mode 0600 for key file, got %o", info.Mode().Perm())
	}

	r2, err := Load("example.com", path)
	if err != nil {
		t.Fatalf("second Load: %v", err)
	}
	if r2.Fingerprint() != r1.Fingerprint() {
		t.Fatalf("fingerprint changed across loads: %q vs %q", r1.Fingerprint(), r2.Fingerprint())
	}
	if r2.PublicKeyPEM() != r1.PublicKeyPEM() {
		t.Fatal("public PEM differs across loads")
	}
}

func TestLoad_RejectsEmptyDomain(t *testing.T) {
	if _, err := Load("", filepath.Join(t.TempDir(), "k.pem")); err == nil {
		t.Fatal("expected error for empty domain")
	}
}

func TestTXTRecord_FormatIsParseable(t *testing.T) {
	root, err := Load("bmw.com", filepath.Join(t.TempDir(), "k.pem"))
	if err != nil {
		t.Fatal(err)
	}
	if got := root.TXTRecordHost(); got != "_revoked.bmw.com" {
		t.Errorf("TXTRecordHost = %q, want _revoked.bmw.com", got)
	}
	val := root.TXTRecordValue()
	if !strings.HasPrefix(val, "v=revoked1; k=sha256/") {
		t.Errorf("TXTRecordValue = %q does not match expected shape", val)
	}
	// A mismatch here makes client-side DNS checks reject legitimate servers.
	want := "v=revoked1; k=sha256/" + root.Fingerprint()
	if val != want {
		t.Errorf("TXTRecordValue = %q, want %q", val, want)
	}
}

func TestAssertion_RoundTrip(t *testing.T) {
	root, err := Load("bmw.com", filepath.Join(t.TempDir(), "k.pem"))
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	a, err := root.IssueAssertion(now)
	if err != nil {
		t.Fatalf("IssueAssertion: %v", err)
	}
	if a.Body.Domain != "bmw.com" {
		t.Errorf("assertion domain = %q", a.Body.Domain)
	}
	if a.Body.Fingerprint != root.Fingerprint() {
		t.Errorf("assertion fingerprint mismatch")
	}
	if a.Body.ExpiresAt-a.Body.IssuedAt != int64(AssertionTTL.Seconds()) {
		t.Errorf("TTL window unexpected: %d", a.Body.ExpiresAt-a.Body.IssuedAt)
	}

	if err := VerifyAssertion(a, now.Add(time.Hour)); err != nil {
		t.Errorf("verify within TTL failed: %v", err)
	}
	if err := VerifyAssertion(a, now.Add(AssertionTTL+time.Minute)); err == nil {
		t.Error("verify past TTL should fail")
	}
	if err := VerifyAssertion(a, now.Add(-time.Hour)); err == nil {
		t.Error("verify before IssuedAt should fail")
	}
}

func TestAssertion_TamperingDetected(t *testing.T) {
	root, err := Load("bmw.com", filepath.Join(t.TempDir(), "k.pem"))
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	a, err := root.IssueAssertion(now)
	if err != nil {
		t.Fatal(err)
	}

	tampered := a
	tampered.Body.Domain = "attacker.com"
	if err := VerifyAssertion(tampered, now); err == nil {
		t.Error("domain tampering must fail verification")
	}

	tampered = a
	tampered.Signature = "deadbeef" + tampered.Signature[8:]
	if err := VerifyAssertion(tampered, now); err == nil {
		t.Error("signature tampering must fail verification")
	}

	// A fingerprint disagreeing with the embedded pubkey must be caught before
	// the signature check.
	tampered = a
	tampered.Body.Fingerprint = strings.Repeat("0", len(tampered.Body.Fingerprint))
	if err := VerifyAssertion(tampered, now); err == nil {
		t.Error("fingerprint/pubkey mismatch must fail verification")
	}
}

func TestSign_DeterministicVerifiable(t *testing.T) {
	root, err := Load("bmw.com", filepath.Join(t.TempDir(), "k.pem"))
	if err != nil {
		t.Fatal(err)
	}
	sig, err := root.Sign([]byte("hello"))
	if err != nil {
		t.Fatal(err)
	}
	if len(sig) == 0 {
		t.Fatal("empty signature")
	}
	// PKCS1v15 is deterministic for the same key+message+hash.
	sig2, err := root.Sign([]byte("hello"))
	if err != nil {
		t.Fatal(err)
	}
	if string(sig) != string(sig2) {
		t.Error("PKCS1v15 should be deterministic for the same input")
	}
}
