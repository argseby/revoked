package server

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"time"
)

const (
	// IssuerKeyFile holds the key ID tokens are signed with. It lives next to
	// the root key and is certified by it, so the DNS pin still anchors every
	// token while the root key itself signs only the certification.
	IssuerKeyFile = "oidc_signing.pem"

	// SubjectSecretFile holds the secret per-service subject identifiers are
	// derived from. Losing it changes every subject at every service, so it
	// is state to back up like the root key.
	SubjectSecretFile = "oidc_subject.key"

	// SigningKeyCertType is the domain separator for a signing-key
	// certification, for the same reason [IdentityStatusType] leads a status.
	SigningKeyCertType = "signing-key-v1"

	pemSubjectLabel  = "REVOKED SUBJECT SECRET"
	subjectSecretLen = 32
)

// IssuerKeys are what the OpenID Connect provider signs and derives with.
type IssuerKeys struct {
	priv          *rsa.PrivateKey
	kid           string
	subjectSecret []byte
	certification SignedStatement
}

// SignedStatement is a root-key statement in the wire format every signed
// statement here uses: the exact signed bytes, base64url, and the signature
// over them, hex.
type SignedStatement struct {
	Payload   string `json:"payload"`
	Signature string `json:"signature"`
}

// SigningKeyCertBody is what the root key signs about a signing key. The
// thumbprint names the key, so the certification cannot be moved to another.
type SigningKeyCertBody struct {
	Type     string `json:"type"`
	Domain   string `json:"domain"`
	Kid      string `json:"kid"`
	Use      string `json:"use"`
	Alg      string `json:"alg"`
	IssuedAt int64  `json:"issuedAt"`
}

// JWK is one published signing key, with the root key's certification of it.
type JWK struct {
	Kty           string           `json:"kty"`
	Use           string           `json:"use"`
	Alg           string           `json:"alg"`
	Kid           string           `json:"kid"`
	N             string           `json:"n"`
	E             string           `json:"e"`
	Certification *SignedStatement `json:"revoked_certification,omitempty"`
}

// Issuer returns the provider keys, loading or generating them on first use
// and certifying the signing key with the root key.
func (r *RootKey) Issuer() (*IssuerKeys, error) {
	r.issuerOnce.Do(func() {
		r.issuer, r.issuerErr = r.loadIssuer(time.Now())
	})
	return r.issuer, r.issuerErr
}

func (r *RootKey) loadIssuer(now time.Time) (*IssuerKeys, error) {
	priv, err := loadOrGenerate(filepath.Join(r.keyDir, IssuerKeyFile))
	if err != nil {
		return nil, err
	}
	secret, err := loadOrGenerateSecret(filepath.Join(r.keyDir, SubjectSecretFile))
	if err != nil {
		return nil, err
	}
	kid := JWKThumbprint(&priv.PublicKey)
	payload, err := json.Marshal(SigningKeyCertBody{
		Type:     SigningKeyCertType,
		Domain:   r.domain,
		Kid:      kid,
		Use:      "sig",
		Alg:      "RS256",
		IssuedAt: now.Unix(),
	})
	if err != nil {
		return nil, err
	}
	sig, err := r.Sign(payload)
	if err != nil {
		return nil, fmt.Errorf("server: certify signing key: %w", err)
	}
	return &IssuerKeys{
		priv:          priv,
		kid:           kid,
		subjectSecret: secret,
		certification: SignedStatement{
			Payload:   base64.RawURLEncoding.EncodeToString(payload),
			Signature: hex.EncodeToString(sig),
		},
	}, nil
}

// PrivateKey is the ID-token signing key.
func (k *IssuerKeys) PrivateKey() *rsa.PrivateKey { return k.priv }

// Kid names the signing key in token headers and the JWKS.
func (k *IssuerKeys) Kid() string { return k.kid }

// SubjectSecret is the key per-service subjects are derived with.
func (k *IssuerKeys) SubjectSecret() []byte { return k.subjectSecret }

// JWK is the published form of the signing key.
func (k *IssuerKeys) JWK() JWK {
	n, e := rsaJWKParams(&k.priv.PublicKey)
	cert := k.certification
	return JWK{Kty: "RSA", Use: "sig", Alg: "RS256", Kid: k.kid, N: n, E: e, Certification: &cert}
}

