package server

import (
	"bytes"
	"compress/zlib"
	"crypto"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"slices"
	"sort"
	"strings"
	"time"
)

// An attestation is issued as an SD-JWT VC (RFC 9901, and the SD-JWT VC
// profile on top of it): a JWT signed by the issuer, whose claims are given
// as salted digests, followed by the disclosures that open them. The holder
// passes on only the disclosures a verifier asked for, and proves possession
// of the key the credential names by appending a Key Binding JWT.
//
//	<issuer JWT>~<disclosure>~<disclosure>~              as issued
//	<issuer JWT>~<disclosure>~<key binding JWT>           as presented
//
// The format is the standard one so that a credential issued today does not
// have to be reissued when wallets and verifiers outside Revoked are added;
// what is specific to Revoked is how the issuer's key is found and checked,
// through the DNS pin.
const (
	// CredentialTyp is the header type of a credential.
	CredentialTyp = "dc+sd-jwt"
	// credentialTypBefore is the type earlier drafts of SD-JWT VC used.
	credentialTypBefore = "vc+sd-jwt"
	// KeyBindingTyp is the header type of a Key Binding JWT.
	KeyBindingTyp = "kb+jwt"
	// StatusListTyp is the header type of a status list token.
	StatusListTyp = "statuslist+jwt"

	sdHashAlg = "sha-256"

	// ClaimHolder names the identity a credential is about. It is never
	// selectively disclosed: a verifier needs it to ask the identity's own
	// server whether that identity still stands.
	ClaimHolder = "revoked_holder"

	// PresentationMaxAge bounds how old a key binding may be. The nonce is
	// what prevents replay; this limits how long a presentation can be held
	// back before it is used.
	PresentationMaxAge = 5 * time.Minute

	// CredentialClockSkew is how far ahead of the verifier another machine's
	// clock may run, as for identity status answers.
	CredentialClockSkew = time.Minute

	// StatusListTTL is how long a verifier may keep a status list before
	// reading it again, and so the revocation latency in the usual case.
	StatusListTTL = 5 * time.Minute

	// StatusListValidity bounds how long a signed list can be replayed.
	StatusListValidity = time.Hour

	// maxStatusListBytes bounds a decompressed status list.
	maxStatusListBytes = 1 << 20
)

// Verification failures a caller reports differently from a forgery.
var (
	// ErrCredentialExpired: every signature holds and the credential's own
	// validity has ended.
	ErrCredentialExpired = errors.New("credential: expired")
	// ErrCredentialNotYetValid: the credential names a start in the future.
	ErrCredentialNotYetValid = errors.New("credential: not valid yet")
	// ErrNoKeyBinding: the presentation carries no proof of the holder's key.
	ErrNoKeyBinding = errors.New("credential: no key binding")
	// ErrCredentialSignature: the issuer's key did not sign this credential.
	// Everything else a credential can fail on is a malformed credential;
	// this one is a credential that claims an issuer it does not have.
	ErrCredentialSignature = errors.New("credential: issuer signature does not verify")
)

// HolderRef names the identity a credential is about.
type HolderRef struct {
	Fingerprint string `json:"fingerprint"`
	Domain      string `json:"domain"`
}

// StatusRef points at a credential's bit in its issuer's status list.
type StatusRef struct {
	Idx int    `json:"idx"`
	URI string `json:"uri"`
}

// CredentialSpec is what an issuer states in one credential.
type CredentialSpec struct {
	Issuer    string
	Type      string
	Holder    HolderRef
	HolderKey PublicJWK
	// Claims are each disclosed or withheld as a whole by the holder.
	Claims    map[string]any
	IssuedAt  time.Time
	ExpiresAt time.Time
	Status    *StatusRef
}

// Disclosure opens one claim of a credential.
type Disclosure struct {
	Raw    string
	Name   string
	Value  any
	Digest string
}

type jwsHeader struct {
	Alg string `json:"alg"`
	Typ string `json:"typ,omitempty"`
	Kid string `json:"kid,omitempty"`
}

// ParsedCredential is a credential or presentation taken apart, with nothing
// about it verified yet beyond its shape.
type ParsedCredential struct {
	JWT         string
	Header      jwsHeader
	Payload     map[string]any
	Disclosures []Disclosure
	KeyBinding  string
}

