// Package mcpserver lets an AI assistant organise shares, requests and
// attestations through the connected-tool protocol: it proposes what the owner
// confirms in the app, follows what became of it and ends it. It reads values
// only when the owner let it read their vault.
package mcpserver

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"revoked/util"
	"runtime"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// DefaultClient is the origin the assistant connects as. A port of its own
// keeps it from sharing a connection with a tool developed on localhost.
const DefaultClient = "http://localhost:47303"

type Config struct {
	// Server is the owner's server origin, as the owner entered it.
	Server string
	// Client is the origin the assistant connects as.
	Client string
	// Name is shown to the owner in the app, as a claim.
	Name string
	// StatePath holds the connection token between runs.
	StatePath string
	// Open hands a revoked:// link to the app. Nil leaves it to the owner.
	Open func(link string) error
	HTTP *http.Client
}

// New builds the MCP server, or refuses a configuration the server would.
func New(cfg Config) (*mcp.Server, error) {
	server, ok := util.NormalizeOrigin(cfg.Server)
	if !ok {
		return nil, fmt.Errorf("server %q is not an https origin (or http on localhost)", cfg.Server)
	}
	cfg.Server = server
	if cfg.Client == "" {
		cfg.Client = DefaultClient
	}
	if cfg.Client, ok = util.NormalizeOrigin(cfg.Client); !ok {
		return nil, errors.New("client must be an https origin, or http on localhost")
	}
	cfg.Name = strings.Join(strings.Fields(cfg.Name), " ")
	if cfg.Name == "" {
		cfg.Name = "AI assistant"
	}
	if utf8.RuneCountInString(cfg.Name) > 40 {
		return nil, errors.New("name is longer than 40 characters")
	}
	if cfg.StatePath == "" {
		return nil, errors.New("no state path")
	}
	if cfg.HTTP == nil {
		cfg.HTTP = &http.Client{Timeout: 20 * time.Second}
	}
	c := &client{cfg: cfg, http: cfg.HTTP}

	s := mcp.NewServer(&mcp.Implementation{Name: "revoked", Version: util.Version()}, &mcp.ServerOptions{
		Instructions: "Organise the owner's Revoked shares, requests and attestations. You propose " +
			"them by name — record keys, a template, claim names — and the owner fills in the values " +
			"and confirms in their app. Connect once to follow what became of your proposals and to " +
			"end them. To keep notes or files for the owner, connect with section set: you get a section " +
			"of your own in their vault, which write_record and delete_record change. Only if the owner " +
			"wants you to answer questions about their whole vault, connect with vault set and they " +
			"decide in the app. list_vault and read_record show what you may read. Read only what the " +
			"task needs, and to give a value to someone else, share it instead of repeating it.",
	})
	addTools(s, c)
	addProposalTools(s, c)
	addVaultTools(s, c)
	return s, nil
}

// OpenWithSystem hands a link to the desktop, which passes revoked:// to the app.
func OpenWithSystem(link string) error {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", link)
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", link)
	default:
		cmd = exec.Command("xdg-open", link)
	}
	cmd.Stdout, cmd.Stderr = nil, nil
	if err := cmd.Start(); err != nil {
		return err
	}
	go func() { _ = cmd.Wait() }()
	return nil
}

type empty struct{}

type ConnectResult struct {
	Connected bool   `json:"connected"`
	Link      string `json:"link,omitempty"`
	CheckCode string `json:"checkCode,omitempty"`
	Opened    bool   `json:"opened"`
	Next      string `json:"next"`
}

type ConnectInput struct {
	Vault   bool `json:"vault,omitempty" jsonschema:"also ask to read the owner's whole vault; only when they asked you to work with what is in it. Needs the Revoked app on this computer"`
	Section bool `json:"section,omitempty" jsonschema:"also ask for a section of your own in the owner's vault, where you can keep notes and files for them"`
	Create  bool `json:"create,omitempty" jsonschema:"also ask to create shares and requests yourself, instead of proposing them"`
}

