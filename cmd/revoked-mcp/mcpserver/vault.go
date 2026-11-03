package mcpserver

import (
	"context"
	"crypto/subtle"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// VaultRecord is one entry of the owner's vault. Value is only filled by
// read_record; a file record carries its name, type and size instead.
type VaultRecord struct {
	ID       string `json:"id"`
	Key      string `json:"key"`
	Label    string `json:"label,omitempty"`
	Type     string `json:"type"`
	Format   string `json:"format,omitempty"`
	Updated  string `json:"updated,omitempty"`
	Value    string `json:"value,omitempty"`
	Filename string `json:"filename,omitempty"`
	Mime     string `json:"mime,omitempty"`
	Size     int    `json:"size,omitempty"`
}

type VaultList struct {
	Records []VaultRecord `json:"records"`
}

type RecordInput struct {
	ID string `json:"id" jsonschema:"the record id from list_vault"`
}

func addVaultTools(s *mcp.Server, c *client) {
	readOnly := &mcp.ToolAnnotations{ReadOnlyHint: true}

	mcp.AddTool(s, &mcp.Tool{
		Name: "list_vault",
		Description: "The records in the owner's vault: id, key, label and type, without values. " +
			"Only works when the owner let this assistant read their vault. Encrypted records are left out.",
		Annotations: readOnly,
	}, func(ctx context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, VaultList, error) {
		var out VaultList
		if err := c.call(ctx, http.MethodGet, "/api/connection/vault", &out); err != nil {
			return nil, VaultList{}, err
		}
		if out.Records == nil {
			out.Records = []VaultRecord{}
		}
		return nil, out, nil
	})

	mcp.AddTool(s, &mcp.Tool{
		Name: "read_record",
		Description: "The current value of one record from list_vault. The value is the owner's secret: use it " +
			"for what they asked, and to give it to someone, propose a share rather than repeating it. " +
			"The owner can see every record read in their audit log.",
		Annotations: readOnly,
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in RecordInput) (*mcp.CallToolResult, VaultRecord, error) {
		if strings.TrimSpace(in.ID) == "" {
			return nil, VaultRecord{}, errors.New("id is required")
		}
		var out VaultRecord
		if err := c.call(ctx, http.MethodGet, "/api/connection/vault/"+url.PathEscape(in.ID), &out); err != nil {
			return nil, VaultRecord{}, err
		}
		return nil, out, nil
	})
}

// loopback receives the app's answer at the assistant's own address. It
// listens only on this machine's loopback interface, which is the point: a
// connect link someone else sent cannot have its answer delivered to them.
type loopback struct {
	servers []*http.Server
	once    sync.Once
}

func (l *loopback) close() {
	l.once.Do(func() {
		for _, s := range l.servers {
			_ = s.Close()
		}
	})
}

func listenLoopback(c *client, p *pendingConnect, state, redirect string) (*loopback, error) {
	u, err := url.Parse(c.cfg.Client)
	if err != nil || u.Scheme != "http" || u.Port() == "" {
		return nil, errors.New("vault access needs the client to be http://localhost:<port>")
	}
	var hosts []string
	switch u.Hostname() {
	case "localhost":
		hosts = []string{"127.0.0.1", "::1"}
	case "127.0.0.1":
		hosts = []string{"127.0.0.1"}
	default:
		return nil, errors.New("vault access needs the client to be http://localhost:<port>")
	}

	lb := &loopback{}
	mux := http.NewServeMux()
	mux.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		if subtle.ConstantTimeCompare([]byte(q.Get("state")), []byte(state)) != 1 {
			http.Error(w, "This page doesn’t belong to a connect your assistant started.", http.StatusBadRequest)
			return
		}
		var result error
		switch {
		case q.Get("status") != "connected" || q.Get("code") == "":
			result = errors.New("the owner declined the connection")
		default:
			ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
			result = c.exchange(ctx, q.Get("code"), p.verifier, redirect)
			cancel()
		}
		c.mu.Lock()
		if result != nil {
			p.err = result
		} else if c.pending == p {
			c.pending = nil
		}
		c.mu.Unlock()

		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		msg := "Your assistant is connected. You can close this tab."
		if result != nil {
			msg = "Your assistant isn’t connected. You can close this tab and ask it to connect again."
		}
		_, _ = fmt.Fprintf(w, "<!doctype html><meta charset=utf-8><title>Revoked</title>"+
			"<body style=\"font:16px system-ui;margin:3rem auto;max-width:32rem;padding:0 1rem\"><p>%s</p>", msg)
		go lb.close()
	})

	for _, host := range hosts {
		ln, err := net.Listen("tcp", net.JoinHostPort(host, u.Port()))
		if err != nil {
			continue
		}
		srv := &http.Server{Handler: mux, ReadHeaderTimeout: 10 * time.Second}
		lb.servers = append(lb.servers, srv)
		go func() { _ = srv.Serve(ln) }()
	}
	if len(lb.servers) == 0 {
		return nil, fmt.Errorf("port %s on this computer is taken; start the assistant with another -client port", u.Port())
	}
	time.AfterFunc(time.Until(p.expires), lb.close)
	return lb, nil
}
