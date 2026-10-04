package server

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
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
	// CredentialKeyFile holds the key credentials and their status lists are
	// signed with. The root key is RSA, while the credential formats this
	// server issues are verified with ES256, so issuing has a key of its own:
	// ECDSA P-256, certified by the root key like the ID-token key is.
	CredentialKeyFile = "credential_signing.pem"

	// CredentialKeyCertType is the domain separator for the certification of a
	// credential key. It differs from [SigningKeyCertType] so that a key
	// certified for one purpose is never accepted for the other.
	CredentialKeyCertType = "credential-key-v1"

	pemECPrivateLabel = "EC PRIVATE KEY"
)

// CredentialKeys are what this server signs attestations with.
type CredentialKeys struct {
	priv          *ecdsa.PrivateKey
	kid           string
	certification SignedStatement
}

// PublicJWK is a public key as a JSON Web Key: the holder's key inside a
// credential (cnf), or the issuer's published key. An issuer's key also
// carries the root key's certification of it.
type PublicJWK struct {
	Kty           string           `json:"kty"`
	Crv           string           `json:"crv,omitempty"`
	X             string           `json:"x,omitempty"`
	Y             string           `json:"y,omitempty"`
	N             string           `json:"n,omitempty"`
	E             string           `json:"e,omitempty"`
	Use           string           `json:"use,omitempty"`
	Alg           string           `json:"alg,omitempty"`
	Kid           string           `json:"kid,omitempty"`
	Certification *SignedStatement `json:"revoked_certification,omitempty"`
}

// Credentials returns the credential keys, loading or generating them on
// first use and certifying the key with the root key.
func (r *RootKey) Credentials() (*CredentialKeys, error) {
	r.credentialOnce.Do(func() {
		r.credential, r.credentialErr = r.loadCredentialKeys(time.Now())
	})
	return r.credential, r.credentialErr
}

func (r *RootKey) loadCredentialKeys(now time.Time) (*CredentialKeys, error) {
	priv, err := loadOrGenerateECKey(filepath.Join(r.keyDir, CredentialKeyFile))
	if err != nil {
		return nil, err
	}
	jwk, err := JWKFromPublicKey(&priv.PublicKey)
	if err != nil {
		return nil, err
	}
	kid, err := jwk.Thumbprint()
	if err != nil {
		return nil, err
	}
	payload, err := json.Marshal(SigningKeyCertBody{
		Type:     CredentialKeyCertType,
		Domain:   r.domain,
		Kid:      kid,
		Use:      "sig",
		Alg:      "ES256",
		IssuedAt: now.Unix(),
	})
	if err != nil {
		return nil, err
	}
	sig, err := r.Sign(payload)
	if err != nil {
		return nil, fmt.Errorf("server: certify credential key: %w", err)
	}
	return &CredentialKeys{
		priv: priv,
		kid:  kid,
		certification: SignedStatement{
			Payload:   base64.RawURLEncoding.EncodeToString(payload),
			Signature: hex.EncodeToString(sig),
		},
	}, nil
}

// Kid names the credential key in token headers and the issuer metadata.
func (k *CredentialKeys) Kid() string { return k.kid }

// PublicKey is the key credentials verify under.
func (k *CredentialKeys) PublicKey() *ecdsa.PublicKey { return &k.priv.PublicKey }

// JWK is the published form of the credential key.
func (k *CredentialKeys) JWK() PublicJWK {
	jwk, _ := JWKFromPublicKey(&k.priv.PublicKey)
	cert := k.certification
	jwk.Use, jwk.Alg, jwk.Kid, jwk.Certification = "sig", "ES256", k.kid, &cert
	return jwk
}

// JWKFromPublicKey encodes an ECDSA P-256 or RSA public key. Those are the
// two kinds of key an identity can have.
func JWKFromPublicKey(pub crypto.PublicKey) (PublicJWK, error) {
	switch key := pub.(type) {
	case *ecdsa.PublicKey:
		if key.Curve != elliptic.P256() {
			return PublicJWK{}, errors.New("jwk: only the P-256 curve is supported")
		}
		point, err := key.Bytes()
		if err != nil || len(point) != 65 || point[0] != 4 {
			return PublicJWK{}, errors.New("jwk: malformed P-256 key")
		}
		return PublicJWK{
			Kty: "EC",
			Crv: "P-256",
			X:   base64.RawURLEncoding.EncodeToString(point[1:33]),
			Y:   base64.RawURLEncoding.EncodeToString(point[33:]),
		}, nil
	case *rsa.PublicKey:
		n, e := rsaJWKParams(key)
		return PublicJWK{Kty: "RSA", N: n, E: e}, nil
	default:
		return PublicJWK{}, errors.New("jwk: unsupported key type")
	}
}

