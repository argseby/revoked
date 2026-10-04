//go:build ignore

// Emits a credential the real server code issued, with the holder key it is
// bound to, as a fixture for the Dart tests: the app builds a presentation
// from it and must arrive at the bytes the server would check.
//
// The reverse direction is app/tool/gen_presentation_fixture.dart, which
// presents this credential with the app's own code; the Go tests verify the
// result. The holder's private key is needed for that one step and is
// written to the file named as the first argument, never into a fixture.
// Refresh both together with app/tool/gen_sd_jwt_fixture.sh.
package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"revoked/cmd/revoked/server"
)

func main() {
	dir, err := os.MkdirTemp("", "revoked-sd-jwt-fixture")
	if err != nil {
		panic(err)
	}
	defer os.RemoveAll(dir)

	root, err := server.Load("fixture.test", filepath.Join(dir, "root.pem"))
	if err != nil {
		panic(err)
	}
	keys, err := root.Credentials()
	if err != nil {
		panic(err)
	}

	holder, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		panic(err)
	}
	holderDER, err := x509.MarshalECPrivateKey(holder)
	if err != nil {
		panic(err)
	}
	holderJWK, err := server.JWKFromPublicKey(&holder.PublicKey)
	if err != nil {
		panic(err)
	}

	issuedAt := time.Unix(1_800_000_000, 0)
	credential, err := keys.IssueCredential(server.CredentialSpec{
		Issuer:    "https://fixture.test",
		Type:      "membership",
		Holder:    server.HolderRef{Fingerprint: strings.Repeat("ab", 32), Domain: "home.test"},
		HolderKey: holderJWK,
		Claims:    map[string]any{"name": "Ada Lovelace", "age_over_18": true, "member_no": 42},
		IssuedAt:  issuedAt,
		Status:    &server.StatusRef{Idx: 7, URI: "https://fixture.test/api/attestations/status"},
	})
	if err != nil {
		panic(err)
	}

	// What a key binding over the one disclosed claim commits to, computed
	// here so the app's own computation has something to be compared with.
	disclose := []string{"age_over_18"}
	parsed, err := server.ParseCredential(credential)
	if err != nil {
		panic(err)
	}
	signedPart := parsed.JWT + "~"
	for _, d := range parsed.Disclosures {
		if d.Name == disclose[0] {
			signedPart += d.Raw + "~"
		}
	}
	sum := sha256.Sum256([]byte(signedPart))

	if len(os.Args) < 2 {
		panic("usage: gen_sd_jwt_fixture.go <file for the holder key>")
	}
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: holderDER})
	if err := os.WriteFile(os.Args[1], keyPEM, 0o600); err != nil {
		panic(err)
	}

	out, _ := json.MarshalIndent(map[string]any{
		"issuerJwk":    keys.JWK(),
		"credential":   credential,
		"holderJwk":    holderJWK,
		"issuedAtUnix": issuedAt.Unix(),
		"disclose":     disclose,
		"audience":     "https://shop.test",
		"nonce":        "fixture-nonce-1",
		"signedPart":   signedPart,
		"sdHash":       base64.RawURLEncoding.EncodeToString(sum[:]),
	}, "", "  ")
	fmt.Println(string(out))
}
