package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)

// Caller is the generator's HTTP client. One instance is shared by every
// worker: connection reuse is what keeps the measurement about the server.
type Caller struct {
	base string
	host string
	hc   *http.Client
}

func NewCaller(base, host string, conns int, timeout time.Duration) *Caller {
	if conns < 2 {
		conns = 2
	}
	return &Caller{
		base: strings.TrimRight(base, "/"),
		host: host,
		hc: &http.Client{
			Timeout: timeout,
			Transport: &http.Transport{
				// Below the worker count these would churn connections every
				// request, and the run would measure the generator's handshakes.
				MaxIdleConns:        conns * 2,
				MaxIdleConnsPerHost: conns,
				DisableCompression:  true,
				ForceAttemptHTTP2:   false,
				DialContext: (&net.Dialer{
					Timeout:   timeout,
					KeepAlive: 30 * time.Second,
				}).DialContext,
			},
		},
	}
}

// Do sends one request and drains the body, which is what returns the
// connection to the pool. It reports the status and the bytes read.
func (c *Caller) Do(ctx context.Context, method, path, token string, body []byte) (int, int64, error) {
	var reader io.Reader
	if body != nil {
		reader = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.base+path, reader)
	if err != nil {
		return 0, 0, err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", token)
	}
	if c.host != "" {
		req.Host = c.host
	}

	resp, err := c.hc.Do(req)
	if err != nil {
		return 0, 0, err
	}
	defer resp.Body.Close()
	n, _ := io.Copy(io.Discard, resp.Body)
	return resp.StatusCode, n, nil
}

func (c *Caller) GET(ctx context.Context, path, token string) (int, int64, error) {
	return c.Do(ctx, http.MethodGet, path, token, nil)
}

func (c *Caller) POST(ctx context.Context, path, token string, body any) (int, int64, error) {
	payload, err := json.Marshal(body)
	if err != nil {
		return 0, 0, err
	}
	return c.Do(ctx, http.MethodPost, path, token, payload)
}

// JSON sends a request and decodes a successful body into out.
func (c *Caller) JSON(ctx context.Context, method, path, token string, body, out any) error {
	var payload []byte
	if body != nil {
		var err error
		if payload, err = json.Marshal(body); err != nil {
			return err
		}
	}
	var reader io.Reader
	if payload != nil {
		reader = bytes.NewReader(payload)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.base+path, reader)
	if err != nil {
		return err
	}
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", token)
	}
	if c.host != "" {
		req.Host = c.host
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("%s %s: %d %s", method, path, resp.StatusCode, truncate(string(raw), 300))
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(raw, out)
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

// errKind collapses a transport failure into one of a handful of labels, so a
// stage's report says how it failed rather than listing a line per socket.
func errKind(err error) string {
	if err == nil {
		return ""
	}
	switch {
	case errors.Is(err, context.DeadlineExceeded):
		return "timeout"
	case errors.Is(err, context.Canceled):
		return "canceled"
	}
	msg := err.Error()
	for _, probe := range []struct{ needle, label string }{
		{"Client.Timeout", "timeout"},
		{"connection refused", "connection refused"},
		{"connection reset", "connection reset"},
		{"broken pipe", "broken pipe"},
		{"EOF", "EOF (server closed)"},
		{"too many open files", "generator out of file descriptors"},
		{"cannot assign requested address", "generator out of ephemeral ports"},
		{"no such host", "DNS failure"},
	} {
		if strings.Contains(msg, probe.needle) {
			return probe.label
		}
	}
	return msg
}
