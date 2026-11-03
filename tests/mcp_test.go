package tests

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"path/filepath"
	"strings"
	"testing"

	"revoked/cmd/revoked-mcp/mcpserver"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

type mcpHarness struct {
	t      *testing.T
	ctx    context.Context
	cs     *mcp.ClientSession
	opened []string
}

func newMCPHarness(t *testing.T, server string) *mcpHarness {
	t.Helper()
	h := &mcpHarness{t: t, ctx: context.Background()}
	s, err := mcpserver.New(mcpserver.Config{
		Server:    server,
		Name:      "Test assistant",
		StatePath: filepath.Join(t.TempDir(), "connection.json"),
		Open:      func(link string) error { h.opened = append(h.opened, link); return nil },
	})
	if err != nil {
		t.Fatalf("new mcp server: %v", err)
	}
	st, ct := mcp.NewInMemoryTransports()
	if _, err := s.Connect(h.ctx, st, nil); err != nil {
		t.Fatalf("connect server: %v", err)
	}
	h.cs, err = mcp.NewClient(&mcp.Implementation{Name: "test"}, nil).Connect(h.ctx, ct, nil)
	if err != nil {
		t.Fatalf("connect client: %v", err)
	}
	t.Cleanup(func() { _ = h.cs.Close() })
	return h
}

// call runs a tool and returns its raw structured output, failing the test
// when the tool refused and wantError is false.
func (h *mcpHarness) call(name string, args any, wantError bool) string {
	h.t.Helper()
	if args == nil {
		args = map[string]any{}
	}
	res, err := h.cs.CallTool(h.ctx, &mcp.CallToolParams{Name: name, Arguments: args})
	if err != nil {
		h.t.Fatalf("%s: %v", name, err)
	}
	if res.IsError != wantError {
		h.t.Fatalf("%s: isError=%v, content %+v", name, res.IsError, res.Content)
	}
	raw, _ := json.Marshal(res.StructuredContent)
	return string(raw)
}

func (h *mcpHarness) decode(name string, args any, out any) {
	h.t.Helper()
	if err := json.Unmarshal([]byte(h.call(name, args, false)), out); err != nil {
		h.t.Fatalf("%s: decode: %v", name, err)
	}
}

