package mcpserver

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"revoked/util"
	"strings"
	"sync"
	"time"
)

// Link is what the assistant learns about a share it proposed. It has no URL
// on purpose: a handed-over link opens the data, and anything a tool returns
// ends up in the model's context.
type Link struct {
	ID         string `json:"id"`
	Ref        string `json:"ref,omitempty"`
	Label      string `json:"label"`
	Status     string `json:"status"`
	ViewCount  int    `json:"viewCount"`
	MaxViews   int    `json:"maxViews,omitempty"`
	ExpiresAt  string `json:"expiresAt,omitempty"`
	Created    string `json:"created"`
	HandedOver bool   `json:"handedOver"`
}

// Request is where a proposed request stands. The server sends neither its
// address nor its answers.
type Request struct {
	ID            string `json:"id"`
	Ref           string `json:"ref,omitempty"`
	Label         string `json:"label"`
	Status        string `json:"status"`
	ResponseCount int    `json:"responseCount"`
	MaxResponses  int    `json:"maxResponses,omitempty"`
	ExpiresAt     string `json:"expiresAt,omitempty"`
	Created       string `json:"created"`
}

// Attestation is a proposed attestation without its claims: the values are
// the owner's statement.
type Attestation struct {
	ID                 string `json:"id"`
	Ref                string `json:"ref,omitempty"`
	Type               string `json:"type"`
	Label              string `json:"label,omitempty"`
	Status             string `json:"status"`
	SubjectName        string `json:"subjectName,omitempty"`
	SubjectFingerprint string `json:"subjectFingerprint,omitempty"`
	SubjectDomain      string `json:"subjectDomain,omitempty"`
	ExpiresAt          string `json:"expiresAt,omitempty"`
	IssuedAt           string `json:"issuedAt,omitempty"`
	Created            string `json:"created"`
}

// Check is a proposed attestation check and, once answered, its verdict with
// the claims the other person chose to show.
type Check struct {
	ID         string   `json:"id"`
	Ref        string   `json:"ref,omitempty"`
	Type       string   `json:"type,omitempty"`
	Status     string   `json:"status"`
	ExpiresAt  string   `json:"expiresAt,omitempty"`
	AnsweredAt string   `json:"answeredAt,omitempty"`
	Created    string   `json:"created"`
	Verdict    *Verdict `json:"verdict,omitempty"`
}

type Verdict struct {
	State    string         `json:"state"`
	Issuer   string         `json:"issuer,omitempty"`
	Type     string         `json:"type,omitempty"`
	Claims   map[string]any `json:"claims,omitempty"`
	Withheld int            `json:"withheld"`
	Status   string         `json:"status,omitempty"`
	Holder   *struct {
		Fingerprint string `json:"fingerprint"`
		Domain      string `json:"domain"`
		State       string `json:"state"`
		Status      string `json:"status,omitempty"`
	} `json:"holder,omitempty"`
}

type Connection struct {
	ID           string        `json:"id"`
	ClientName   string        `json:"clientName"`
	ExpiresAt    string        `json:"expiresAt"`
	AllowRevoke  bool          `json:"allowRevoke"`
	Links        []Link        `json:"links"`
	Requests     []Request     `json:"requests"`
	Attestations []Attestation `json:"attestations"`
	Checks       []Check       `json:"checks"`
}

type savedConnection struct {
	Server string `json:"server"`
	Token  string `json:"token"`
}

type pendingConnect struct {
	verifier string
	expires  time.Time
}

// errNotConnected is returned when the server no longer accepts the token; the
// token is forgotten, since only the owner can connect the assistant again.
var errNotConnected = errors.New("not connected: call connect, then confirm in the Revoked app")

type apiError struct {
	Status int
	Code   string
}

func (e *apiError) Error() string {
	switch e.Code {
	case util.Errors.ConnectionPaused.ErrorCode:
		return "the owner paused this assistant in the Revoked app"
	case util.Errors.ConnectionRevokeNotAllowed.ErrorCode:
		return "the owner has not allowed this assistant to end what it proposed"
	}
	if e.Code != "" {
		return fmt.Sprintf("server refused (%d %s)", e.Status, e.Code)
	}
	return fmt.Sprintf("server refused (%d)", e.Status)
}

// client speaks the connected-tool protocol (docs/api/tools.md) against one
// server. It never holds a user session, so nothing it does can read the vault.
type client struct {
	cfg  Config
	http *http.Client

	mu      sync.Mutex
	pending *pendingConnect
}

func (c *client) redirect() string { return c.cfg.Client + "/" }

func (c *client) loadToken() string {
	raw, err := os.ReadFile(c.cfg.StatePath)
	if err != nil {
		return ""
	}
	var s savedConnection
	if json.Unmarshal(raw, &s) != nil || s.Server != c.cfg.Server {
		return ""
	}
	return s.Token
}

