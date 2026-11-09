// Command works-with checks the Works with Revoked entries in services/ and
// builds the catalog the app bundles and reads.
//
//	go run ./cmd/works-with check    # validate entries; fail if the catalog is stale
//	go run ./cmd/works-with build    # write the catalog
//	go run ./cmd/works-with online   # fetch every origin and proof file
//
// Run it from the repository root.
package main

import (
	"bytes"
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"time"
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprintln(stderr, "usage: works-with check|build|online [flags]")
		return 2
	}
	fs := flag.NewFlagSet(args[0], flag.ContinueOnError)
	fs.SetOutput(stderr)
	dir := fs.String("services", "services", "directory of <slug>.yaml entries")
	blocklist := fs.String("blocklist", "blocked-domains.txt", "blocked domains, in the app's format")
	out := fs.String("out", "app/assets/works_with/catalog.json", "where the catalog is written")
	only := fs.String("only", "", "online: check only this slug")
	if err := fs.Parse(args[1:]); err != nil {
		return 2
	}

	blockedText, err := os.ReadFile(*blocklist)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	entries, problems := LoadEntries(*dir, ParseBlocklist(string(blockedText)))
	if len(problems) > 0 {
		for _, p := range problems {
			fmt.Fprintln(stderr, p)
		}
		return 1
	}
	built, err := Build(entries).Encode()
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}

	switch args[0] {
	case "check":
		current, err := os.ReadFile(*out)
		if err != nil || !bytes.Equal(current, built) {
			fmt.Fprintf(stderr, "%s is out of date: run go run ./cmd/works-with build\n", *out)
			return 1
		}
		fmt.Fprintf(stdout, "%d entries, catalog up to date\n", len(entries))
		return 0

	case "build":
		if err := os.WriteFile(*out, built, 0o644); err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		fmt.Fprintf(stdout, "wrote %s (%d entries)\n", *out, len(entries))
		return 0

	case "online":
		checker := NewChecker()
		failed := 0
		for _, e := range entries {
			if *only != "" && e.Slug != *only {
				continue
			}
			ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
			f := checker.Check(ctx, e)
			cancel()
			status := "ok"
			if f.Problem != "" {
				status = f.Problem
				failed++
			}
			fmt.Fprintf(stdout, "- %s (%s): reachable=%t, proof %s — %s\n",
				e.Slug, e.Origin, f.Reachable, f.Proof, status)
		}
		if failed > 0 {
			return 1
		}
		return 0
	}
	fmt.Fprintf(stderr, "unknown command %q\n", args[0])
	return 2
}