func TestMCPAssistantManagesSharesWithoutSeeingThem(t *testing.T) {
	f := newWatermarkFixture(t)
	baseURL, _ := testutils.SetupTestApp(t)
	h := newMCPHarness(t, baseURL)

	var status mcpserver.StatusResult
	h.decode("connection_status", nil, &status)
	if status.Connected || status.Pending {
		t.Fatalf("connected before connecting: %+v", status)
	}
	h.call("list_shares", nil, true)

	var started mcpserver.ConnectResult
	h.decode("connect", nil, &started)
	if !started.Opened || len(h.opened) != 1 || h.opened[0] != started.Link {
		t.Fatalf("connect link not handed to the app: %+v", started)
	}
	link, err := url.Parse(started.Link)
	if err != nil || link.Scheme != "revoked" || link.Host != "connect" {
		t.Fatalf("not a connect link: %s", started.Link)
	}
	q := link.Query()
	challenge := q.Get("challenge")
	if q.Get("client") != mcpserver.DefaultClient || q.Get("poll") != baseURL ||
		q.Get("links_reason") != "" || started.CheckCode != mcpserver.CheckCode(challenge) {
		t.Fatalf("unexpected connect link %s (check code %s)", started.Link, started.CheckCode)
	}

	h.decode("connection_status", nil, &status)
	if !status.Pending {
		t.Fatalf("not waiting for the owner: %+v", status)
	}

	connID := authorizeTool(f.api, f.token, map[string]any{
		"clientId": q.Get("client"), "clientName": q.Get("name"), "redirectUri": q.Get("redirect"),
		"challenge": challenge, "poll": true, "allowRevoke": true,
	}).Status(http.StatusOK).JSON().Object().Value("connectionId").String().Raw()

	h.decode("connection_status", nil, &status)
	if !status.Connected || !status.AllowRevoke || status.ClientName != "Test assistant" {
		t.Fatalf("not connected after the owner approved: %+v", status)
	}

	t.Run("a proposal names keys and is refused whole when malformed", func(t *testing.T) {
		var p mcpserver.ProposeResult
		h.decode("propose_share", map[string]any{
			"label": "Wi-Fi for guests", "keys": []string{"network_name", "wifi_password"},
			"template": "Wi-Fi access", "days": 7, "ref": "guests",
		}, &p)
		got, _ := url.Parse(p.Link)
		pq := got.Query()
		if got.Host != "p" || pq.Get("keys") != "network_name,wifi_password" ||
			pq.Get("client") != mcpserver.DefaultClient || pq.Get("ref") != "guests" || pq.Get("days") != "7" {
			t.Fatalf("unexpected proposal %s", p.Link)
		}
		if !strings.Contains(p.Link, "label=Wi-Fi%20for%20guests") {
			t.Fatalf("a space must travel as %%20: %s", p.Link)
		}
		h.call("propose_share", map[string]any{"label": "x", "keys": []string{"Not A Key"}}, true)
		h.call("propose_share", map[string]any{"label": "x", "keys": []string{"a"}, "days": 400}, true)
	})

	t.Run("it follows and ends its shares, never learning their address", func(t *testing.T) {
		setPermissions(f.api, connID, f.token, map[string]any{"allowHandOver": true}).Status(http.StatusOK)
		slug, id := f.share(t, map[string]any{
			util.Fields.Link.Connection: connID, util.Fields.Link.Ref: "guests",
			util.Fields.Link.HandedOver: true,
		})
		// The server would hand this link's URL to a tool; the assistant drops it.
		toolLinks := toolGetAll(t, f, connID)
		if !strings.Contains(toolLinks, "/s/"+slug) {
			t.Fatalf("fixture: server did not hand the link over: %s", toolLinks)
		}

		raw := h.call("list_shares", nil, false)
		if strings.Contains(raw, slug) || strings.Contains(raw, "\"url\"") {
			t.Fatalf("list_shares exposed the share's address: %s", raw)
		}
		var list mcpserver.ListResult
		_ = json.Unmarshal([]byte(raw), &list)
		if len(list.Shares) != 1 || list.Shares[0].ID != id || list.Shares[0].Ref != "guests" {
			t.Fatalf("unexpected shares: %s", raw)
		}

		var revoked mcpserver.Link
		h.decode("revoke_share", map[string]any{"id": id}, &revoked)
		if revoked.Status != util.StatusRevoked {
			t.Fatalf("not revoked: %+v", revoked)
		}
		h.call("revoke_share", map[string]any{"id": "doesnotexist123"}, true)
	})

	t.Run("without the owner's permission it cannot end a share", func(t *testing.T) {
		setPermissions(f.api, connID, f.token, map[string]any{"allowRevoke": false}).Status(http.StatusOK)
		_, id := f.share(t, map[string]any{util.Fields.Link.Connection: connID})
		h.call("revoke_share", map[string]any{"id": id}, true)
	})

	t.Run("disconnecting forgets the token", func(t *testing.T) {
		h.call("disconnect", nil, false)
		h.decode("connection_status", nil, &status)
		if status.Connected {
			t.Fatalf("still connected: %+v", status)
		}
		h.call("list_shares", nil, true)
	})
}

// toolGetAll reads the connection as the server serves it to any tool, through
// a second token for the same connection.
func toolGetAll(t *testing.T, f watermarkFixture, connID string) string {
	t.Helper()
	verifier, challenge := pkcePair()
	redirect := mcpserver.DefaultClient + "/"
	code := authorizeTool(f.api, f.token, map[string]any{
		"clientId": mcpserver.DefaultClient, "redirectUri": redirect, "challenge": challenge, "reuse": true,
	}).Status(http.StatusOK).JSON().Object().Value("code").String().Raw()
	token := f.api.E.POST("/api/connect/token").WithJSON(map[string]any{
		"code": code, "verifier": verifier, "redirectUri": redirect,
	}).Expect().Status(http.StatusOK).JSON().Object().Value("token").String().Raw()
	return toolGet(f.api, token).Status(http.StatusOK).Body().Raw()
}

// connectMCP runs the assistant's connect flow, with the owner approving it.
func connectMCP(t *testing.T, h *mcpHarness, f checkFixture) string {
	t.Helper()
	var started mcpserver.ConnectResult
	h.decode("connect", nil, &started)
	link, _ := url.Parse(started.Link)
	q := link.Query()
	connID := authorizeTool(f.api, f.issuerToken, map[string]any{
		"clientId": q.Get("client"), "clientName": q.Get("name"), "redirectUri": q.Get("redirect"),
		"challenge": q.Get("challenge"), "poll": true, "allowRevoke": true,
	}).Status(http.StatusOK).JSON().Object().Value("connectionId").String().Raw()
	var status mcpserver.StatusResult
	h.decode("connection_status", nil, &status)
	if !status.Connected {
		t.Fatalf("not connected: %+v", status)
	}
	return connID
}

