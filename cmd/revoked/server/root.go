// Package server owns the per-hub root identity that anchors the trust chain
// for everything this server emits.
package server

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	// TXTPrefix is the label prepended to the operator's domain when publishing
	// the TXT record, so it cannot collide with other software on the bare domain.
	TXTPrefix = "_revoked"

	// TXTVersion is the format version baked into the TXT record.
	TXTVersion = "revoked1"

	// PEM block headers for the root keypair.
	pemPrivateLabel = "RSA PRIVATE KEY"
	pemPublicLabel  = "PUBLIC KEY"

	keyBits = 2048
)

// RootKey holds the server's signing key. Construct via [Load]; never
// instantiate by hand.
type RootKey struct {
	domain      string
	priv        *rsa.PrivateKey
	pubPEM      string
	fingerprint string
}

// Load reads the keypair at path, generating and persisting one with mode 0600
// if the file is absent. domain is the operator's public domain.
func Load(domain, path string) (*RootKey, error) {
	if strings.TrimSpace(domain) == "" {
		return nil, errors.New("server: domain is required")
	}

	priv, err := loadOrGenerate(path)
	if err != nil {
		return nil, err
	}

	pubPEM, err := encodePublicKeyPEM(&priv.PublicKey)
	if err != nil {
		return nil, fmt.Errorf("server: encode public key: %w", err)
	}

	return &RootKey{
		domain:      domain,
		priv:        priv,
		pubPEM:      pubPEM,
		fingerprint: fingerprintPEM(pubPEM),
	}, nil
}

// Domain returns the configured operator domain.
func (r *RootKey) Domain() string { return r.domain }

// PublicKeyPEM returns the PEM-encoded SubjectPublicKeyInfo of the root key.
func (r *RootKey) PublicKeyPEM() string { return r.pubPEM }

// Fingerprint returns the lowercase-hex SHA-256 of the public key PEM, matching
// the encoding the Flutter client uses for identity fingerprints.
func (r *RootKey) Fingerprint() string { return r.fingerprint }

// Sign returns a raw PKCS#1 v1.5 signature over the SHA-256 digest of message;
// callers encode it as needed.
func (r *RootKey) Sign(message []byte) ([]byte, error) {
	digest := sha256.Sum256(message)
	return rsa.SignPKCS1v15(rand.Reader, r.priv, crypto.SHA256, digest[:])
}

// TXTRecordValue is the value side of the TXT record the operator must publish,
// e.g. "v=revoked1; k=sha256/<hex>".
func (r *RootKey) TXTRecordValue() string {
	return fmt.Sprintf("v=%s; k=sha256/%s", TXTVersion, r.fingerprint)
}

// TXTRecordHost is the hostname the TXT record lives at, e.g. "_revoked.bmw.com".
func (r *RootKey) TXTRecordHost() string {
	return fmt.Sprintf("%s.%s", TXTPrefix, r.domain)
}

// SetupInstructions returns the human-readable DNS setup block printed to stdout
// at startup.
func (r *RootKey) SetupInstructions() string {
	var b strings.Builder
	b.WriteString("========================================\n")
	b.WriteString(" revoked — DNS verification setup\n")
	b.WriteString("========================================\n")
	fmt.Fprintf(&b, " Domain:               %s\n", r.domain)
	fmt.Fprintf(&b, " Root key fingerprint: %s\n", r.fingerprint)
	b.WriteString("\n")
	b.WriteString(" Add the following DNS TXT record:\n\n")
	fmt.Fprintf(&b, "   %s.  IN  TXT  %q\n\n", r.TXTRecordHost(), r.TXTRecordValue())
	b.WriteString(" Verify propagation with:\n\n")
	fmt.Fprintf(&b, "   dig +short TXT %s\n\n", r.TXTRecordHost())
	b.WriteString(" Until this record resolves, clients will refuse to\n")
	b.WriteString(" trust identities issued by this server.\n")
	b.WriteString("========================================\n")
	return b.String()
}

// loadOrGenerate reads the key from disk, generating a new one if the file is
// absent and writing it atomically (mode 0600) so a crash cannot leave a corrupt
// or world-readable key.
func loadOrGenerate(path string) (*rsa.PrivateKey, error) {
	if data, err := os.ReadFile(path); err == nil {
		block, _ := pem.Decode(data)
		if block == nil {
			return nil, fmt.Errorf("server: %s contains no PEM block", path)
		}
		priv, err := x509.ParsePKCS1PrivateKey(block.Bytes)
		if err != nil {
			return nil, fmt.Errorf("server: parse %s: %w", path, err)
		}
		return priv, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("server: read %s: %w", path, err)
	}

	priv, err := rsa.GenerateKey(rand.Reader, keyBits)
	if err != nil {
		return nil, fmt.Errorf("server: generate root key: %w", err)
	}

	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, fmt.Errorf("server: mkdir %s: %w", filepath.Dir(path), err)
	}

	encoded := pem.EncodeToMemory(&pem.Block{
		Type:  pemPrivateLabel,
		Bytes: x509.MarshalPKCS1PrivateKey(priv),
	})

	tmp, err := os.CreateTemp(filepath.Dir(path), ".server_root.*.tmp")
	if err != nil {
		return nil, fmt.Errorf("server: tempfile: %w", err)
	}
	tmpName := tmp.Name()
	if _, err := tmp.Write(encoded); err != nil {
		tmp.Close()
		os.Remove(tmpName)
		return nil, fmt.Errorf("server: write temp key: %w", err)
	}
	if err := tmp.Chmod(0o600); err != nil {
		tmp.Close()
		os.Remove(tmpName)
		return nil, fmt.Errorf("server: chmod temp key: %w", err)
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpName)
		return nil, fmt.Errorf("server: close temp key: %w", err)
	}
	if err := os.Rename(tmpName, path); err != nil {
		os.Remove(tmpName)
		return nil, fmt.Errorf("server: rename to %s: %w", path, err)
	}
	return priv, nil
}

func encodePublicKeyPEM(pub *rsa.PublicKey) (string, error) {
	der, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		return "", err
	}
	return string(pem.EncodeToMemory(&pem.Block{
		Type:  pemPublicLabel,
		Bytes: der,
	})), nil
}

func fingerprintPEM(pemStr string) string {
	sum := sha256.Sum256([]byte(pemStr))
	return strings.ToLower(hex.EncodeToString(sum[:]))
}