// CredentialVerification is what a credential states, once its issuer's
// signature has been checked.
type CredentialVerification struct {
	Issuer    string
	Type      string
	IssuedAt  time.Time
	ExpiresAt time.Time
	Holder    HolderRef
	HolderKey *PublicJWK
	Status    *StatusRef
	// Claims are the disclosed claims, together with any the issuer stated
	// in the clear.
	Claims map[string]any
	// Withheld counts the claims the credential holds that were not disclosed.
	Withheld int
}

// registeredCredentialClaims are read into fields of their own, not Claims.
var registeredCredentialClaims = []string{
	"iss", "iat", "nbf", "exp", "vct", "cnf", "status", "sub", "jti", "_sd", "_sd_alg", ClaimHolder,
}

func b64(data []byte) string { return base64.RawURLEncoding.EncodeToString(data) }

func sdDigest(s string) string {
	sum := sha256.Sum256([]byte(s))
	return b64(sum[:])
}

// SignES256 signs a JWS signing input: the raw r||s form JWS uses, not the
// ASN.1 form Go's ECDSA produces.
func SignES256(priv *ecdsa.PrivateKey, signingInput string) ([]byte, error) {
	digest := sha256.Sum256([]byte(signingInput))
	der, err := ecdsa.SignASN1(rand.Reader, priv, digest[:])
	if err != nil {
		return nil, err
	}
	var sig struct{ R, S *big.Int }
	if _, err := asn1.Unmarshal(der, &sig); err != nil {
		return nil, err
	}
	out := make([]byte, 64)
	sig.R.FillBytes(out[:32])
	sig.S.FillBytes(out[32:])
	return out, nil
}

// SignRS256 signs a JWS signing input with an RSA key.
func SignRS256(priv *rsa.PrivateKey, signingInput string) ([]byte, error) {
	digest := sha256.Sum256([]byte(signingInput))
	return rsa.SignPKCS1v15(rand.Reader, priv, crypto.SHA256, digest[:])
}

// verifyJWS checks a signature under the algorithm the header names, which
// must be the one that fits the key: ES256 for P-256, RS256 for RSA.
func verifyJWS(alg, signingInput string, sig []byte, pub crypto.PublicKey) error {
	digest := sha256.Sum256([]byte(signingInput))
	switch key := pub.(type) {
	case *ecdsa.PublicKey:
		if alg != "ES256" {
			return errors.New("jws: algorithm does not fit the key")
		}
		if len(sig) != 64 {
			return errors.New("jws: malformed ES256 signature")
		}
		der, err := asn1.Marshal(struct{ R, S *big.Int }{
			new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:]),
		})
		if err != nil {
			return err
		}
		if !ecdsa.VerifyASN1(key, digest[:], der) {
			return errors.New("jws: signature does not verify")
		}
		return nil
	case *rsa.PublicKey:
		if alg != "RS256" {
			return errors.New("jws: algorithm does not fit the key")
		}
		return rsa.VerifyPKCS1v15(key, crypto.SHA256, digest[:], sig)
	default:
		return errors.New("jws: unsupported key type")
	}
}

func encodeJWS(header jwsHeader, payload any, sign func(string) ([]byte, error)) (string, error) {
	h, err := json.Marshal(header)
	if err != nil {
		return "", err
	}
	p, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	input := b64(h) + "." + b64(p)
	sig, err := sign(input)
	if err != nil {
		return "", err
	}
	return input + "." + b64(sig), nil
}

// splitJWS takes a compact JWS apart without checking its signature.
func splitJWS(token string) (header jwsHeader, payload []byte, signingInput string, sig []byte, err error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return header, nil, "", nil, errors.New("jws: not a compact JWS")
	}
	h, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return header, nil, "", nil, errors.New("jws: malformed header")
	}
	if err := json.Unmarshal(h, &header); err != nil {
		return header, nil, "", nil, errors.New("jws: malformed header")
	}
	payload, err = base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return header, nil, "", nil, errors.New("jws: malformed payload")
	}
	sig, err = base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return header, nil, "", nil, errors.New("jws: malformed signature")
	}
	return header, payload, parts[0] + "." + parts[1], sig, nil
}

