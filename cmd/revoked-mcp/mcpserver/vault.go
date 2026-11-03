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
	// Writable is whether this assistant wrote the record and may change it.
	Writable bool `json:"writable"`
}

type VaultList struct {
	Records []VaultRecord `json:"records"`
}

type RecordInput struct {
	ID string `json:"id" jsonschema:"the record id from list_vault"`
}

type WriteInput struct {
	ID    string `json:"id,omitempty" jsonschema:"a record you wrote, from list_vault, to change it; left out, a new record"`
	Key   string `json:"key,omitempty" jsonschema:"for a new record: its key, [a-z0-9_]"`
	Label string `json:"label,omitempty" jsonschema:"what the record is, as the owner will see it"`
	Value string `json:"value" jsonschema:"the text to keep"`
}

type CreateShareInput struct {
	Label   string   `json:"label" jsonschema:"what the share is for, up to 120 characters"`
	Records []string `json:"records" jsonschema:"record ids from list_vault"`
	Days    int      `json:"days,omitempty" jsonschema:"expiry in days, 1-365; left out, the share does not expire"`
	Ref     string   `json:"ref,omitempty" jsonschema:"your own reference, up to 80 characters"`
}

type DeletedResult struct {
	Deleted bool `json:"deleted"`
}

type CreatedShare struct {
	Link
	URL string `json:"url"`
}

type CreateRequestInput struct {
	Label        string `json:"label" jsonschema:"what the request asks for, up to 120 characters"`
	Template     string `json:"template,omitempty" jsonschema:"a template name in the owner's workspace"`
	MaxResponses int    `json:"maxResponses,omitempty" jsonschema:"how many answers it takes; left out, no limit"`
	Days         int    `json:"days,omitempty" jsonschema:"expiry in days, 1-365"`
	Ref          string `json:"ref,omitempty" jsonschema:"your own reference, up to 80 characters"`
}

type CreatedRequest struct {
	Request
	URL string `json:"url"`
}

func expiry(days int) string {
	if days <= 0 {
		return ""
	}
	return time.Now().Add(time.Duration(days) * 24 * time.Hour).UTC().Format("2006-01-02 15:04:05.000Z")
}

func addVaultTools(s *mcp.Server, c *client) {
	readOnly := &mcp.ToolAnnotations{ReadOnlyHint: true}
	destructive := true

	mcp.AddTool(s, &mcp.Tool{
		Name: "list_vault",
		Description: "The records you may read: those in your own section and any the owner added to it, " +
			"or their whole vault if they allowed that. Id, key, label and type, without values. " +
			"Encrypted records are left out.",
		Annotations: readOnly,
	}, func(ctx context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, VaultList, error) {
		var out VaultList
		if err := c.call(ctx, http.MethodGet, "/api/vault", &out); err != nil {
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
			"for what they asked, and to give it to someone, share it rather than repeating it. " +
			"The owner can see every record read in their audit log.",
		Annotations: readOnly,
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in RecordInput) (*mcp.CallToolResult, VaultRecord, error) {
		if strings.TrimSpace(in.ID) == "" {
			return nil, VaultRecord{}, errors.New("id is required")
		}
		var out VaultRecord
		if err := c.call(ctx, http.MethodGet, "/api/vault/"+url.PathEscape(in.ID), &out); err != nil {
			return nil, VaultRecord{}, err
		}
		return nil, out, nil
	})

	mcp.AddTool(s, &mcp.Tool{
		Name: "write_record",
		Description: "Keep a value in your own section of the owner's vault, or change one you wrote. " +
			"The owner sees it in their vault, marked as yours, and can share, change or delete it. " +
			"Needs a section: call connect with section set.",
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in WriteInput) (*mcp.CallToolResult, VaultRecord, error) {
		var out VaultRecord
		if id := strings.TrimSpace(in.ID); id != "" {
			body := map[string]any{"value": in.Value}
			if in.Label != "" {
				body["label"] = in.Label
			}
			err := c.send(ctx, http.MethodPatch, "/api/vault/"+url.PathEscape(id), body, &out)
			return nil, out, err
		}
		if !recordKey.MatchString(in.Key) {
			return nil, VaultRecord{}, errors.New("key must be [a-z0-9_-]{1,64}")
		}
		err := c.send(ctx, http.MethodPost, "/api/vault",
			map[string]any{"key": in.Key, "label": in.Label, "value": in.Value}, &out)
		return nil, out, err
	})

	mcp.AddTool(s, &mcp.Tool{
		Name:        "delete_record",
		Description: "Delete a record you wrote. Records the owner put in your section stay theirs.",
		Annotations: &mcp.ToolAnnotations{DestructiveHint: &destructive},
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in RecordInput) (*mcp.CallToolResult, DeletedResult, error) {
		if strings.TrimSpace(in.ID) == "" {
			return nil, DeletedResult{}, errors.New("id is required")
		}
		if err := c.call(ctx, http.MethodDelete, "/api/vault/"+url.PathEscape(in.ID), nil); err != nil {
			return nil, DeletedResult{}, err
		}
		return nil, DeletedResult{Deleted: true}, nil
	})

	mcp.AddTool(s, &mcp.Tool{
		Name: "create_share",
		Description: "Share records you may read, at once, and get the link to pass on. Needs the owner's " +
			"permission to create shares: call connect with create set. The owner sees the share in their app.",
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in CreateShareInput) (*mcp.CallToolResult, CreatedShare, error) {
		if len(in.Records) == 0 {
			return nil, CreatedShare{}, errors.New("records are required")
		}
		var out CreatedShare
		err := c.send(ctx, http.MethodPost, "/api/connection/links", map[string]any{
			"label": in.Label, "records": in.Records, "expiresAt": expiry(in.Days), "ref": in.Ref,
		}, &out)
		return nil, out, err
	})

	mcp.AddTool(s, &mcp.Tool{
		Name: "create_request",
		Description: "Ask other people for data in the owner's name, at once, and get the link to pass on. " +
			"Needs the owner's permission to create requests: call connect with create set.",
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in CreateRequestInput) (*mcp.CallToolResult, CreatedRequest, error) {
		var out CreatedRequest
		err := c.send(ctx, http.MethodPost, "/api/connection/requests", map[string]any{
			"label": in.Label, "template": in.Template, "maxResponses": in.MaxResponses,
			"expiresAt": expiry(in.Days), "ref": in.Ref,
		}, &out)
		return nil, out, err
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
		return nil, errors.New("this connect needs the client to be http://localhost:<port>")
	}
	var hosts []string
	switch u.Hostname() {
	case "localhost":
		hosts = []string{"127.0.0.1", "::1"}
	case "127.0.0.1":
		hosts = []string{"127.0.0.1"}
	default:
		return nil, errors.New("this connect needs the client to be http://localhost:<port>")
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
