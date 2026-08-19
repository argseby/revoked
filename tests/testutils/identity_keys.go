package testutils

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/hex"
	"encoding/pem"
	"math/big"
	"testing"
	"time"
)

// IdentityKeyPair holds the key material tests need for the signed-challenge
// handshake.
type IdentityKeyPair struct {
	PrivateKey     *rsa.PrivateKey
	PublicKeyPem   string
	CertificatePem string
}

// NewTestIdentity mints an RSA-2048 keypair and a self-signed X.509 certificate
// suitable for posting to the identities collection; the private key never
// leaves memory.
func NewTestIdentity(t testing.TB, commonName string) *IdentityKeyPair {
	t.Helper()
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("Failed to generate RSA key: %v", err)
	}
	template := &x509.Certificate{
		SerialNumber: big.NewInt(time.Now().UnixNano()),
		Subject:      pkix.Name{CommonName: commonName, Organization: []string{"Revoked Tests"}},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth},
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &priv.PublicKey, priv)
	if err != nil {
		t.Fatalf("Failed to create certificate: %v", err)
	}
	certPem := string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}))

	pubDer, err := x509.MarshalPKIXPublicKey(&priv.PublicKey)
	if err != nil {
		t.Fatalf("Failed to marshal public key: %v", err)
	}
	pubPem := string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubDer}))

	return &IdentityKeyPair{PrivateKey: priv, PublicKeyPem: pubPem, CertificatePem: certPem}
}

// SignChallenge returns the base64 RSA-SHA256 signature over nonce that clients
// send back.
func (kp *IdentityKeyPair) SignChallenge(t testing.TB, nonce string) string {
	t.Helper()
	hashed := sha256.Sum256([]byte(nonce))
	sig, err := rsa.SignPKCS1v15(rand.Reader, kp.PrivateKey, crypto.SHA256, hashed[:])
	if err != nil {
		t.Fatalf("Failed to sign challenge: %v", err)
	}
	return base64.StdEncoding.EncodeToString(sig)
}

// Fingerprint is the lowercase SHA-256 hex of the certificate PEM, matching the
// server-side identity fingerprint.
func (kp *IdentityKeyPair) Fingerprint() string {
	sum := sha256.Sum256([]byte(kp.CertificatePem))
	return hex.EncodeToString(sum[:])
}