// IssueCredential signs a credential and returns it with every disclosure,
// as its holder keeps it.
func (k *CredentialKeys) IssueCredential(spec CredentialSpec) (string, error) {
	if spec.Issuer == "" || spec.Type == "" {
		return "", errors.New("credential: issuer and type are required")
	}
	if _, err := spec.HolderKey.PublicKey(); err != nil {
		return "", fmt.Errorf("credential: holder key: %w", err)
	}
	if spec.IssuedAt.IsZero() {
		return "", errors.New("credential: issue time is required")
	}

	// Only the key itself is bound: a holder key's other members say nothing
	// a verifier may rely on.
	holderKey := PublicJWK{
		Kty: spec.HolderKey.Kty, Crv: spec.HolderKey.Crv,
		X: spec.HolderKey.X, Y: spec.HolderKey.Y,
		N: spec.HolderKey.N, E: spec.HolderKey.E,
	}
	payload := map[string]any{
		"iss":       spec.Issuer,
		"iat":       spec.IssuedAt.Unix(),
		"vct":       spec.Type,
		"cnf":       map[string]any{"jwk": holderKey},
		ClaimHolder: spec.Holder,
	}
	if !spec.ExpiresAt.IsZero() {
		payload["exp"] = spec.ExpiresAt.Unix()
	}
	if spec.Status != nil {
		payload["status"] = map[string]any{"status_list": spec.Status}
	}

	names := make([]string, 0, len(spec.Claims))
	for name := range spec.Claims {
		if slices.Contains(registeredCredentialClaims, name) {
			return "", fmt.Errorf("credential: claim %q is reserved", name)
		}
		names = append(names, name)
	}
	sort.Strings(names)

	disclosures := make([]string, 0, len(names))
	digests := make([]string, 0, len(names))
	for _, name := range names {
		salt := make([]byte, 16)
		if _, err := rand.Read(salt); err != nil {
			return "", err
		}
		raw, err := json.Marshal([]any{b64(salt), name, spec.Claims[name]})
		if err != nil {
			return "", err
		}
		disclosure := b64(raw)
		disclosures = append(disclosures, disclosure)
		digests = append(digests, sdDigest(disclosure))
	}
	if len(digests) > 0 {
		// Sorted, so the order of the digests says nothing about the claims.
		sort.Strings(digests)
		payload["_sd"] = digests
		payload["_sd_alg"] = sdHashAlg
	}

	jwt, err := encodeJWS(jwsHeader{Alg: "ES256", Typ: CredentialTyp, Kid: k.kid}, payload,
		func(input string) ([]byte, error) { return SignES256(k.priv, input) })
	if err != nil {
		return "", err
	}
	return jwt + "~" + strings.Join(disclosures, "~") + tildeAfter(disclosures), nil
}

func tildeAfter(disclosures []string) string {
	if len(disclosures) == 0 {
		return ""
	}
	return "~"
}

// ParseCredential takes a credential or a presentation apart and checks that
// its disclosures belong to it: each opens exactly one digest the issuer
// signed, none is given twice, and none names a claim the issuer stated in
// the clear. No signature is checked here.
func ParseCredential(s string) (*ParsedCredential, error) {
	parts := strings.Split(s, "~")
	if len(parts) < 2 {
		return nil, errors.New("credential: not an SD-JWT")
	}
	p := &ParsedCredential{JWT: parts[0], KeyBinding: parts[len(parts)-1]}
	header, rawPayload, _, _, err := splitJWS(p.JWT)
	if err != nil {
		return nil, fmt.Errorf("credential: %w", err)
	}
	p.Header = header
	if err := json.Unmarshal(rawPayload, &p.Payload); err != nil || p.Payload == nil {
		return nil, errors.New("credential: malformed payload")
	}
	if alg, present := p.Payload["_sd_alg"]; present && alg != sdHashAlg {
		return nil, errors.New("credential: unsupported digest algorithm")
	}

	signed := map[string]bool{}
	if raw, present := p.Payload["_sd"]; present {
		list, ok := raw.([]any)
		if !ok {
			return nil, errors.New("credential: malformed _sd")
		}
		for _, item := range list {
			digest, ok := item.(string)
			if !ok || signed[digest] {
				return nil, errors.New("credential: malformed _sd")
			}
			signed[digest] = true
		}
	}

	opened := map[string]bool{}
	names := map[string]bool{}
	for _, raw := range parts[1 : len(parts)-1] {
		if raw == "" {
			return nil, errors.New("credential: empty disclosure")
		}
		decoded, err := base64.RawURLEncoding.DecodeString(raw)
		if err != nil {
			return nil, errors.New("credential: malformed disclosure")
		}
		var fields []any
		if err := json.Unmarshal(decoded, &fields); err != nil || len(fields) != 3 {
			return nil, errors.New("credential: malformed disclosure")
		}
		name, ok := fields[1].(string)
		if _, saltOK := fields[0].(string); !ok || !saltOK {
			return nil, errors.New("credential: malformed disclosure")
		}
		digest := sdDigest(raw)
		if !signed[digest] {
			return nil, errors.New("credential: a disclosure does not belong to this credential")
		}
		if opened[digest] || names[name] {
			return nil, errors.New("credential: a disclosure is given twice")
		}
		if _, clash := p.Payload[name]; clash || name == "_sd" || name == "..." {
			return nil, errors.New("credential: a disclosure names a claim it may not")
		}
		opened[digest], names[name] = true, true
		p.Disclosures = append(p.Disclosures, Disclosure{Raw: raw, Name: name, Value: fields[2], Digest: digest})
	}
	return p, nil
}

