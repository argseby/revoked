//go:build ignore

// Emits real IssueIdentityStatus output, used as a fixture by the Dart tests so
// the client verifier is checked against bytes the Go server actually produced.
//
// The two implementations agree on a signed representation or they agree on
// nothing, and a disagreement presents as a working key that signs nothing
// anyone can check — which is how the SHA-1/SHA-256 mismatch presented.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"revoked/cmd/revoked/server"
)

func main() {
	dir, err := os.MkdirTemp("", "revoked-status-fixture")
	if err != nil {
		panic(err)
	}
	defer os.RemoveAll(dir)

	root, err := server.Load("fixture.test", filepath.Join(dir, "root.pem"))
	if err != nil {
		panic(err)
	}

	const fingerprint = "3fa2c1b0d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f"
	issuedAt := time.Unix(1_700_000_000, 0)

	active, err := root.IssueIdentityStatus(
		fingerprint, server.IdentityStatusActive, "", time.Time{}, issuedAt,
	)
	if err != nil {
		panic(err)
	}
	revoked, err := root.IssueIdentityStatus(
		fingerprint, server.IdentityStatusRevoked, "membership_ended",
		issuedAt.Add(-24*time.Hour), issuedAt,
	)
	if err != nil {
		panic(err)
	}

	out, _ := json.MarshalIndent(map[string]any{
		"publicKeyPem": root.PublicKeyPEM(),
		"domain":       "fixture.test",
		"fingerprint":  fingerprint,
		"issuedAtUnix": issuedAt.Unix(),
		"active":       active,
		"revoked":      revoked,
	}, "", "  ")
	fmt.Println(string(out))
}
