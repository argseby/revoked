package server

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

// ReissueVoucherType is the domain separator for a reissue voucher, and the
// reason it is the first field of the signed JSON.
//
// An identity key signs three other things: challenge nonces (bare tokens),
// sign-in consents (a fixed prefix and a ticket), and key binding JWTs (a JWS
// signing input, base64url.base64url) — none of which starts with a brace.
// A voucher is the one statement that hands
// authority to another key, so it must be unmistakable for a signature made
// for any other purpose, and no signature made for another purpose may pass
// as one. The app refuses to sign a nonce that is not a token, which keeps a
// server from presenting a voucher body as a challenge.
const ReissueVoucherType = "credential-reissue-v1"

// maxVoucherPayload bounds what is decoded as a voucher.
const maxVoucherPayload = 2048

// ReissueVoucherBody is what the old identity key signs: that the identity
// named new takes over the credential the issuer named issuer gave old, on
// the occasion of the issuer's challenge nonce. The nonce is spent at the
// issuer, so one voucher moves one credential once.
type ReissueVoucherBody struct {
	Type           string `json:"type"`
	Issuer         string `json:"issuer"`
	OldFingerprint string `json:"oldFingerprint"`
	NewFingerprint string `json:"newFingerprint"`
	Nonce          string `json:"nonce"`
}

// ReissueVoucher is the wire form: the exact bytes that were signed,
// base64url without padding, and the signature over their SHA-256 in the
// encoding challenge signatures use — base64 of PKCS#1 v1.5 for an RSA key,
// of ASN.1 DER for an ECDSA one.
//
// As with [IdentityStatusAssertion], the encoding is transmitted rather than
// the decoded object, so the app and the server never have to agree on field
// order or spacing.
type ReissueVoucher struct {
	Payload   string `json:"payload"`
	Signature string `json:"signature"`
}

// SignReissueVoucher is the holder's side. The app does the same on the
// device, where the old identity key is; this exists so both sides are
// written against one description, and for the tests. sign receives the
// payload bytes and returns the raw signature.
func SignReissueVoucher(body ReissueVoucherBody, sign func(payload []byte) ([]byte, error)) (ReissueVoucher, error) {
	body.Type = ReissueVoucherType
	payload, err := json.Marshal(body)
	if err != nil {
		return ReissueVoucher{}, err
	}
	sig, err := sign(payload)
	if err != nil {
		return ReissueVoucher{}, err
	}
	return ReissueVoucher{
		Payload:   base64.RawURLEncoding.EncodeToString(payload),
		Signature: base64.StdEncoding.EncodeToString(sig),
	}, nil
}

// VerifyReissueVoucher checks that oldKey — the key the credential names in
// cnf — signed a voucher stating exactly expect. The signature is checked
// over the transmitted bytes before they are parsed, and every comparison
// reads the body that came out of those bytes.
func VerifyReissueVoucher(v ReissueVoucher, oldKey PublicJWK, expect ReissueVoucherBody) error {
	if len(v.Payload) > maxVoucherPayload || v.Payload == "" || v.Signature == "" {
		return errors.New("reissue voucher: missing or oversized")
	}
	payload, err := base64.RawURLEncoding.DecodeString(v.Payload)
	if err != nil {
		return fmt.Errorf("reissue voucher: decode payload: %w", err)
	}
	sig, err := base64.StdEncoding.DecodeString(v.Signature)
	if err != nil {
		if sig, err = base64.RawStdEncoding.DecodeString(v.Signature); err != nil {
			return fmt.Errorf("reissue voucher: decode signature: %w", err)
		}
	}
	pub, err := oldKey.PublicKey()
	if err != nil {
		return fmt.Errorf("reissue voucher: old key: %w", err)
	}
	digest := sha256.Sum256(payload)
	switch key := pub.(type) {
	case *rsa.PublicKey:
		if err := rsa.VerifyPKCS1v15(key, crypto.SHA256, digest[:], sig); err != nil {
			return fmt.Errorf("reissue voucher: signature: %w", err)
		}
	case *ecdsa.PublicKey:
		if !ecdsa.VerifyASN1(key, digest[:], sig) {
			return errors.New("reissue voucher: signature does not verify")
		}
	default:
		return errors.New("reissue voucher: unsupported key type")
	}

	var body ReissueVoucherBody
	if err := json.Unmarshal(payload, &body); err != nil {
		return fmt.Errorf("reissue voucher: parse payload: %w", err)
	}
	if body.Type != ReissueVoucherType {
		return errors.New("reissue voucher: wrong or missing type")
	}
	if !strings.EqualFold(body.Issuer, expect.Issuer) {
		return errors.New("reissue voucher: made for another issuer")
	}
	if !strings.EqualFold(body.OldFingerprint, expect.OldFingerprint) {
		return errors.New("reissue voucher: made for another credential holder")
	}
	if !strings.EqualFold(body.NewFingerprint, expect.NewFingerprint) {
		return errors.New("reissue voucher: names another identity")
	}
	if body.Nonce == "" || body.Nonce != expect.Nonce {
		return errors.New("reissue voucher: made for another occasion")
	}
	return nil
}