// signedPart is what a key binding commits to: the issuer's JWT and exactly
// the disclosures presented with it.
func (p *ParsedCredential) signedPart() string {
	var b strings.Builder
	b.WriteString(p.JWT)
	b.WriteString("~")
	for _, d := range p.Disclosures {
		b.WriteString(d.Raw)
		b.WriteString("~")
	}
	return b.String()
}

func numericDate(payload map[string]any, name string) (time.Time, bool, error) {
	raw, present := payload[name]
	if !present {
		return time.Time{}, false, nil
	}
	n, ok := raw.(float64)
	if !ok {
		return time.Time{}, false, fmt.Errorf("credential: malformed %s", name)
	}
	return time.Unix(int64(n), 0), true, nil
}

// reencode reads one decoded JSON member into a typed value.
func reencode(from any, into any) error {
	raw, err := json.Marshal(from)
	if err != nil {
		return err
	}
	return json.Unmarshal(raw, into)
}

// VerifyCredential checks the issuer's signature and the credential's own
// validity, and returns what it states. issuerKey must already be tied to the
// issuer the credential names; this checks that the key signed it, not that
// the key deserves to be believed.
//
// An expired credential is reported as [ErrCredentialExpired] together with
// what it states, so a caller can say what ran out.
func VerifyCredential(p *ParsedCredential, issuerKey *ecdsa.PublicKey, now time.Time) (CredentialVerification, error) {
	var out CredentialVerification
	if p.Header.Typ != CredentialTyp && p.Header.Typ != credentialTypBefore {
		return out, errors.New("credential: not an SD-JWT credential")
	}
	_, _, signingInput, sig, err := splitJWS(p.JWT)
	if err != nil {
		return out, err
	}
	if err := verifyJWS(p.Header.Alg, signingInput, sig, issuerKey); err != nil {
		return out, fmt.Errorf("%w: %v", ErrCredentialSignature, err)
	}

	out.Issuer, _ = p.Payload["iss"].(string)
	out.Type, _ = p.Payload["vct"].(string)
	if out.Issuer == "" || out.Type == "" {
		return out, errors.New("credential: issuer and type are required")
	}
	if raw, present := p.Payload["cnf"]; present {
		var cnf struct {
			JWK *PublicJWK `json:"jwk"`
		}
		if err := reencode(raw, &cnf); err != nil || cnf.JWK == nil {
			return out, errors.New("credential: malformed cnf")
		}
		if _, err := cnf.JWK.PublicKey(); err != nil {
			return out, fmt.Errorf("credential: holder key: %w", err)
		}
		out.HolderKey = cnf.JWK
	}
	if raw, present := p.Payload["status"]; present {
		var status struct {
			List *StatusRef `json:"status_list"`
		}
		if err := reencode(raw, &status); err != nil {
			return out, errors.New("credential: malformed status")
		}
		if status.List != nil && (status.List.URI == "" || status.List.Idx < 0) {
			return out, errors.New("credential: malformed status")
		}
		out.Status = status.List
	}
	if raw, present := p.Payload[ClaimHolder]; present {
		if err := reencode(raw, &out.Holder); err != nil {
			return out, errors.New("credential: malformed holder")
		}
	}

	out.Claims = map[string]any{}
	for name, value := range p.Payload {
		if !slices.Contains(registeredCredentialClaims, name) {
			out.Claims[name] = value
		}
	}
	for _, d := range p.Disclosures {
		out.Claims[d.Name] = d.Value
	}
	if list, ok := p.Payload["_sd"].([]any); ok {
		out.Withheld = len(list) - len(p.Disclosures)
	}

	issued, present, err := numericDate(p.Payload, "iat")
	if err != nil {
		return out, err
	}
	if present {
		out.IssuedAt = issued
		if issued.After(now.Add(CredentialClockSkew)) {
			return out, ErrCredentialNotYetValid
		}
	}
	notBefore, present, err := numericDate(p.Payload, "nbf")
	if err != nil {
		return out, err
	}
	if present && notBefore.After(now.Add(CredentialClockSkew)) {
		return out, ErrCredentialNotYetValid
	}
	expires, present, err := numericDate(p.Payload, "exp")
	if err != nil {
		return out, err
	}
	if present {
		out.ExpiresAt = expires
		if !expires.After(now) {
			return out, ErrCredentialExpired
		}
	}
	return out, nil
}