func TestMCPAssistantFollowsRequestsAttestationsAndChecks(t *testing.T) {
	f := newCheckFixture(t)
	h := newMCPHarness(t, f.baseURL)
	connID := connectMCP(t, h, f)

	t.Run("requests: proposed by template, followed without answers, closed", func(t *testing.T) {
		var p mcpserver.ProposeResult
		h.decode("propose_request", map[string]any{
			"template": "Event registration", "label": "Summer party", "days": 14, "ref": "summer",
		}, &p)
		got, _ := url.Parse(p.Link)
		if got.Host != "pr" || got.Query().Get("template") != "Event registration" ||
			got.Query().Get("client") != mcpserver.DefaultClient || got.Query().Get("ref") != "summer" {
			t.Fatalf("unexpected request proposal %s", p.Link)
		}
		h.call("propose_request", map[string]any{"template": ""}, true)

		slug, id := setupRequest(t, f.baseURL, f.issuerToken, f.issuerID, f.issuerWs, f.askerIdentity, map[string]any{
			util.Fields.Request.Connection: connID, util.Fields.Request.Ref: "summer",
		})
		raw := h.call("list_requests", nil, false)
		if strings.Contains(raw, slug) {
			t.Fatalf("list_requests exposed the request's address: %s", raw)
		}
		var list mcpserver.RequestList
		_ = json.Unmarshal([]byte(raw), &list)
		if len(list.Requests) != 1 || list.Requests[0].ID != id || list.Requests[0].Ref != "summer" {
			t.Fatalf("unexpected requests: %s", raw)
		}
		var closed mcpserver.Request
		h.decode("close_request", map[string]any{"id": id}, &closed)
		if closed.Status != util.StatusRevoked {
			t.Fatalf("not closed: %+v", closed)
		}
	})

	t.Run("attestations: proposed by claim names, followed without values, revoked", func(t *testing.T) {
		var p mcpserver.ProposeResult
		h.decode("propose_attestation", map[string]any{
			"type": "membership", "claims": []string{"member_no", "board"}, "for": strings.Repeat("ab", 32),
			"ref": "member-42",
		}, &p)
		got, _ := url.Parse(p.Link)
		if got.Host != "attest" || got.Query().Get("claims") != "member_no,board" || got.Query().Get("name") != "Test assistant" {
			t.Fatalf("unexpected attestation proposal %s", p.Link)
		}
		h.call("propose_attestation", map[string]any{"type": "membership", "for": "short"}, true)

		id, token := f.offer(t, map[string]any{
			util.Fields.Attestation.Connection: connID, util.Fields.Attestation.Ref: "member-42",
		})
		raw := h.call("list_attestations", nil, false)
		if strings.Contains(raw, "Ada Lovelace") || strings.Contains(raw, token) {
			t.Fatalf("list_attestations exposed what the owner holds: %s", raw)
		}
		var revoked mcpserver.Attestation
		h.decode("revoke_attestation", map[string]any{"id": id}, &revoked)
		if revoked.Status != util.StatusRevoked {
			t.Fatalf("not revoked: %+v", revoked)
		}
	})

	t.Run("checks: proposed, then the verdict with only what was shown", func(t *testing.T) {
		var p mcpserver.ProposeResult
		h.decode("propose_check", map[string]any{
			"type": "membership", "issuers": []string{"Chess-Club.org"}, "claims": []string{"age_over_18"}, "ref": "door",
		}, &p)
		got, _ := url.Parse(p.Link)
		if got.Host != "check" || got.Query().Get("issuers") != "chess-club.org" {
			t.Fatalf("unexpected check proposal %s", p.Link)
		}

		id, present := f.ask(t, map[string]any{
			"type": "membership", "claims": []string{"age_over_18"}, "connection": connID, "ref": "door",
		})
		if resp := f.answer(t, present, f.presentFor(t, present, []string{"age_over_18"})); resp.StatusCode != http.StatusOK {
			t.Fatalf("answer refused: %d", resp.StatusCode)
		}
		var list mcpserver.CheckList
		h.decode("list_checks", nil, &list)
		if len(list.Checks) != 1 || list.Checks[0].ID != id || list.Checks[0].Verdict == nil {
			t.Fatalf("unexpected checks: %+v", list)
		}
		v := list.Checks[0].Verdict
		if v.State != "verified" || len(v.Claims) != 1 || v.Claims["age_over_18"] != true || v.Withheld != 2 {
			t.Fatalf("unexpected verdict: %+v", v)
		}
	})
}