func rsaJWKParams(pub *rsa.PublicKey) (n, e string) {
	return base64.RawURLEncoding.EncodeToString(pub.N.Bytes()),
		base64.RawURLEncoding.EncodeToString(big.NewInt(int64(pub.E)).Bytes())
}

// JWKThumbprint is the RFC 7638 thumbprint of an RSA public key: the SHA-256
// of its required members in lexicographic order, base64url.
func JWKThumbprint(pub *rsa.PublicKey) string {
	n, e := rsaJWKParams(pub)
	canonical := `{"e":"` + e + `","kty":"RSA","n":"` + n + `"}`
	sum := sha256.Sum256([]byte(canonical))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

// VerifySigningKey checks a published signing key against the root key that
// claims it: the certification is the root key's signature, for this domain,
// over this key's thumbprint. rootPubPEM must already be tied to the domain
// through the DNS pin.
func VerifySigningKey(jwk JWK, rootPubPEM, expectDomain string) (SigningKeyCertBody, error) {
	if jwk.Certification == nil {
		return SigningKeyCertBody{}, errors.New("signing key: not certified")
	}
	payload, err := base64.RawURLEncoding.DecodeString(jwk.Certification.Payload)
	if err != nil {
		return SigningKeyCertBody{}, fmt.Errorf("signing key: decode payload: %w", err)
	}
	block, _ := pem.Decode([]byte(rootPubPEM))
	if block == nil {
		return SigningKeyCertBody{}, errors.New("signing key: root key is not PEM")
	}
	pubAny, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return SigningKeyCertBody{}, err
	}
	root, ok := pubAny.(*rsa.PublicKey)
	if !ok {
		return SigningKeyCertBody{}, errors.New("signing key: root key is not RSA")
	}
	sig, err := hex.DecodeString(jwk.Certification.Signature)
	if err != nil {
		return SigningKeyCertBody{}, err
	}
	digest := sha256.Sum256(payload)
	if err := rsa.VerifyPKCS1v15(root, crypto.SHA256, digest[:], sig); err != nil {
		return SigningKeyCertBody{}, fmt.Errorf("signing key: certification: %w", err)
	}
	var body SigningKeyCertBody
	if err := json.Unmarshal(payload, &body); err != nil {
		return SigningKeyCertBody{}, err
	}
	if body.Type != SigningKeyCertType || body.Domain != expectDomain {
		return SigningKeyCertBody{}, errors.New("signing key: certification is for something else")
	}

	pub, err := jwkPublicKey(jwk)
	if err != nil {
		return SigningKeyCertBody{}, err
	}
	if JWKThumbprint(pub) != body.Kid || jwk.Kid != body.Kid {
		return SigningKeyCertBody{}, errors.New("signing key: certification names another key")
	}
	return body, nil
}

// jwkPublicKey decodes an RSA JWK's modulus and exponent.
func jwkPublicKey(jwk JWK) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(jwk.N)
	if err != nil {
		return nil, err
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(jwk.E)
	if err != nil {
		return nil, err
	}
	return &rsa.PublicKey{N: new(big.Int).SetBytes(nBytes), E: int(new(big.Int).SetBytes(eBytes).Int64())}, nil
}

// loadOrGenerateSecret reads a random secret stored as PEM, generating and
// persisting one with mode 0600 if the file is absent.
func loadOrGenerateSecret(path string) ([]byte, error) {
	if data, err := os.ReadFile(path); err == nil {
		block, _ := pem.Decode(data)
		if block == nil || block.Type != pemSubjectLabel || len(block.Bytes) != subjectSecretLen {
			return nil, fmt.Errorf("server: %s is not a subject secret", path)
		}
		return block.Bytes, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("server: read %s: %w", path, err)
	}
	secret := make([]byte, subjectSecretLen)
	if _, err := rand.Read(secret); err != nil {
		return nil, err
	}
	if err := writeSecretFile(path, pem.EncodeToMemory(&pem.Block{Type: pemSubjectLabel, Bytes: secret})); err != nil {
		return nil, err
	}
	return secret, nil
}
