// Command revoked-mcp is an MCP server over stdio that lets an AI assistant
// propose, follow and end shares, requests and attestations on the owner's
// Revoked server, and read their vault if they allow it: see docs/api/mcp.md.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"revoked/cmd/revoked-mcp/mcpserver"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func main() {
	statePath, _ := mcpserver.DefaultStatePath()
	server := flag.String("server", os.Getenv("REVOKED_SERVER"), "your Revoked server, e.g. https://api.revoked.link")
	name := flag.String("name", envOr("REVOKED_MCP_NAME", "AI assistant"), "the name shown in the app")
	client := flag.String("client", envOr("REVOKED_MCP_CLIENT", mcpserver.DefaultClient), "the origin the assistant connects as")
	state := flag.String("state", envOr("REVOKED_MCP_STATE", statePath), "where the connection token is kept")
	noOpen := flag.Bool("no-open", false, "print links instead of opening them in the app")
	flag.Parse()

	cfg := mcpserver.Config{Server: *server, Client: *client, Name: *name, StatePath: *state}
	if !*noOpen {
		cfg.Open = mcpserver.OpenWithSystem
	}
	s, err := mcpserver.New(cfg)
	if err != nil {
		fmt.Fprintln(os.Stderr, "revoked-mcp:", err)
		os.Exit(2)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := s.Run(ctx, &mcp.StdioTransport{}); err != nil && ctx.Err() == nil {
		fmt.Fprintln(os.Stderr, "revoked-mcp:", err)
		os.Exit(1)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
