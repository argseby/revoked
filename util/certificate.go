package util

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"errors"
	"math/big"
	"os"
	"path/filepath"
	"time"
)

// ServerCertificate holds the server's self-signed root certificate and RSA key
// material in PEM form, persisted as JSON in the PocketBase data dir.
//
// PrivateKey must never leave this process: this type is marshaled verbatim only
// when writing server_cert.json, and anything reaching an HTTP response MUST go
// through [ServerCertificate.PublicView].
type ServerCertificate struct {
	PrivateKey  string `json:"privateKey"`
	PublicKey   string `json:"publicKey"`
	Certificate string `json:"certificate"`
	Domain      string `json:"domain"`
}

// PublicView returns the externally shareable subset of the certificate and is
// the only supported way to expose certificate material over HTTP.
func (c *ServerCertificate) PublicView() map[string]any {
	return map[string]any{
		"certificate": c.Certificate,
		"publicKey":   c.PublicKey,
		"domain":      c.Domain,
	}
}

var serverCert *ServerCertificate

// LoadOrGenerateCertificate returns the certificate at dataDir/server_cert.json,
// generating and persisting a self-signed RSA-2048 one with 0600 perms on first
// run, and caching it for the lifetime of the process.
func LoadOrGenerateCertificate(dataDir string) (*ServerCertificate, error) {
	if serverCert != nil {
		return serverCert, nil
	}

	certPath := filepath.Join(dataDir, "server_cert.json")
	if _, err := os.Stat(certPath); err == nil {
		data, err := os.ReadFile(certPath)
		if err != nil {
			return nil, err
		}
		var cert ServerCertificate
		if err := json.Unmarshal(data, &cert); err != nil {
			return nil, err
		}
		serverCert = &cert
		return serverCert, nil
	}

	privKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, err
	}

	privBytes := x509.MarshalPKCS1PrivateKey(privKey)
	privPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: privBytes,
	})

	pubBytes, err := x509.MarshalPKIXPublicKey(&privKey.PublicKey)
	if err != nil {
		return nil, err
	}
	pubPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "PUBLIC KEY",
		Bytes: pubBytes,
	})

	serialNumber, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, err
	}

	template := x509.Certificate{
		SerialNumber: serialNumber,
		Subject: pkix.Name{
			Organization: []string{"Revoked Decentralized Trust Network"},
			CommonName:   "revoked.local",
		},
		NotBefore:             time.Now(),
		NotAfter:              time.Now().AddDate(10, 0, 0),
		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		IsCA:                  true,
	}

	certBytes, err := x509.CreateCertificate(rand.Reader, &template, &template, &privKey.PublicKey, privKey)
	if err != nil {
		return nil, err
	}

	certPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "CERTIFICATE",
		Bytes: certBytes,
	})

	cert := &ServerCertificate{
		PrivateKey:  string(privPEM),
		PublicKey:   string(pubPEM),
		Certificate: string(certPEM),
		Domain:      "revoked.local",
	}

	if err := os.MkdirAll(filepath.Dir(certPath), 0755); err != nil {
		return nil, err
	}
	jsonData, err := json.MarshalIndent(cert, "", "  ")
	if err != nil {
		return nil, err
	}
	if err := os.WriteFile(certPath, jsonData, 0600); err != nil {
		return nil, err
	}

	serverCert = cert
	return serverCert, nil
}

// GetServerCertificate returns the certificate loaded by
// LoadOrGenerateCertificate, or an error if it has not been loaded yet.
func GetServerCertificate() (*ServerCertificate, error) {
	if serverCert == nil {
		return nil, errors.New("certificate not loaded yet")
	}
	return serverCert, nil
}