type StatusResult struct {
	Connected    bool     `json:"connected"`
	Pending      bool     `json:"pending"`
	ClientName   string   `json:"clientName,omitempty"`
	ExpiresAt    string   `json:"expiresAt,omitempty"`
	AllowRevoke  bool     `json:"allowRevoke"`
	ReadsVault   bool     `json:"readsVault"`
	HasSection   bool     `json:"hasSection"`
	Permissions  []string `json:"permissions,omitempty"`
	Shares       int      `json:"shares"`
	Requests     int      `json:"requests"`
	Attestations int      `json:"attestations"`
	Checks       int      `json:"checks"`
}

type ProposeInput struct {
	Label    string   `json:"label" jsonschema:"what the share is for, up to 120 characters"`
	Keys     []string `json:"keys" jsonschema:"record keys to include, 1-50, each [a-z0-9_-]{1,64}"`
	Template string   `json:"template,omitempty" jsonschema:"template name describing the keys, so the app can ask for one the vault lacks"`
	Days     int      `json:"days,omitempty" jsonschema:"expiry in days, 1-365; left out, the share does not expire"`
	Ref      string   `json:"ref,omitempty" jsonschema:"your own reference, up to 80 characters, returned by list_shares"`
}

type ProposeResult struct {
	Link   string `json:"link"`
	Opened bool   `json:"opened"`
	Next   string `json:"next"`
}

type ListResult struct {
	Shares []Link `json:"shares"`
}

type RevokeInput struct {
	ID string `json:"id" jsonschema:"the share id from list_shares"`
}

type DisconnectResult struct {
	Disconnected bool `json:"disconnected"`
}

var recordKey = regexp.MustCompile(`^[a-z0-9_-]{1,64}$`)

func addTools(s *mcp.Server, c *client) {
	readOnly := &mcp.ToolAnnotations{ReadOnlyHint: true}
	destructive := true

	mcp.AddTool(s, &mcp.Tool{
		Name: "connect",
		Description: "Ask the owner to connect this assistant, so it can follow and end what it proposes. " +
			"With section set it also asks for a section of its own in their vault; with create, to create " +
			"shares and requests itself; with vault, to read their whole vault. Opens a confirmation in the Revoked app.",
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in ConnectInput) (*mcp.CallToolResult, ConnectResult, error) {
		if conn, err := c.connection(ctx); err == nil {
			if (!in.Vault || conn.VaultReadable) && (!in.Section || conn.hasSection()) &&
				(!in.Create || slices.Contains(conn.Permissions, util.PermSharesManage)) {
				return nil, ConnectResult{Connected: true, Next: "Already connected."}, nil
			}
		} else if !errors.Is(err, errNotConnected) {
			return nil, ConnectResult{}, err
		}
		link, code, err := c.startConnect(connectAsk{Vault: in.Vault, Section: in.Section, Create: in.Create})
		if err != nil {
			return nil, ConnectResult{}, err
		}
		opened := c.cfg.Open != nil && c.cfg.Open(link) == nil
		next := "Tell the owner to approve only if the app shows check code " + code +
			". Then call connection_status."
		if in.Vault || in.Create {
			next = "The owner decides in the Revoked app what you may do. Afterwards " +
				"the app opens a browser tab that hands their answer back to you. Then call connection_status."
		}
		return nil, ConnectResult{Link: link, CheckCode: code, Opened: opened, Next: next}, nil
	})

	mcp.AddTool(s, &mcp.Tool{
		Name:        "connection_status",
		Description: "Whether the owner has connected this assistant, and what they allowed.",
		Annotations: readOnly,
	}, func(ctx context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, StatusResult, error) {
		if c.loadToken() == "" {
			done, err := c.pollConnect(ctx)
			if errors.Is(err, errNotConnected) {
				return nil, StatusResult{}, nil
			}
			if err != nil {
				return nil, StatusResult{}, err
			}
			if !done {
				return nil, StatusResult{Pending: true}, nil
			}
		}
		conn, err := c.connection(ctx)
		if errors.Is(err, errNotConnected) {
			return nil, StatusResult{}, nil
		}
		if err != nil {
			return nil, StatusResult{}, err
		}
		return nil, StatusResult{
			Connected: true, Pending: c.pendingConnectActive(), ClientName: conn.ClientName, ExpiresAt: conn.ExpiresAt,
			AllowRevoke: conn.AllowRevoke, ReadsVault: conn.VaultReadable, HasSection: conn.hasSection(),
			Permissions: conn.Permissions, Shares: len(conn.Links), Requests: len(conn.Requests),
			Attestations: len(conn.Attestations), Checks: len(conn.Checks),
		}, nil
	})

	mcp.AddTool(s, &mcp.Tool{
		Name: "propose_share",
		Description: "Propose a share of the owner's records by key. The owner reviews it, picks the values " +
			"and creates it in the Revoked app; the link goes to them, not to you.",
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in ProposeInput) (*mcp.CallToolResult, ProposeResult, error) {
		link, err := proposalLink(c.cfg, in)
		if err != nil {
			return nil, ProposeResult{}, err
		}
		opened := c.cfg.Open != nil && c.cfg.Open(link) == nil
		next := "The owner confirms the share in the Revoked app."
		if c.loadToken() != "" {
			next += " Call list_shares to see it once they have."
		} else {
			next += " Connect first to be able to follow it."
		}
		return nil, ProposeResult{Link: link, Opened: opened, Next: next}, nil
	})

	mcp.AddTool(s, &mcp.Tool{
		Name:        "list_shares",
		Description: "The shares the owner created from this assistant's proposals: label, your ref, status, views and expiry. Never their content or address.",
		Annotations: readOnly,
	}, func(ctx context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, ListResult, error) {
		conn, err := c.connection(ctx)
		if err != nil {
			return nil, ListResult{}, err
		}
		return nil, ListResult{Shares: conn.Links}, nil
	})

	mcp.AddTool(s, &mcp.Tool{
		Name:        "revoke_share",
		Description: "End one of the shares from list_shares at once. Needs the owner's permission, given when connecting.",
		Annotations: &mcp.ToolAnnotations{DestructiveHint: &destructive},
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in RevokeInput) (*mcp.CallToolResult, Link, error) {
		if strings.TrimSpace(in.ID) == "" {
			return nil, Link{}, errors.New("id is required")
		}
		var l Link
		if err := c.act(ctx, "links", in.ID, "revoke", &l); err != nil {
			return nil, Link{}, err
		}
		return nil, l, nil
	})

	mcp.AddTool(s, &mcp.Tool{
		Name:        "disconnect",
		Description: "Disconnect this assistant. Everything it proposed stays the owner's and keeps working.",
		Annotations: &mcp.ToolAnnotations{DestructiveHint: &destructive},
	}, func(ctx context.Context, _ *mcp.CallToolRequest, _ empty) (*mcp.CallToolResult, DisconnectResult, error) {
		if err := c.disconnect(ctx); err != nil {
			return nil, DisconnectResult{}, err
		}
		return nil, DisconnectResult{Disconnected: true}, nil
	})
}

