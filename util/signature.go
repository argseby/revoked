package util

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"errors"
)

// ErrInvalidCertificatePem is returned when a PEM block cannot be parsed.
var ErrInvalidCertificatePem = errors.New("invalid certificate PEM")

// ErrUnsupportedPublicKey is returned when the embedded public key is neither
// RSA nor ECDSA.
var ErrUnsupportedPublicKey = errors.New("certificate does not embed an RSA or ECDSA public key")

// VerifySignature checks a base64 RSASSA-PKCS1-v1_5 or ECDSA SHA-256 signature
// against keyPem, which may be an X.509 certificate PEM or a bare
// SubjectPublicKeyInfo PEM.
func VerifySignature(keyPem, message, signature string) error {
	pubKey, err := publicKeyFromAnyPem(keyPem)
	if err != nil {
		return err
	}
	sig, err := base64.StdEncoding.DecodeString(signature)
	if err != nil {
		// Tolerate URL-safe / unpadded encodings too.
		sig, err = base64.RawStdEncoding.DecodeString(signature)
		if err != nil {
			return err
		}
	}
	hashed := sha256.Sum256([]byte(message))

	switch pk := pubKey.(type) {
	case *rsa.PublicKey:
		return rsa.VerifyPKCS1v15(pk, crypto.SHA256, hashed[:], sig)
	case *ecdsa.PublicKey:
		if !ecdsa.VerifyASN1(pk, hashed[:], sig) {
			return errors.New("invalid ECDSA signature")
		}
		return nil
	default:
		return ErrUnsupportedPublicKey
	}
}

// publicKeyFromAnyPem extracts a public key from an X.509 certificate PEM or a
// bare SubjectPublicKeyInfo PEM.
func publicKeyFromAnyPem(keyPem string) (any, error) {
	block, _ := pem.Decode([]byte(keyPem))
	if block == nil {
		return nil, ErrInvalidCertificatePem
	}
	if block.Type == "PUBLIC KEY" {
		return x509.ParsePKIXPublicKey(block.Bytes)
	}
	if cert, err := x509.ParseCertificate(block.Bytes); err == nil {
		return cert.PublicKey, nil
	}
	// Last resort: a public key under a non-standard block type.
	return x509.ParsePKIXPublicKey(block.Bytes)
}
