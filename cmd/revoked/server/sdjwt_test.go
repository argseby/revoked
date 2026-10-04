package server

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"
)

func TestCredentialKeyIsCertifiedByTheRootKey(t *testing.T) {
	root := testRoot(t, "attester.example")
	keys, err := root.Credentials()
	if err != nil {
		t.Fatalf("Credentials: %v", err)
	}
	pub, err := VerifyCredentialKey(keys.JWK(), root.PublicKeyPEM(), "attester.example")
	if err != nil {
		t.Fatalf("a freshly certified key did not verify: %v", err)
	}
	if !pub.Equal(keys.PublicKey()) {
		t.Fatal("the verified key is not the published one")
	}
	if _, err := VerifyCredentialKey(keys.JWK(), root.PublicKeyPEM(), "other.example"); err == nil {
		t.Fatal("a certification was accepted for another domain")
	}
	if _, err := VerifyCredentialKey(keys.JWK(), testRoot(t, "attester.example").PublicKeyPEM(), "attester.example"); err == nil {
		t.Fatal("a certification verified under a root key that did not make it")
	}

	other, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	forged := keys.JWK()
	swapped, _ := JWKFromPublicKey(&other.PublicKey)
	forged.X, forged.Y = swapped.X, swapped.Y
	if _, err := VerifyCredentialKey(forged, root.PublicKeyPEM(), "attester.example"); err == nil {
		t.Fatal("a certification verified for a different key")
	}
}

// A key certified for signing ID tokens must not be accepted as a credential
// key, nor the other way round: each certification names its purpose.
func TestKeyCertificationsAreNotInterchangeable(t *testing.T) {
	root := testRoot(t, "attester.example")
	issuer, err := root.Issuer()
	if err != nil {
		t.Fatal(err)
	}
	credentials, err := root.Credentials()
	if err != nil {
		t.Fatal(err)
	}
	asCredentialKey := credentials.JWK()
	asCredentialKey.Certification = issuer.JWK().Certification
	if _, err := VerifyCredentialKey(asCredentialKey, root.PublicKeyPEM(), "attester.example"); err == nil {
		t.Fatal("an ID-token certification was accepted for a credential key")
	}
	asSigningKey := issuer.JWK()
	asSigningKey.Certification = credentials.JWK().Certification
	if _, err := VerifySigningKey(asSigningKey, root.PublicKeyPEM(), "attester.example"); err == nil {
		t.Fatal("a credential certification was accepted for an ID-token key")
	}

	// The purpose is part of what the root key signs: a certification that
	// names this very key, but for another purpose, is not one for issuing
	// credentials.
	for name, body := range map[string]SigningKeyCertBody{
		"another purpose":   {Type: SigningKeyCertType, Domain: "attester.example", Kid: credentials.Kid(), Use: "sig", Alg: "ES256"},
		"another algorithm": {Type: CredentialKeyCertType, Domain: "attester.example", Kid: credentials.Kid(), Use: "sig", Alg: "RS256"},
	} {
		payload, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		sig, err := root.Sign(payload)
		if err != nil {
			t.Fatal(err)
		}
		jwk := credentials.JWK()
		jwk.Certification = &SignedStatement{
			Payload:   base64.RawURLEncoding.EncodeToString(payload),
			Signature: hex.EncodeToString(sig),
		}
		if _, err := VerifyCredentialKey(jwk, root.PublicKeyPEM(), "attester.example"); err == nil {
			t.Fatalf("a certification for %s was accepted for a credential key", name)
		}
	}
}

func TestCredentialKeyPersists(t *testing.T) {
	dir := t.TempDir()
	first, err := Load("attester.example", dir+"/server_root.pem")
	if err != nil {
		t.Fatal(err)
	}
	a, err := first.Credentials()
	if err != nil {
		t.Fatal(err)
	}
	second, err := Load("attester.example", dir+"/server_root.pem")
	if err != nil {
		t.Fatal(err)
	}
	b, err := second.Credentials()
	if err != nil {
		t.Fatal(err)
	}
	if a.Kid() != b.Kid() {
		t.Fatal("the credential key changed across a reload")
	}
}

