package server

import (
	"crypto/rand"
	"crypto/rsa"
	"testing"
)

func TestSigningKeyIsCertifiedByTheRootKey(t *testing.T) {
	root := testRoot(t, "idp.example")
	keys, err := root.Issuer()
	if err != nil {
		t.Fatalf("Issuer: %v", err)
	}
	body, err := VerifySigningKey(keys.JWK(), root.PublicKeyPEM(), "idp.example")
	if err != nil {
		t.Fatalf("a freshly certified key did not verify: %v", err)
	}
	if body.Kid != keys.Kid() || body.Alg != "RS256" {
		t.Fatalf("certification does not describe the key: %+v", body)
	}
	if _, err := VerifySigningKey(keys.JWK(), root.PublicKeyPEM(), "other.example"); err == nil {
		t.Fatal("a certification was accepted for another domain")
	}
	if _, err := VerifySigningKey(keys.JWK(), testRoot(t, "idp.example").PublicKeyPEM(), "idp.example"); err == nil {
		t.Fatal("a certification verified under a root key that did not make it")
	}
}

// The certification names the key by its thumbprint, so it cannot be lifted
// onto a key the root key never saw.
func TestSigningKeyCertificationCannotMove(t *testing.T) {
	root := testRoot(t, "idp.example")
	keys, err := root.Issuer()
	if err != nil {
		t.Fatal(err)
	}
	other, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	forged := keys.JWK()
	forged.N, forged.E = rsaJWKParams(&other.PublicKey)
	if _, err := VerifySigningKey(forged, root.PublicKeyPEM(), "idp.example"); err == nil {
		t.Fatal("a certification verified for a different key")
	}
}

// The keys survive a restart: a new signing key would only cost a refetch of
// the JWKS, but a new subject secret would make every person a stranger to
// every service.
func TestIssuerKeysPersist(t *testing.T) {
	dir := t.TempDir()
	first, err := Load("idp.example", dir+"/server_root.pem")
	if err != nil {
		t.Fatal(err)
	}
	a, err := first.Issuer()
	if err != nil {
		t.Fatal(err)
	}
	second, err := Load("idp.example", dir+"/server_root.pem")
	if err != nil {
		t.Fatal(err)
	}
	b, err := second.Issuer()
	if err != nil {
		t.Fatal(err)
	}
	if a.Kid() != b.Kid() || string(a.SubjectSecret()) != string(b.SubjectSecret()) {
		t.Fatal("issuer keys changed across a reload")
	}
}

func TestJWKThumbprintMatchesRFC7638Example(t *testing.T) {
	// RFC 7638, section 3.1.
	jwk := JWK{
		N: "0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw",
		E: "AQAB",
	}
	pub, err := jwkPublicKey(jwk)
	if err != nil {
		t.Fatal(err)
	}
	if got := JWKThumbprint(pub); got != "NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs" {
		t.Fatalf("thumbprint = %s", got)
	}
}