// PublicKey decodes the key a JWK describes.
func (j PublicJWK) PublicKey() (crypto.PublicKey, error) {
	switch j.Kty {
	case "EC":
		if j.Crv != "P-256" {
			return nil, errors.New("jwk: only the P-256 curve is supported")
		}
		x, err := base64.RawURLEncoding.DecodeString(j.X)
		if err != nil || len(x) != 32 {
			return nil, errors.New("jwk: malformed x")
		}
		y, err := base64.RawURLEncoding.DecodeString(j.Y)
		if err != nil || len(y) != 32 {
			return nil, errors.New("jwk: malformed y")
		}
		point := append(append([]byte{4}, x...), y...)
		return ecdsa.ParseUncompressedPublicKey(elliptic.P256(), point)
	case "RSA":
		n, err := base64.RawURLEncoding.DecodeString(j.N)
		if err != nil || len(n) < 256 {
			return nil, errors.New("jwk: malformed modulus")
		}
		e, err := base64.RawURLEncoding.DecodeString(j.E)
		if err != nil || len(e) == 0 || len(e) > 4 {
			return nil, errors.New("jwk: malformed exponent")
		}
		return &rsa.PublicKey{N: new(big.Int).SetBytes(n), E: int(new(big.Int).SetBytes(e).Int64())}, nil
	default:
		return nil, errors.New("jwk: unsupported key type")
	}
}

// Thumbprint is the RFC 7638 thumbprint: the SHA-256 of the key's required
// members in lexicographic order, base64url.
func (j PublicJWK) Thumbprint() (string, error) {
	var canonical string
	switch j.Kty {
	case "EC":
		canonical = `{"crv":"` + j.Crv + `","kty":"EC","x":"` + j.X + `","y":"` + j.Y + `"}`
	case "RSA":
		canonical = `{"e":"` + j.E + `","kty":"RSA","n":"` + j.N + `"}`
	default:
		return "", errors.New("jwk: unsupported key type")
	}
	sum := sha256.Sum256([]byte(canonical))
	return base64.RawURLEncoding.EncodeToString(sum[:]), nil
}

// SameKey reports whether two JWKs describe the same public key.
func (j PublicJWK) SameKey(other PublicJWK) bool {
	a, errA := j.Thumbprint()
	b, errB := other.Thumbprint()
	return errA == nil && errB == nil && a == b
}

// VerifyCredentialKey checks a published credential key against the root key
// that claims it: the certification is the root key's signature, for this
// domain, over this key's thumbprint, and it is a certification for issuing
// credentials rather than for anything else. rootPubPEM must already be tied
// to the domain through the DNS pin.
func VerifyCredentialKey(jwk PublicJWK, rootPubPEM, expectDomain string) (*ecdsa.PublicKey, error) {
	if jwk.Certification == nil {
		return nil, errors.New("credential key: not certified")
	}
	payload, err := base64.RawURLEncoding.DecodeString(jwk.Certification.Payload)
	if err != nil {
		return nil, fmt.Errorf("credential key: decode payload: %w", err)
	}
	sig, err := hex.DecodeString(jwk.Certification.Signature)
	if err != nil {
		return nil, fmt.Errorf("credential key: decode signature: %w", err)
	}
	if err := verifyRootSignature(rootPubPEM, payload, sig); err != nil {
		return nil, fmt.Errorf("credential key: certification: %w", err)
	}
	var body SigningKeyCertBody
	if err := json.Unmarshal(payload, &body); err != nil {
		return nil, err
	}
	if body.Type != CredentialKeyCertType || body.Domain != expectDomain || body.Alg != "ES256" {
		return nil, errors.New("credential key: certification is for something else")
	}
	thumbprint, err := jwk.Thumbprint()
	if err != nil {
		return nil, err
	}
	if thumbprint != body.Kid || jwk.Kid != body.Kid {
		return nil, errors.New("credential key: certification names another key")
	}
	pub, err := jwk.PublicKey()
	if err != nil {
		return nil, err
	}
	ec, ok := pub.(*ecdsa.PublicKey)
	if !ok {
		return nil, errors.New("credential key: not an ECDSA key")
	}
	return ec, nil
}

// verifyRootSignature checks a root key's PKCS#1 v1.5 signature over the
// SHA-256 of payload.
func verifyRootSignature(rootPubPEM string, payload, sig []byte) error {
	block, _ := pem.Decode([]byte(rootPubPEM))
	if block == nil {
		return errors.New("root key is not PEM")
	}
	pubAny, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return err
	}
	root, ok := pubAny.(*rsa.PublicKey)
	if !ok {
		return errors.New("root key is not RSA")
	}
	digest := sha256.Sum256(payload)
	return rsa.VerifyPKCS1v15(root, crypto.SHA256, digest[:], sig)
}

// loadOrGenerateECKey reads a P-256 key stored as PEM, generating and
// persisting one with mode 0600 if the file is absent.
func loadOrGenerateECKey(path string) (*ecdsa.PrivateKey, error) {
	if data, err := os.ReadFile(path); err == nil {
		block, _ := pem.Decode(data)
		if block == nil || block.Type != pemECPrivateLabel {
			return nil, fmt.Errorf("server: %s is not an EC private key", path)
		}
		priv, err := x509.ParseECPrivateKey(block.Bytes)
		if err != nil {
			return nil, fmt.Errorf("server: parse %s: %w", path, err)
		}
		if priv.Curve != elliptic.P256() {
			return nil, fmt.Errorf("server: %s is not a P-256 key", path)
		}
		return priv, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("server: read %s: %w", path, err)
	}
	priv, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("server: generate credential key: %w", err)
	}
	der, err := x509.MarshalECPrivateKey(priv)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, fmt.Errorf("server: mkdir %s: %w", filepath.Dir(path), err)
	}
	if err := writeSecretFile(path, pem.EncodeToMemory(&pem.Block{Type: pemECPrivateLabel, Bytes: der})); err != nil {
		return nil, err
	}
	return priv, nil
}
