package util

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/hkdf"
	"crypto/hpke"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"math/big"
	"os"
	"testing"
)

// The server does no sealing. This test exists so the app's hand-written
// crypto answers to an independent implementation, Go's crypto/hpke, in both
// directions: a mistake in the Dart code that only agrees with itself would
// otherwise pass every test it has.
type sealingVectors struct {
	IKM, PublicKey, PrivateKey, Info, Plaintext                 string
	GoSealed, DartSealed                                        string
	DartSignMessage, DartSignPublicKey, DartSignature           string
	ValueKey, WorkspaceKey, Workspace, Record, RecordKey, Value string
	Version, Epoch                                              int
	SealedValue, KeyWrap                                        string
	RecoverySecret                                              string
	RecoveryHpkePublicKey, RecoverySigningPublicKey             string
}

func loadSealingVectors(t *testing.T) sealingVectors {
	t.Helper()
	raw, err := os.ReadFile("../app/test/fixtures/sealing_vectors.json")
	if err != nil {
		t.Fatal(err)
	}
	var v sealingVectors
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	return v
}

func mustHex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestDartHpkeOpensInGo(t *testing.T) {
	v := loadSealingVectors(t)
	kem := hpke.DHKEM(ecdh.P256())

	derived, err := kem.DeriveKeyPair(mustHex(t, v.IKM))
	if err != nil {
		t.Fatal(err)
	}
	if got := hex.EncodeToString(derived.PublicKey().Bytes()); got != v.PublicKey {
		t.Fatalf("derived public key differs: %s", got)
	}

	got, err := hpke.Open(derived, hpke.HKDFSHA256(), hpke.AES256GCM(), mustHex(t, v.Info), mustHex(t, v.DartSealed))
	if err != nil {
		t.Fatalf("Go could not open what Dart sealed: %v", err)
	}
	if string(got) != string(mustHex(t, v.Plaintext)) {
		t.Fatalf("plaintext differs: %q", got)
	}
}

func TestDartSignatureVerifiesInGo(t *testing.T) {
	v := loadSealingVectors(t)
	pub := mustHex(t, v.DartSignPublicKey)
	x, y := elliptic.Unmarshal(elliptic.P256(), pub)
	if x == nil {
		t.Fatal("public key does not parse")
	}
	sig := mustHex(t, v.DartSignature)
	if len(sig) != 64 {
		t.Fatalf("signature is %d bytes", len(sig))
	}
	digest := sha256.Sum256(mustHex(t, v.DartSignMessage))
	r := new(big.Int).SetBytes(sig[:32])
	s := new(big.Int).SetBytes(sig[32:])
	if !ecdsa.Verify(&ecdsa.PublicKey{Curve: elliptic.P256(), X: x, Y: y}, digest[:], r, s) {
		t.Fatal("Go rejected the Dart signature")
	}
	if s.Cmp(new(big.Int).Rsh(elliptic.P256().Params().N, 1)) > 0 {
		t.Fatal("the Dart signature is not low-s, so hashes over it are not canonical")
	}
}

func sealingContext(label string, parts ...any) []byte {
	var out []byte
	addBytes := func(b []byte) {
		out = binary.BigEndian.AppendUint32(out, uint32(len(b)))
		out = append(out, b...)
	}
	addBytes([]byte(label))
	for _, p := range parts {
		switch part := p.(type) {
		case string:
			addBytes([]byte(part))
		case int:
			out = binary.BigEndian.AppendUint64(out, uint64(part))
		}
	}
	return out
}

func openEnvelope(t *testing.T, key []byte, aad []byte, encoded string) []byte {
	t.Helper()
	raw, err := base64.URLEncoding.DecodeString(encoded)
	if err != nil {
		t.Fatal(err)
	}
	if raw[0] != 1 {
		t.Fatalf("format version %d", raw[0])
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		t.Fatal(err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		t.Fatal(err)
	}
	plain, err := gcm.Open(nil, raw[1:13], raw[13:], append([]byte{raw[0]}, aad...))
	if err != nil {
		t.Fatalf("could not open envelope: %v", err)
	}
	return plain
}

func TestSealedValueFormatOpensInGo(t *testing.T) {
	v := loadSealingVectors(t)
	aad := sealingContext("revoked-record-v1", v.Workspace, v.Record, v.RecordKey, v.Version)
	padded := openEnvelope(t, mustHex(t, v.ValueKey), aad, v.SealedValue)

	if len(padded) != 64 {
		t.Fatalf("a short value should pad to the 64-byte bucket, got %d", len(padded))
	}
	end := len(padded) - 1
	for padded[end] == 0 {
		end--
	}
	if padded[end] != 0x80 {
		t.Fatalf("padding marker missing: %x", padded[end])
	}
	if string(padded[:end]) != v.Value {
		t.Fatalf("value differs: %q", padded[:end])
	}

	dekAad := sealingContext("revoked-dek-v1", v.Workspace, v.Record, v.Version, v.Epoch)
	if got := openEnvelope(t, mustHex(t, v.WorkspaceKey), dekAad, v.KeyWrap); string(got) != string(mustHex(t, v.ValueKey)) {
		t.Fatal("wrapped value key differs")
	}
}

func TestRecoveryKeysDeriveInGo(t *testing.T) {
	v := loadSealingVectors(t)
	kem := hpke.DHKEM(ecdh.P256())
	secret := mustHex(t, v.RecoverySecret)

	for purpose, want := range map[string]string{
		"revoked-recovery-hpke-v1": v.RecoveryHpkePublicKey,
		"revoked-recovery-sign-v1": v.RecoverySigningPublicKey,
	} {
		ikm, err := hkdf.Expand(sha256.New, mustExtract(t, secret), purpose, 32)
		if err != nil {
			t.Fatal(err)
		}
		derived, err := kem.DeriveKeyPair(ikm)
		if err != nil {
			t.Fatal(err)
		}
		if got := hex.EncodeToString(derived.PublicKey().Bytes()); got != want {
			t.Fatalf("%s: public key differs: %s", purpose, got)
		}
	}
}

func mustExtract(t *testing.T, secret []byte) []byte {
	t.Helper()
	prk, err := hkdf.Extract(sha256.New, secret, nil)
	if err != nil {
		t.Fatal(err)
	}
	return prk
}
