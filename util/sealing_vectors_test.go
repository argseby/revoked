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

// A link carries an encrypted record as three small envelopes, and the link
// page opens them in a browser with HKDF and AES-GCM alone. Go opening each one
// with its own primitives is what says a third implementation can
// (design/e2ee-sharing.md §3.2).
func TestLinkFormatsOpenInGo(t *testing.T) {
	raw, err := os.ReadFile("../app/test/fixtures/sealing_link_vectors.json")
	if err != nil {
		t.Fatal(err)
	}
	var v struct {
		Workspace, Link, Record, Scope       string
		Version, Epoch                       int
		LinkKey, ValueKey, ScopeKey, CopyKey string
		ViewerWrap, WriterWrap, LinkKeyWrap  string
	}
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}

	copyKey, err := hkdf.Expand(sha256.New, mustExtract(t, mustHex(t, v.LinkKey)),
		string(sealingContext("revoked-link-copy-v1", v.Record)), 32)
	if err != nil {
		t.Fatal(err)
	}
	if hex.EncodeToString(copyKey) != v.CopyKey {
		t.Fatalf("copy key differs: %x", copyKey)
	}

	// The viewer: value key first, then the workspace its value is bound to.
	viewer := openEnvelope(t, copyKey,
		sealingContext("revoked-link-viewer-v1", v.Record, v.Version), v.ViewerWrap)
	if len(viewer) <= 32 || hex.EncodeToString(viewer[:32]) != v.ValueKey || string(viewer[32:]) != v.Workspace {
		t.Fatalf("viewer wrap opened to something else: %x", viewer)
	}

	// The next writer: the copy key, under the value key of this version.
	writer := openEnvelope(t, mustHex(t, v.ValueKey),
		sealingContext("revoked-link-writer-v1", v.Workspace, v.Link, v.Record, v.Version), v.WriterWrap)
	if hex.EncodeToString(writer) != v.CopyKey {
		t.Fatalf("writer wrap opened to something else: %x", writer)
	}

	linkKey := openEnvelope(t, mustHex(t, v.ScopeKey),
		sealingContext("revoked-link-key-v1", v.Scope, v.Link, v.Epoch), v.LinkKeyWrap)
	if hex.EncodeToString(linkKey) != v.LinkKey {
		t.Fatalf("link key wrap opened to something else: %x", linkKey)
	}

	// What the server checks without a key: each envelope has exactly the
	// length its content gives it.
	for name, c := range map[string]struct {
		wrap string
		size int
	}{
		"viewerWrap":  {v.ViewerWrap, SealedEnvelopeOverhead + 32 + len(v.Workspace)},
		"writerWrap":  {v.WriterWrap, SealedEnvelopeOverhead + 32},
		"linkKeyWrap": {v.LinkKeyWrap, SealedEnvelopeOverhead + 32},
	} {
		raw, err := base64.URLEncoding.DecodeString(c.wrap)
		if err != nil || len(raw) != c.size {
			t.Fatalf("%s is %d bytes, expected %d", name, len(raw), c.size)
		}
	}
}

// What a reader with nothing but a link's address does, end to end: from the
// key the address ends in and one entry as the public read returns it, to the
// value with the label, type and format that were encrypted with it. The link
// page does this in a browser (routes/publicPageSealing.go) and the app in its
// own view of a link; Go doing it with its own primitives is what holds the
// three to one format (design/e2ee-sharing.md §3).
func TestLinkReadVectorOpensInGo(t *testing.T) {
	raw, err := os.ReadFile("../app/test/fixtures/sealing_link_read_vectors.json")
	if err != nil {
		t.Fatal(err)
	}
	var v struct {
		LinkKey, Workspace string
		Entry              struct {
			ID, Key, SealedValue, ViewerWrap string
			SealedVersion                    int
		}
		Content map[string]string
	}
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}

	// In an address the key is base64url without padding.
	linkKey, err := base64.RawURLEncoding.DecodeString(v.LinkKey)
	if err != nil || len(linkKey) != 32 {
		t.Fatalf("link key: %v, %d bytes", err, len(linkKey))
	}
	copyKey, err := hkdf.Expand(sha256.New, mustExtract(t, linkKey),
		string(sealingContext("revoked-link-copy-v1", v.Entry.ID)), 32)
	if err != nil {
		t.Fatal(err)
	}
	viewer := openEnvelope(t, copyKey,
		sealingContext("revoked-link-viewer-v1", v.Entry.ID, v.Entry.SealedVersion), v.Entry.ViewerWrap)
	if len(viewer) <= 32 || string(viewer[32:]) != v.Workspace {
		t.Fatalf("viewer wrap opened to something else: %x", viewer)
	}

	padded := openEnvelope(t, viewer[:32],
		sealingContext("revoked-record-v1", string(viewer[32:]), v.Entry.ID, v.Entry.Key, v.Entry.SealedVersion),
		v.Entry.SealedValue)
	end := len(padded) - 1
	for end > 0 && padded[end] == 0 {
		end--
	}
	if padded[end] != 0x80 {
		t.Fatalf("padding marker missing: %x", padded[end])
	}
	var content map[string]string
	if err := json.Unmarshal(padded[:end], &content); err != nil {
		t.Fatalf("content is not JSON: %v: %q", err, padded[:end])
	}
	if len(content) != 4 {
		t.Fatalf("content has %d fields: %v", len(content), content)
	}
	for _, field := range []string{"v", "l", "t", "f"} {
		if content[field] != v.Content[field] || content[field] == "" {
			t.Fatalf("content %q differs: %q, expected %q", field, content[field], v.Content[field])
		}
	}
}

