// Command gen-sdk writes the catalogues the JavaScript SDK mirrors from the
// server: error codes and webhook event types. Run it from the repo root;
// TestSDKGeneratedFilesCurrent fails while the committed output is stale.
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"revoked/util/sdkgen"
)

func main() {
	out := filepath.Join("packages", "revoked-js", "src", "generated")
	for name, content := range sdkgen.Files() {
		path := filepath.Join(out, name)
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Println("wrote", path)
	}
}
