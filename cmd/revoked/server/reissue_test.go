package server

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"strings"
	"testing"
)

func voucherKey(t *testing.T) (*ecdsa.PrivateKey, PublicJWK) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	jwk, err := JWKFromPublicKey(&key.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	return key, jwk
}

func signWith(key *ecdsa.PrivateKey) func([]byte) ([]byte, error) {
	return func(payload []byte) ([]byte, error) {
		digest := sha256.Sum256(payload)
		return ecdsa.SignASN1(rand.Reader, key, digest[:])
	}
}

func TestReissueVoucher(t *testing.T) {
	key, jwk := voucherKey(t)
	newFingerprint := strings.Repeat("b", 64)
	expect := ReissueVoucherBody{
		Issuer: "club.example", OldFingerprint: sampleFingerprint,
		NewFingerprint: newFingerprint, Nonce: "nonce-0123456789abcdef",
	}
	voucher, err := SignReissueVoucher(expect, signWith(key))
	if err != nil {
		t.Fatal(err)
	}

	if err := VerifyReissueVoucher(voucher, jwk, expect); err != nil {
		t.Fatalf("a voucher did not verify: %v", err)
	}

	t.Run("under another key", func(t *testing.T) {
		_, other := voucherKey(t)
		if VerifyReissueVoucher(voucher, other, expect) == nil {
			t.Fatal("accepted under a key that did not sign it")
		}
	})

	t.Run("for anything other than what it states", func(t *testing.T) {
		for name, change := range map[string]func(*ReissueVoucherBody){
			"issuer":    func(b *ReissueVoucherBody) { b.Issuer = "other.example" },
			"old":       func(b *ReissueVoucherBody) { b.OldFingerprint = strings.Repeat("c", 64) },
			"new":       func(b *ReissueVoucherBody) { b.NewFingerprint = strings.Repeat("d", 64) },
			"nonce":     func(b *ReissueVoucherBody) { b.Nonce = "another-nonce-0123456" },
			"no nonce":  func(b *ReissueVoucherBody) { b.Nonce = "" },
			"no issuer": func(b *ReissueVoucherBody) { b.Issuer = "" },
		} {
			want := expect
			change(&want)
			if VerifyReissueVoucher(voucher, jwk, want) == nil {
				t.Errorf("%s: accepted a voucher that states something else", name)
			}
		}
	})

	t.Run("with its bytes changed after signing", func(t *testing.T) {
		raw, _ := base64.RawURLEncoding.DecodeString(voucher.Payload)
		tampered := voucher
		tampered.Payload = base64.RawURLEncoding.EncodeToString(
			[]byte(strings.Replace(string(raw), newFingerprint, strings.Repeat("e", 64), 1)))
		want := expect
		want.NewFingerprint = strings.Repeat("e", 64)
		if VerifyReissueVoucher(tampered, jwk, want) == nil {
			t.Fatal("accepted a payload the key did not sign")
		}
	})

	// The same key signs challenge nonces. A signature over anything without
	// the voucher's type tag — a nonce, or a body of the same shape made for
	// another purpose — must not pass as a voucher.
	t.Run("without its type", func(t *testing.T) {
		for name, payload := range map[string]string{
			"a bare nonce": expect.Nonce,
			"an untyped body": `{"issuer":"club.example","oldFingerprint":"` + sampleFingerprint +
				`","newFingerprint":"` + newFingerprint + `","nonce":"` + expect.Nonce + `"}`,
		} {
			sig, err := signWith(key)([]byte(payload))
			if err != nil {
				t.Fatal(err)
			}
			forged := ReissueVoucher{
				Payload:   base64.RawURLEncoding.EncodeToString([]byte(payload)),
				Signature: base64.StdEncoding.EncodeToString(sig),
			}
			if VerifyReissueVoucher(forged, jwk, expect) == nil {
				t.Errorf("%s passed as a voucher", name)
			}
		}
	})
}