func TestECJWKThumbprintMatchesRFC7638Form(t *testing.T) {
	jwk := PublicJWK{Kty: "EC", Crv: "P-256", X: "f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU", Y: "x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0"}
	got, err := jwk.Thumbprint()
	if err != nil {
		t.Fatal(err)
	}
	// SHA-256 of {"crv":"P-256","kty":"EC","x":"…","y":"…"}, as RFC 7638 orders
	// the required members of an EC key.
	if want := sdDigest(`{"crv":"P-256","kty":"EC","x":"f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU","y":"x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0"}`); got != want {
		t.Fatalf("thumbprint = %s, want %s", got, want)
	}
	if _, err := jwk.PublicKey(); err != nil {
		t.Fatalf("the RFC 7515 example key did not decode: %v", err)
	}
}

type testHolder struct {
	ec  *ecdsa.PrivateKey
	rsa *rsa.PrivateKey
	jwk PublicJWK
}

func newECHolder(t *testing.T) testHolder {
	t.Helper()
	priv, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	jwk, err := JWKFromPublicKey(&priv.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	return testHolder{ec: priv, jwk: jwk}
}

func (h testHolder) alg() string {
	if h.rsa != nil {
		return "RS256"
	}
	return "ES256"
}

func (h testHolder) sign(input string) ([]byte, error) {
	if h.rsa != nil {
		return SignRS256(h.rsa, input)
	}
	return SignES256(h.ec, input)
}

func testCredential(t *testing.T, keys *CredentialKeys, holder testHolder, now time.Time, expires time.Time) string {
	t.Helper()
	credential, err := keys.IssueCredential(CredentialSpec{
		Issuer:    "https://attester.example",
		Type:      "membership",
		Holder:    HolderRef{Fingerprint: strings.Repeat("ab", 32), Domain: "home.example"},
		HolderKey: holder.jwk,
		Claims:    map[string]any{"name": "Ada Lovelace", "age_over_18": true, "member_no": float64(42)},
		IssuedAt:  now,
		ExpiresAt: expires,
		Status:    &StatusRef{Idx: 7, URI: "https://attester.example/api/attestations/status"},
	})
	if err != nil {
		t.Fatalf("IssueCredential: %v", err)
	}
	return credential
}

func TestCredentialStatesWhatWasIssued(t *testing.T) {
	root := testRoot(t, "attester.example")
	keys, _ := root.Credentials()
	holder := newECHolder(t)
	now := time.Now()
	credential := testCredential(t, keys, holder, now, now.Add(time.Hour))

	if !strings.HasSuffix(credential, "~") {
		t.Fatal("an issued credential ends with a tilde: it carries no key binding")
	}
	p, err := ParseCredential(credential)
	if err != nil {
		t.Fatalf("ParseCredential: %v", err)
	}
	if len(p.Disclosures) != 3 || p.KeyBinding != "" {
		t.Fatalf("disclosures = %d, key binding = %q", len(p.Disclosures), p.KeyBinding)
	}
	// Nothing a credential states is readable from the signed part alone.
	for _, secret := range []string{"Ada", "member_no", "age_over_18"} {
		if raw, _ := p.Payload["_sd"]; strings.Contains(strings.Join(toStrings(raw), ","), secret) {
			t.Fatalf("%q appears in the digests", secret)
		}
		if _, present := p.Payload[secret]; present {
			t.Fatalf("%q is stated in the clear", secret)
		}
	}

	v, err := VerifyCredential(p, keys.PublicKey(), now)
	if err != nil {
		t.Fatalf("VerifyCredential: %v", err)
	}
	if v.Issuer != "https://attester.example" || v.Type != "membership" {
		t.Fatalf("issuer/type = %q/%q", v.Issuer, v.Type)
	}
	if v.Holder.Domain != "home.example" || v.Holder.Fingerprint != strings.Repeat("ab", 32) {
		t.Fatalf("holder = %+v", v.Holder)
	}
	if v.HolderKey == nil || !v.HolderKey.SameKey(holder.jwk) {
		t.Fatal("the credential does not name the holder's key")
	}
	if v.Status == nil || v.Status.Idx != 7 {
		t.Fatalf("status = %+v", v.Status)
	}
	if v.Claims["name"] != "Ada Lovelace" || v.Claims["age_over_18"] != true || v.Claims["member_no"] != float64(42) {
		t.Fatalf("claims = %v", v.Claims)
	}
	if v.Withheld != 0 {
		t.Fatalf("withheld = %d", v.Withheld)
	}

	other := testRoot(t, "attester.example")
	otherKeys, _ := other.Credentials()
	if _, err := VerifyCredential(p, otherKeys.PublicKey(), now); err == nil {
		t.Fatal("a credential verified under a key that did not sign it")
	}
}

func toStrings(v any) []string {
	list, _ := v.([]any)
	out := make([]string, 0, len(list))
	for _, item := range list {
		if s, ok := item.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

func TestPresentationDisclosesOnlyWhatWasChosen(t *testing.T) {
	root := testRoot(t, "attester.example")
	keys, _ := root.Credentials()
	holder := newECHolder(t)
	now := time.Now()
	credential := testCredential(t, keys, holder, now, time.Time{})

	presentation, err := PresentCredential(credential, []string{"age_over_18"},
		"https://shop.example", "n-123", holder.alg(), now, holder.sign)
	if err != nil {
		t.Fatalf("PresentCredential: %v", err)
	}
	if strings.Contains(presentation, credentialDisclosure(t, credential, "name")) {
		t.Fatal("a withheld disclosure travelled with the presentation")
	}
	p, err := ParseCredential(presentation)
	if err != nil {
		t.Fatalf("ParseCredential: %v", err)
	}
	v, err := VerifyCredential(p, keys.PublicKey(), now)
	if err != nil {
		t.Fatalf("VerifyCredential: %v", err)
	}
	if len(v.Claims) != 1 || v.Claims["age_over_18"] != true || v.Withheld != 2 {
		t.Fatalf("claims = %v, withheld = %d", v.Claims, v.Withheld)
	}
	if err := VerifyKeyBinding(p, *v.HolderKey, "https://shop.example", "n-123", now); err != nil {
		t.Fatalf("VerifyKeyBinding: %v", err)
	}

	if err := VerifyKeyBinding(p, *v.HolderKey, "https://other.example", "n-123", now); err == nil {
		t.Fatal("a key binding was accepted by a verifier it was not made for")
	}
	if err := VerifyKeyBinding(p, *v.HolderKey, "https://shop.example", "n-456", now); err == nil {
		t.Fatal("a key binding was accepted for another nonce")
	}
	if err := VerifyKeyBinding(p, *v.HolderKey, "https://shop.example", "n-123", now.Add(PresentationMaxAge+time.Second)); err == nil {
		t.Fatal("a stale key binding was accepted")
	}
	stranger := newECHolder(t)
	if err := VerifyKeyBinding(p, stranger.jwk, "https://shop.example", "n-123", now); err == nil {
		t.Fatal("a key binding verified under a key that did not make it")
	}
}

func credentialDisclosure(t *testing.T, credential, name string) string {
	t.Helper()
	p, err := ParseCredential(credential)
	if err != nil {
		t.Fatal(err)
	}
	for _, d := range p.Disclosures {
		if d.Name == name {
			return d.Raw
		}
	}
	t.Fatalf("no disclosure for %q", name)
	return ""
}

// A key binding commits to the disclosures it was made with, so someone who
// captures a presentation cannot widen or narrow what it reveals.
func TestKeyBindingCoversTheDisclosures(t *testing.T) {
	root := testRoot(t, "attester.example")
	keys, _ := root.Credentials()
	holder := newECHolder(t)
	now := time.Now()
	credential := testCredential(t, keys, holder, now, time.Time{})

	presentation, err := PresentCredential(credential, []string{"age_over_18"},
		"https://shop.example", "n-1", holder.alg(), now, holder.sign)
	if err != nil {
		t.Fatal(err)
	}
	parts := strings.Split(presentation, "~")
	binding := parts[len(parts)-1]

	widened := parts[0] + "~" + parts[1] + "~" + credentialDisclosure(t, credential, "name") + "~" + binding
	p, err := ParseCredential(widened)
	if err != nil {
		t.Fatalf("ParseCredential: %v", err)
	}
	if err := VerifyKeyBinding(p, holder.jwk, "https://shop.example", "n-1", now); err == nil {
		t.Fatal("a disclosure added after the key binding was accepted")
	}

	narrowed := parts[0] + "~" + binding
	p, err = ParseCredential(narrowed)
	if err != nil {
		t.Fatalf("ParseCredential: %v", err)
	}
	if err := VerifyKeyBinding(p, holder.jwk, "https://shop.example", "n-1", now); err == nil {
		t.Fatal("a disclosure removed after the key binding was accepted")
	}

	if err := VerifyKeyBinding(mustParse(t, credential), holder.jwk, "https://shop.example", "n-1", now); !errors.Is(err, ErrNoKeyBinding) {
		t.Fatalf("a credential without a key binding: %v", err)
	}
}

func mustParse(t *testing.T, s string) *ParsedCredential {
	t.Helper()
	p, err := ParseCredential(s)
	if err != nil {
		t.Fatalf("ParseCredential: %v", err)
	}
	return p
}

func TestForeignAndRepeatedDisclosuresAreRefused(t *testing.T) {
	root := testRoot(t, "attester.example")
	keys, _ := root.Credentials()
	holder := newECHolder(t)
	now := time.Now()
	one := testCredential(t, keys, holder, now, time.Time{})
	two := testCredential(t, keys, holder, now, time.Time{})

	jwt := strings.Split(one, "~")[0]
	if _, err := ParseCredential(jwt + "~" + credentialDisclosure(t, two, "name") + "~"); err == nil {
		t.Fatal("a disclosure from another credential was accepted")
	}
	own := credentialDisclosure(t, one, "name")
	if _, err := ParseCredential(jwt + "~" + own + "~" + own + "~"); err == nil {
		t.Fatal("a disclosure given twice was accepted")
	}
	if _, err := ParseCredential(jwt); err == nil {
		t.Fatal("a bare JWT was read as a credential")
	}
	if _, err := PresentCredential(one, []string{"shoe_size"}, "https://shop.example", "n", holder.alg(), now, holder.sign); err == nil {
		t.Fatal("a claim the credential does not hold was presented")
	}
}

func TestCredentialValidityIsItsOwn(t *testing.T) {
	root := testRoot(t, "attester.example")
	keys, _ := root.Credentials()
	holder := newECHolder(t)
	now := time.Now()
	credential := testCredential(t, keys, holder, now, now.Add(time.Hour))
	p := mustParse(t, credential)

	v, err := VerifyCredential(p, keys.PublicKey(), now.Add(2*time.Hour))
	if !errors.Is(err, ErrCredentialExpired) {
		t.Fatalf("an expired credential: %v", err)
	}
	if v.Type != "membership" {
		t.Fatal("an expired credential no longer says what it was")
	}
	if _, err := VerifyCredential(p, keys.PublicKey(), now.Add(-time.Hour)); !errors.Is(err, ErrCredentialNotYetValid) {
		t.Fatalf("a credential issued in the future: %v", err)
	}
}

// Identities made before the app generated P-256 keys are RSA; a credential
// binds to those with RS256.
func TestRSAHolderKey(t *testing.T) {
	root := testRoot(t, "attester.example")
	keys, _ := root.Credentials()
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	jwk, err := JWKFromPublicKey(&priv.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	holder := testHolder{rsa: priv, jwk: jwk}
	now := time.Now()
	credential := testCredential(t, keys, holder, now, time.Time{})

	presentation, err := PresentCredential(credential, nil, "https://shop.example", "n", holder.alg(), now, holder.sign)
	if err != nil {
		t.Fatal(err)
	}
	p := mustParse(t, presentation)
	v, err := VerifyCredential(p, keys.PublicKey(), now)
	if err != nil {
		t.Fatal(err)
	}
	if len(v.Claims) != 0 || v.Withheld != 3 {
		t.Fatalf("claims = %v, withheld = %d", v.Claims, v.Withheld)
	}
	if err := VerifyKeyBinding(p, *v.HolderKey, "https://shop.example", "n", now); err != nil {
		t.Fatalf("VerifyKeyBinding: %v", err)
	}

	// The algorithm has to be the one that fits the key.
	ec := newECHolder(t)
	mislabelled, err := PresentCredential(credential, nil, "https://shop.example", "n", "RS256", now, ec.sign)
	if err != nil {
		t.Fatal(err)
	}
	if err := VerifyKeyBinding(mustParse(t, mislabelled), jwk, "https://shop.example", "n", now); err == nil {
		t.Fatal("a key binding signed with another key was accepted")
	}
}

func TestStatusListBitOrder(t *testing.T) {
	// The example of the Token Status List specification: sixteen one-bit
	// statuses packed from the least significant bit give 0xb9 0xa3.
	statuses := []int{1, 0, 0, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 1, 0, 1}
	list := NewStatusList(len(statuses))
	for idx, s := range statuses {
		if s == 1 {
			list.Revoke(idx)
		}
	}
	if list.bits[0] != 0xb9 || list.bits[1] != 0xa3 {
		t.Fatalf("bits = %#x %#x", list.bits[0], list.bits[1])
	}
	for idx, s := range statuses {
		revoked, known := list.Revoked(idx)
		if !known || revoked != (s == 1) {
			t.Fatalf("position %d: revoked=%v known=%v", idx, revoked, known)
		}
	}
	if _, known := list.Revoked(16); known {
		t.Fatal("a position past the end of the list was answered")
	}
}

func TestStatusListToken(t *testing.T) {
	root := testRoot(t, "attester.example")
	keys, _ := root.Credentials()
	const uri = "https://attester.example/api/attestations/status"
	now := time.Now()

	list := NewStatusList(1024)
	list.Revoke(7)
	token, err := keys.SignStatusList(uri, list, now)
	if err != nil {
		t.Fatalf("SignStatusList: %v", err)
	}
	got, ttl, err := VerifyStatusList(token, keys.PublicKey(), uri, now)
	if err != nil {
		t.Fatalf("VerifyStatusList: %v", err)
	}
	if ttl != StatusListTTL || got.Len() != 1024 {
		t.Fatalf("ttl = %v, len = %d", ttl, got.Len())
	}
	if revoked, known := got.Revoked(7); !revoked || !known {
		t.Fatal("the revoked position reads as valid")
	}
	if revoked, known := got.Revoked(8); revoked || !known {
		t.Fatal("a valid position reads as revoked")
	}

	if _, _, err := VerifyStatusList(token, keys.PublicKey(), "https://attester.example/other", now); err == nil {
		t.Fatal("a list was accepted for an address it was not published for")
	}
	if _, _, err := VerifyStatusList(token, keys.PublicKey(), uri, now.Add(StatusListValidity+time.Second)); err == nil {
		t.Fatal("an expired list was accepted")
	}
	other := testRoot(t, "attester.example")
	otherKeys, _ := other.Credentials()
	if _, _, err := VerifyStatusList(token, otherKeys.PublicKey(), uri, now); err == nil {
		t.Fatal("a list verified under a key that did not sign it")
	}
	// A credential is not a status list, even when the same key signed it.
	credential := testCredential(t, keys, newECHolder(t), now, time.Time{})
	if _, _, err := VerifyStatusList(strings.Split(credential, "~")[0], keys.PublicKey(), uri, now); err == nil {
		t.Fatal("a credential was accepted as a status list")
	}
}