func (c *client) saveToken(token string) error {
	if err := os.MkdirAll(filepath.Dir(c.cfg.StatePath), 0o700); err != nil {
		return err
	}
	raw, _ := json.Marshal(savedConnection{Server: c.cfg.Server, Token: token})
	return os.WriteFile(c.cfg.StatePath, raw, 0o600)
}

func (c *client) forgetToken() { _ = os.Remove(c.cfg.StatePath) }

// startConnect prepares a connect link the owner answers in the app. The
// answer is collected by polling, so the app opens no browser.
func (c *client) startConnect() (link, checkCode string, err error) {
	verifier, err := randomValue(32)
	if err != nil {
		return "", "", err
	}
	state, err := randomValue(16)
	if err != nil {
		return "", "", err
	}
	challenge := util.PKCEChallenge(verifier)

	c.mu.Lock()
	c.pending = &pendingConnect{verifier: verifier, expires: time.Now().Add(10 * time.Minute)}
	c.mu.Unlock()

	q := []string{
		"client=" + escape(c.cfg.Client),
		"name=" + escape(c.cfg.Name),
		"redirect=" + escape(c.redirect()),
		"state=" + state,
		"challenge=" + challenge,
		"poll=" + escape(c.cfg.Server),
		"revoke_reason=" + escape("So you can ask your assistant to end what it set up for you"),
	}
	return "revoked://connect?" + strings.Join(q, "&"), CheckCode(challenge), nil
}

// pollConnect asks once whether the owner answered. It reports false while
// they have not.
func (c *client) pollConnect(ctx context.Context) (bool, error) {
	c.mu.Lock()
	p := c.pending
	c.mu.Unlock()
	if p == nil || time.Now().After(p.expires) {
		return false, errNotConnected
	}
	body, _ := json.Marshal(map[string]string{"verifier": p.verifier, "redirectUri": c.redirect()})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.cfg.Server+"/api/connect/token", bytes.NewReader(body))
	if err != nil {
		return false, err
	}
	req.Header.Set("Content-Type", "application/json")
	// The server hands a polled answer only to the tool's own origin.
	req.Header.Set("Origin", c.cfg.Client)
	resp, err := c.http.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusAccepted:
		return false, nil
	case http.StatusOK:
		var out struct {
			Token string `json:"token"`
		}
		if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&out); err != nil || out.Token == "" {
			return false, errors.New("unexpected answer from the server")
		}
		c.mu.Lock()
		c.pending = nil
		c.mu.Unlock()
		return true, c.saveToken(out.Token)
	default:
		c.mu.Lock()
		c.pending = nil
		c.mu.Unlock()
		return false, readAPIError(resp)
	}
}

func (c *client) connection(ctx context.Context) (*Connection, error) {
	var out Connection
	if err := c.call(ctx, http.MethodGet, "/api/connection", &out); err != nil {
		return nil, err
	}
	if out.Links == nil {
		out.Links = []Link{}
	}
	if out.Requests == nil {
		out.Requests = []Request{}
	}
	if out.Attestations == nil {
		out.Attestations = []Attestation{}
	}
	if out.Checks == nil {
		out.Checks = []Check{}
	}
	return &out, nil
}

// act posts to one of the connection's own rows, e.g. links/{id}/revoke.
func (c *client) act(ctx context.Context, kind, id, verb string, out any) error {
	return c.call(ctx, http.MethodPost, "/api/connection/"+kind+"/"+url.PathEscape(id)+"/"+verb, out)
}

func (c *client) disconnect(ctx context.Context) error {
	err := c.call(ctx, http.MethodDelete, "/api/connection", nil)
	if err == nil || errors.Is(err, errNotConnected) {
		c.forgetToken()
		return nil
	}
	return err
}

func (c *client) call(ctx context.Context, method, path string, out any) error {
	token := c.loadToken()
	if token == "" {
		return errNotConnected
	}
	req, err := http.NewRequestWithContext(ctx, method, c.cfg.Server+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set(util.ConnectionHeader, token)
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusUnauthorized {
		c.forgetToken()
		return errNotConnected
	}
	if resp.StatusCode >= 300 {
		return readAPIError(resp)
	}
	if out == nil {
		return nil
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 8<<20)).Decode(out)
}

func readAPIError(resp *http.Response) error {
	var env struct {
		Code string `json:"code"`
	}
	_ = json.NewDecoder(io.LimitReader(resp.Body, 1<<16)).Decode(&env)
	return &apiError{Status: resp.StatusCode, Code: env.Code}
}

// CheckCode is what the owner compares with the app before approving a polled
// connection: the first three bytes of SHA-256(challenge), as "ABC-123".
func CheckCode(challenge string) string {
	d := sha256.Sum256([]byte(challenge))
	h := strings.ToUpper(hex.EncodeToString(d[:3]))
	return h[:3] + "-" + h[3:]
}

func randomValue(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// escape percent-encodes a link value with a space as %20, as the app expects.
func escape(s string) string {
	return strings.ReplaceAll(url.QueryEscape(s), "+", "%20")
}
