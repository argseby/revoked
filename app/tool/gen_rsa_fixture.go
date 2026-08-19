//go:build ignore

// Emits a signature produced by the server's root key, used as a fixture by
// the Dart crypto tests so the client verifier is checked against real output.
package main

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"revoked/cmd/revoked/server"
)

func main() {
	dir, err := os.MkdirTemp("", "revoked-fixture")
	if err != nil {
		panic(err)
	}
	defer os.RemoveAll(dir)

	root, err := server.Load("fixture.test", filepath.Join(dir, "root.pem"))
	if err != nil {
		panic(err)
	}

	const message = "identity-fingerprint-under-test"
	sig, err := root.Sign([]byte(message))
	if err != nil {
		panic(err)
	}

	out, _ := json.MarshalIndent(map[string]string{
		"publicKeyPem": root.PublicKeyPEM(),
		"message":      message,
		"signatureHex": hex.EncodeToString(sig),
	}, "", "  ")
	fmt.Println(string(out))
}