// VerifyKeyBinding checks that a presentation was made by the holder of the
// key the credential names, for this verifier and this occasion: the key
// binding is signed with that key, commits to exactly the disclosures
// presented, names the audience, carries the verifier's nonce, and is fresh.
func VerifyKeyBinding(p *ParsedCredential, holderKey PublicJWK, audience, nonce string, now time.Time) error {
	if p.KeyBinding == "" {
		return ErrNoKeyBinding
	}
	if audience == "" || nonce == "" {
		return errors.New("key binding: an audience and a nonce are required to check it")
	}
	pub, err := holderKey.PublicKey()
	if err != nil {
		return fmt.Errorf("key binding: holder key: %w", err)
	}
	header, rawPayload, signingInput, sig, err := splitJWS(p.KeyBinding)
	if err != nil {
		return fmt.Errorf("key binding: %w", err)
	}
	if header.Typ != KeyBindingTyp {
		return errors.New("key binding: wrong type")
	}
	if err := verifyJWS(header.Alg, signingInput, sig, pub); err != nil {
		return fmt.Errorf("key binding: %w", err)
	}
	var body struct {
		IssuedAt *float64 `json:"iat"`
		Audience string   `json:"aud"`
		Nonce    string   `json:"nonce"`
		SDHash   string   `json:"sd_hash"`
	}
	if err := json.Unmarshal(rawPayload, &body); err != nil || body.IssuedAt == nil {
		return errors.New("key binding: malformed payload")
	}
	if body.SDHash != sdDigest(p.signedPart()) {
		return errors.New("key binding: made for other disclosures")
	}
	if body.Audience != audience {
		return errors.New("key binding: made for another verifier")
	}
	if body.Nonce != nonce {
		return errors.New("key binding: made for another occasion")
	}
	issued := time.Unix(int64(*body.IssuedAt), 0)
	if issued.After(now.Add(CredentialClockSkew)) {
		return errors.New("key binding: made in the future")
	}
	if now.Sub(issued) > PresentationMaxAge {
		return errors.New("key binding: too old")
	}
	return nil
}

// PresentCredential is the holder's side: it keeps the disclosures named in
// disclose, drops the others, and appends a key binding made with sign. The
// app does the same on the device, where the identity key is; this exists so
// the two sides are written against one description, and for the tests.
//
// alg is ES256 for a P-256 identity key and RS256 for an RSA one.
func PresentCredential(credential string, disclose []string, audience, nonce, alg string, now time.Time,
	sign func(signingInput string) ([]byte, error),
) (string, error) {
	p, err := ParseCredential(credential)
	if err != nil {
		return "", err
	}
	kept := p.Disclosures[:0:0]
	for _, d := range p.Disclosures {
		if slices.Contains(disclose, d.Name) {
			kept = append(kept, d)
		}
	}
	if len(kept) != len(disclose) {
		return "", errors.New("credential: it holds no such claim to disclose")
	}
	p.Disclosures = kept
	signed := p.signedPart()
	binding, err := encodeJWS(jwsHeader{Alg: alg, Typ: KeyBindingTyp}, map[string]any{
		"iat":     now.Unix(),
		"aud":     audience,
		"nonce":   nonce,
		"sd_hash": sdDigest(signed),
	}, sign)
	if err != nil {
		return "", err
	}
	return signed + binding, nil
}

// StatusList is the published revocation state of an issuer's credentials:
// one bit each, set when the credential was revoked.
type StatusList struct {
	bits []byte
}

