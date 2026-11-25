package routes

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/hkdf"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"math/big"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"revoked/util"
)

// passkeyIdentityReference derives the identity key the way the page must:
// HKDF-SHA256 over the PRF output with an empty salt and the purpose as info,
// 48 bytes reduced into [1, n-1]. Written apart from the page's script, so the
// two can be compared.
func passkeyIdentityReference(t *testing.T, prf []byte) (*ecdsa.PrivateKey, string) {
	t.Helper()
	okm, err := hkdf.Key(sha256.New, prf, nil, "revoked-passkey-identity-v1", 48)
	if err != nil {
		t.Fatal(err)
	}
	curve := elliptic.P256()
	nMinus1 := new(big.Int).Sub(curve.Params().N, big.NewInt(1))
	d := new(big.Int).Mod(new(big.Int).SetBytes(okm), nMinus1)
	d.Add(d, big.NewInt(1))
	key, err := ecdsa.ParseRawPrivateKey(curve, d.FillBytes(make([]byte, 32)))
	if err != nil {
		t.Fatal(err)
	}
	spki, err := x509.MarshalPKIXPublicKey(&key.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	return key, string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: spki}))
}

const passkeyIdentityHarness = `
function identityError(code) { return new Error(code); }
function unhex(s) { var out = new Uint8Array(s.length / 2); for (var i = 0; i < out.length; i++) out[i] = parseInt(s.substr(i * 2, 2), 16); return out; }
(async function () {
  var out = [];
  for (var i = 2; i < process.argv.length; i++) {
    var key = await deriveIdentityKey(unhex(process.argv[i]));
    out.push({ pem: key.publicPem, signature: await identitySignWith(key.privateKey, 'revoked-oidc-consent:ticket-' + i) });
  }
  process.stdout.write(JSON.stringify(out));
})().catch(function (e) { console.error(e); process.exit(1); });
`

// The page and the server agree on the key a PRF output makes and on the
// signatures it gives: the identity a person registered in one browser is the
// one every other browser derives from the same passkey, and what it signs
// verifies where the app's signatures do.
func TestPasskeyIdentityMatchesTheReference(t *testing.T) {
	node, err := exec.LookPath("node")
	if err != nil {
		t.Skip("node is not installed; the page's key derivation is not checked on this machine")
	}
	prfs := []string{
		strings.Repeat("00", 32),
		strings.Repeat("ff", 32),
		"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
		"9b1e2f7c5d3a48e6b0c4f1a27d8e9c3b5a6f0e1d2c3b4a59687766554433221a",
	}
	script := filepath.Join(t.TempDir(), "identity.js")
	if err := os.WriteFile(script, []byte(passkeyIdentityScript+passkeyIdentityHarness), 0o600); err != nil {
		t.Fatal(err)
	}
	raw, err := exec.Command(node, append([]string{script}, prfs...)...).Output()
	if err != nil {
		t.Fatalf("node: %v", err)
	}
	var got []struct {
		PEM       string `json:"pem"`
		Signature string `json:"signature"`
	}
	if err := json.Unmarshal(raw, &got); err != nil || len(got) != len(prfs) {
		t.Fatalf("harness output %q: %v", raw, err)
	}
	seen := map[string]bool{}
	for i, prf := range prfs {
		b, _ := hex.DecodeString(prf)
		_, want := passkeyIdentityReference(t, b)
		if got[i].PEM != want {
			t.Fatalf("prf %s: page derived\n%s\nreference\n%s", prf, got[i].PEM, want)
		}
		message := "revoked-oidc-consent:ticket-" + string(rune('0'+i+2))
		if err := util.VerifySignature(got[i].PEM, message, got[i].Signature); err != nil {
			t.Fatalf("prf %s: the page's signature does not verify: %v", prf, err)
		}
		if util.VerifySignature(got[i].PEM, message+"x", got[i].Signature) == nil {
			t.Fatalf("prf %s: a signature verified for another message", prf)
		}
		if seen[want] {
			t.Fatalf("two PRF outputs gave one key")
		}
		seen[want] = true
	}
}
