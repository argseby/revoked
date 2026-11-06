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
	IKM, PublicKey, PrivateKey, Info, Plaintext                                                                                       string
	GoSealed, DartSealed                                                                                                              string
	DartSignMessage, DartSignPublicKey, DartSignature                                                                                 string
	ValueKey, WorkspaceKey, Workspace, Record, RecordKey, Value                                                                       string
	Version, Epoch                                                                                                                    int
	SealedValue, KeyWrap                                                                                                              string
	ChainUser, ChainEntries, ChainWorkspace, ChainWrap, ChainWrapSignature, ChainUnsealRecord, ChainUnsealValue, ChainUnsealSignature string
	ChainWrapEpoch, ChainWrapDeviceSeq, ChainWrapSignerSeq, ChainWrapChainSeq, ChainUnsealVersion, ChainUnsealDeviceSeq               int
	RecoverySecret                                                                                                                    string
	RecoveryHpkePublicKey, RecoverySigningPublicKey                                                                                   string
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

// The server checks every entry a client appends, so a list the app signed must
// pass the Go check byte for byte.
func TestDartSignedListVerifiesInGo(t *testing.T) {
	v := loadSealingVectors(t)
	var entries []struct {
		Seq              int    `json:"seq"`
		Action           string `json:"action"`
		Kind             string `json:"kind"`
		Label            string `json:"label"`
		HpkePublicKey    string `json:"hpkePublicKey"`
		SigningPublicKey string `json:"signingPublicKey"`
		TargetSeq        int    `json:"targetSeq"`
		PreviousHash     string `json:"previousHash"`
		SignerSeq        int    `json:"signerSeq"`
		AnchorSignature  string `json:"anchorSignature"`
		Signature        string `json:"signature"`
	}
	if err := json.Unmarshal([]byte(v.ChainEntries), &entries); err != nil {
		t.Fatal(err)
	}
	if len(entries) < 4 {
		t.Fatalf("only %d entries", len(entries))
	}
	decode := func(s string) []byte {
		b, err := base64.URLEncoding.DecodeString(s)
		if err != nil {
			t.Fatal(err)
		}
		return b
	}
	chain := &SealedChain{}
	for _, e := range entries {
		err := chain.Append(SealedChainEntry{
			User: v.ChainUser, Seq: e.Seq, Action: e.Action, Kind: e.Kind, Label: e.Label,
			HpkePublicKey: decode(e.HpkePublicKey), SigningPublicKey: decode(e.SigningPublicKey),
			TargetSeq: e.TargetSeq, PreviousHash: decode(e.PreviousHash), SignerSeq: e.SignerSeq,
			AnchorSignature: decode(e.AnchorSignature), Signature: decode(e.Signature),
		})
		if err != nil {
			t.Fatalf("Go refused entry %d that Dart signed: %v", e.Seq, err)
		}
	}
	if !VerifySealedSignature(chain.Entry(v.ChainWrapSignerSeq).SigningPublicKey,
		SealedWrapPayload(v.ChainWorkspace, v.ChainWrapEpoch,
			chain.Entry(v.ChainWrapDeviceSeq).HpkePublicKey, v.ChainWrap, v.ChainWrapChainSeq),
		decode(v.ChainWrapSignature)) {
		t.Fatal("Go refused a key hand-over Dart signed")
	}
	if !VerifySealedSignature(chain.Entry(v.ChainUnsealDeviceSeq).SigningPublicKey,
		SealedUnsealPayload(v.ChainUser, v.ChainUnsealRecord, v.ChainUnsealVersion, v.ChainUnsealValue),
		decode(v.ChainUnsealSignature)) {
		t.Fatal("Go refused an unseal Dart signed")
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

// A passkey's keys derive from its PRF output the way the recovery key's do, and
// a list the app signed with one must pass the Go check (E2EE.md §6.8).
func TestPasskeyKeysDeriveAndVerifyInGo(t *testing.T) {
	raw, err := os.ReadFile("../app/test/fixtures/sealing_passkey_vectors.json")
	if err != nil {
		t.Fatal(err)
	}
	var v struct {
		User, CredentialId, PrfSecret, HpkePublicKey, SigningPublicKey, Entries string
	}
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	kem := hpke.DHKEM(ecdh.P256())
	secret := mustHex(t, v.PrfSecret)
	for purpose, want := range map[string]string{
		"revoked-passkey-hpke-v1": v.HpkePublicKey,
		"revoked-passkey-sign-v1": v.SigningPublicKey,
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

	var entries []struct {
		Seq              int    `json:"seq"`
		Action           string `json:"action"`
		Kind             string `json:"kind"`
		Label            string `json:"label"`
		CredentialId     string `json:"credentialId"`
		HpkePublicKey    string `json:"hpkePublicKey"`
		SigningPublicKey string `json:"signingPublicKey"`
		TargetSeq        int    `json:"targetSeq"`
		PreviousHash     string `json:"previousHash"`
		SignerSeq        int    `json:"signerSeq"`
		AnchorSignature  string `json:"anchorSignature"`
		Signature        string `json:"signature"`
	}
	if err := json.Unmarshal([]byte(v.Entries), &entries); err != nil {
		t.Fatal(err)
	}
	decode := func(s string) []byte {
		b, err := base64.URLEncoding.DecodeString(s)
		if err != nil {
			t.Fatal(err)
		}
		return b
	}
	chain := &SealedChain{}
	for _, e := range entries {
		err := chain.Append(SealedChainEntry{
			User: v.User, Seq: e.Seq, Action: e.Action, Kind: e.Kind, Label: e.Label, CredentialID: e.CredentialId,
			HpkePublicKey: decode(e.HpkePublicKey), SigningPublicKey: decode(e.SigningPublicKey),
			TargetSeq: e.TargetSeq, PreviousHash: decode(e.PreviousHash), SignerSeq: e.SignerSeq,
			AnchorSignature: decode(e.AnchorSignature), Signature: decode(e.Signature),
		})
		if err != nil {
			t.Fatalf("Go refused entry %d that Dart signed: %v", e.Seq, err)
		}
	}
	if chain.LivePasskey(v.CredentialId) == nil || chain.Entry(3).SignerSeq != 2 {
		t.Fatal("the passkey entry is not live, or did not vouch for the device")
	}
	if hex.EncodeToString(chain.LivePasskey(v.CredentialId).SigningPublicKey) != v.SigningPublicKey {
		t.Fatal("the list's passkey entry does not carry the derived key")
	}
}

// A grant is signed by the app and checked by this server, so the two must
// build the same payload byte for byte.
func TestDartGrantSignatureVerifiesInGo(t *testing.T) {
	raw, err := os.ReadFile("../app/test/fixtures/sealing_grant_vectors.json")
	if err != nil {
		t.Fatal(err)
	}
	var v struct {
		Workspace, RecipientUser, GranterUser     string
		RecipientHpkePublicKey, SigningPublicKey  string
		Wrap, Signature                           string
		Epoch, GranterChainSeq, RecipientChainSeq int
	}
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	signature, err := base64.URLEncoding.DecodeString(v.Signature)
	if err != nil {
		t.Fatal(err)
	}
	payload := SealedGrantPayload(v.Workspace, v.Epoch, v.RecipientUser,
		mustHex(t, v.RecipientHpkePublicKey), v.Wrap, v.GranterUser, v.GranterChainSeq, v.RecipientChainSeq)
	if !VerifySealedSignature(mustHex(t, v.SigningPublicKey), payload, signature) {
		t.Fatal("Go refused a grant Dart signed")
	}
	// Every bound field matters: the same signature over another recipient fails.
	other := SealedGrantPayload(v.Workspace, v.Epoch, "someoneelse0001",
		mustHex(t, v.RecipientHpkePublicKey), v.Wrap, v.GranterUser, v.GranterChainSeq, v.RecipientChainSeq)
	if VerifySealedSignature(mustHex(t, v.SigningPublicKey), other, signature) {
		t.Fatal("a grant verified for someone it does not name")
	}
}