// NewStatusList makes a list of size bits, all valid.
func NewStatusList(size int) StatusList {
	return StatusList{bits: make([]byte, (size+7)/8)}
}

// Len is the number of positions in the list.
func (l StatusList) Len() int { return len(l.bits) * 8 }

// Revoke sets a position. Positions are packed from the least significant
// bit of each byte, as the Token Status List specification defines.
func (l StatusList) Revoke(idx int) {
	if idx >= 0 && idx < l.Len() {
		l.bits[idx/8] |= 1 << (idx % 8)
	}
}

// Revoked reads a position. known is false when the list does not reach it:
// no statement can then be made, which is not the same as revoked.
func (l StatusList) Revoked(idx int) (revoked, known bool) {
	if idx < 0 || idx >= l.Len() {
		return false, false
	}
	return l.bits[idx/8]&(1<<(idx%8)) != 0, true
}

// SignStatusList publishes a list as a status list token for uri.
func (k *CredentialKeys) SignStatusList(uri string, list StatusList, now time.Time) (string, error) {
	var compressed bytes.Buffer
	w := zlib.NewWriter(&compressed)
	if _, err := w.Write(list.bits); err != nil {
		return "", err
	}
	if err := w.Close(); err != nil {
		return "", err
	}
	return encodeJWS(jwsHeader{Alg: "ES256", Typ: StatusListTyp, Kid: k.kid}, map[string]any{
		"sub": uri,
		"iat": now.Unix(),
		"exp": now.Add(StatusListValidity).Unix(),
		"ttl": int(StatusListTTL.Seconds()),
		"status_list": map[string]any{
			"bits": 1,
			"lst":  b64(compressed.Bytes()),
		},
	}, func(input string) ([]byte, error) { return SignES256(k.priv, input) })
}

// VerifyStatusList checks a status list token against the issuer's key and
// the address the credential named, and returns the list with how long it
// may be kept.
func VerifyStatusList(token string, issuerKey *ecdsa.PublicKey, expectURI string, now time.Time) (StatusList, time.Duration, error) {
	header, rawPayload, signingInput, sig, err := splitJWS(token)
	if err != nil {
		return StatusList{}, 0, fmt.Errorf("status list: %w", err)
	}
	if header.Typ != StatusListTyp {
		return StatusList{}, 0, errors.New("status list: wrong type")
	}
	if err := verifyJWS(header.Alg, signingInput, sig, issuerKey); err != nil {
		return StatusList{}, 0, fmt.Errorf("status list: %w", err)
	}
	var body struct {
		Subject  string   `json:"sub"`
		IssuedAt *float64 `json:"iat"`
		Expires  *float64 `json:"exp"`
		TTL      *float64 `json:"ttl"`
		List     struct {
			Bits int    `json:"bits"`
			Lst  string `json:"lst"`
		} `json:"status_list"`
	}
	if err := json.Unmarshal(rawPayload, &body); err != nil || body.IssuedAt == nil {
		return StatusList{}, 0, errors.New("status list: malformed payload")
	}
	if body.Subject != expectURI {
		return StatusList{}, 0, errors.New("status list: published for another address")
	}
	if time.Unix(int64(*body.IssuedAt), 0).After(now.Add(CredentialClockSkew)) {
		return StatusList{}, 0, errors.New("status list: issued in the future")
	}
	if body.Expires != nil && !time.Unix(int64(*body.Expires), 0).After(now) {
		return StatusList{}, 0, errors.New("status list: expired")
	}
	if body.List.Bits != 1 {
		return StatusList{}, 0, errors.New("status list: only one bit per credential is supported")
	}
	compressed, err := base64.RawURLEncoding.DecodeString(body.List.Lst)
	if err != nil {
		return StatusList{}, 0, errors.New("status list: malformed list")
	}
	r, err := zlib.NewReader(bytes.NewReader(compressed))
	if err != nil {
		return StatusList{}, 0, errors.New("status list: malformed list")
	}
	defer r.Close()
	bits, err := io.ReadAll(io.LimitReader(r, maxStatusListBytes+1))
	if err != nil || len(bits) > maxStatusListBytes {
		return StatusList{}, 0, errors.New("status list: malformed or oversized list")
	}
	ttl := StatusListTTL
	if body.TTL != nil && *body.TTL >= 0 {
		ttl = time.Duration(*body.TTL) * time.Second
	}
	return StatusList{bits: bits}, ttl, nil
}