// TestFileVectorOpensInGo reads an encrypted file the way a link's viewer
// does (design/e2ee-sharing.md §7.2), from the address key to the bytes, with
// Go's own HKDF and AES-GCM rather than anything shared with the app.
func TestFileVectorOpensInGo(t *testing.T) {
	raw, err := os.ReadFile("../app/test/fixtures/sealing_file_vectors.json")
	if err != nil {
		t.Fatal(err)
	}
	var v struct {
		LinkKey, Workspace string
		Entry              struct {
			ID, Key, SealedValue, ViewerWrap string
			SealedVersion                    int
		}
		PlaintextSha256, Blob string
		Small                 struct{ Text, Blob string }
	}
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}

	linkKey, err := base64.RawURLEncoding.DecodeString(v.LinkKey)
	if err != nil {
		t.Fatal(err)
	}
	copyKey, err := hkdf.Expand(sha256.New, mustExtract(t, linkKey),
		string(sealingContext("revoked-link-copy-v1", v.Entry.ID)), 32)
	if err != nil {
		t.Fatal(err)
	}
	viewer := openEnvelope(t, copyKey,
		sealingContext("revoked-link-viewer-v1", v.Entry.ID, v.Entry.SealedVersion), v.Entry.ViewerWrap)
	workspace := string(viewer[32:])
	padded := openEnvelope(t, viewer[:32],
		sealingContext("revoked-record-v1", workspace, v.Entry.ID, v.Entry.Key, v.Entry.SealedVersion),
		v.Entry.SealedValue)
	end := len(padded) - 1
	for end > 0 && padded[end] == 0 {
		end--
	}
	var content struct {
		V, T string
		X    struct {
			N, M, K string
			S       int
		}
	}
	if err := json.Unmarshal(padded[:end], &content); err != nil {
		t.Fatalf("content is not JSON: %v", err)
	}
	if content.V != "" || content.T != "file" || content.X.N == "" {
		t.Fatalf("not a file descriptor: %+v", content)
	}
	fileKey, err := base64.RawURLEncoding.DecodeString(content.X.K)
	if err != nil || len(fileKey) != 32 {
		t.Fatalf("file key: %v", err)
	}

	open := func(blobText string, size int) []byte {
		blob, err := base64.URLEncoding.DecodeString(blobText)
		if err != nil {
			t.Fatal(err)
		}
		if blob[0] != 1 {
			t.Fatalf("version %d", blob[0])
		}
		salt := blob[1:17]
		segKey, err := hkdf.Expand(sha256.New, mustExtract(t, fileKey),
			string(sealingContext("revoked-file-v1", workspace, v.Entry.ID, string(salt))), 32)
		if err != nil {
			t.Fatal(err)
		}
		block, _ := aes.NewCipher(segKey)
		gcm, _ := cipher.NewGCM(block)
		var plain []byte
		rest := blob[17:]
		for i := uint64(0); ; i++ {
			n := min(len(rest), 65536+16)
			last := n == len(rest)
			nonce := make([]byte, 12)
			binary.BigEndian.PutUint64(nonce[3:11], i)
			if last {
				nonce[11] = 1
			}
			seg, err := gcm.Open(nil, nonce, rest[:n], []byte{1})
			if err != nil {
				t.Fatalf("segment %d: %v", i, err)
			}
			plain = append(plain, seg...)
			rest = rest[n:]
			if last {
				break
			}
		}
		for _, b := range plain[size:] {
			if b != 0 {
				t.Fatal("padding is not zeros")
			}
		}
		return plain[:size]
	}

	bytes := open(v.Blob, content.X.S)
	sum := sha256.Sum256(bytes)
	if hex.EncodeToString(sum[:]) != v.PlaintextSha256 {
		t.Fatalf("file differs: %x", sum)
	}
	if got := string(open(v.Small.Blob, len(v.Small.Text))); got != v.Small.Text {
		t.Fatalf("small file: %q", got)
	}
}