// proposalLink builds a revoked://p link, refused whole when any part is one
// the app would refuse.
func proposalLink(cfg Config, in ProposeInput) (string, error) {
	label := strings.Join(strings.Fields(in.Label), " ")
	if label == "" || utf8.RuneCountInString(label) > 120 {
		return "", errors.New("label must be 1-120 characters")
	}
	if len(in.Keys) == 0 || len(in.Keys) > 50 {
		return "", errors.New("keys must name 1-50 records")
	}
	for _, k := range in.Keys {
		if !recordKey.MatchString(k) {
			return "", fmt.Errorf("key %q is not [a-z0-9_-]{1,64}", k)
		}
	}
	if utf8.RuneCountInString(in.Template) > 80 {
		return "", errors.New("template must be at most 80 characters")
	}
	if in.Days < 0 || in.Days > 365 {
		return "", errors.New("days must be 1-365")
	}
	if utf8.RuneCountInString(in.Ref) > 80 {
		return "", errors.New("ref must be at most 80 characters")
	}

	q := []string{
		"label=" + escape(label),
		"keys=" + strings.Join(in.Keys, ","),
		"from=" + escape(cfg.Name),
		"client=" + escape(cfg.Client),
	}
	if in.Template != "" {
		q = append(q, "template="+escape(in.Template))
	}
	if in.Days > 0 {
		q = append(q, "days="+strconv.Itoa(in.Days))
	}
	if in.Ref != "" {
		q = append(q, "ref="+escape(in.Ref))
	}
	return "revoked://p?" + strings.Join(q, "&"), nil
}

// DefaultStatePath is where the connection token is kept between runs.
func DefaultStatePath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "revoked", "mcp-connection.json"), nil
}
