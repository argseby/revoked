package tests

import (
	"context"
	"encoding/json"
	"fmt"
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
		h.t.Fatalf("%s: isError=%v, content %s", name, res.IsError, mcpText(res))
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
		// Who should see it is only a suggestion, and only one of two.
		h.decode("propose_request", map[string]any{"template": "Event registration", "visibility": "workspace"}, &p)
		if got, _ := url.Parse(p.Link); got.Query().Get("visibility") != "workspace" {
			t.Fatalf("visibility not carried: %s", p.Link)
		}
		h.call("propose_request", map[string]any{"template": "Event registration", "visibility": "everyone"}, true)

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

func mcpText(res *mcp.CallToolResult) string {
	out := ""
	for _, c := range res.Content {
		if t, ok := c.(*mcp.TextContent); ok {
			out += t.Text
		}
	}
	return out
}

func TestMCPAssistantKeepsNotesInItsOwnSection(t *testing.T) {
	f := newWatermarkFixture(t)
	baseURL, _ := testutils.SetupTestApp(t)
	h := newMCPHarness(t, baseURL)

	h.call("write_record", map[string]any{"key": "note", "value": "x"}, true)

	var started mcpserver.ConnectResult
	h.decode("connect", map[string]any{"section": true}, &started)
	link, _ := url.Parse(started.Link)
	q := link.Query()
	if q.Get("section") != "1" || q.Get("poll") != baseURL || q.Get("permissions") != "" {
		t.Fatalf("unexpected connect link %s", started.Link)
	}
	authorizeTool(f.api, f.token, map[string]any{
		"clientId": q.Get("client"), "clientName": q.Get("name"), "redirectUri": q.Get("redirect"),
		"challenge": q.Get("challenge"), "poll": true, "section": true,
		"permissions": []string{util.PermSharesManage},
	}).Status(http.StatusOK)

	var status mcpserver.StatusResult
	h.decode("connection_status", nil, &status)
	if !status.Connected || !status.HasSection || status.ReadsVault {
		t.Fatalf("not connected with a section: %+v", status)
	}

	var rec mcpserver.VaultRecord
	h.decode("write_record", map[string]any{"key": "packing_list", "label": "Packing list", "value": "tent, stove"}, &rec)
	if rec.ID == "" || !rec.Writable {
		t.Fatalf("unexpected record: %+v", rec)
	}
	h.decode("write_record", map[string]any{"id": rec.ID, "value": "tent, stove, lamp"}, &rec)

	var list mcpserver.VaultList
	h.decode("list_vault", nil, &list)
	if len(list.Records) != 1 || list.Records[0].ID != rec.ID {
		t.Fatalf("the vault list shows more than its section: %+v", list)
	}
	h.call("read_record", map[string]any{"id": f.textID}, true)

	var share mcpserver.CreatedShare
	h.decode("create_share", map[string]any{"label": "Packing list", "records": []string{rec.ID}, "days": 7}, &share)
	if !strings.Contains(share.URL, "/s/") || share.Status != util.StatusActive {
		t.Fatalf("unexpected share: %+v", share)
	}
	h.call("create_share", map[string]any{"label": "x", "records": []string{f.textID}}, true)
	h.call("create_request", map[string]any{"label": "RSVP"}, true)

	h.decode("delete_record", map[string]any{"id": rec.ID}, &struct{}{})
	h.call("read_record", map[string]any{"id": rec.ID}, true)

	t.Run("asking to create requests comes back to this machine", func(t *testing.T) {
		client := fmt.Sprintf("http://127.0.0.1:%d", freeLoopbackPort(t))
		h2 := &mcpHarness{t: t, ctx: context.Background()}
		s, err := mcpserver.New(mcpserver.Config{
			Server: baseURL, Client: client, Name: "Test assistant",
			StatePath: filepath.Join(t.TempDir(), "connection.json"),
			Open:      func(link string) error { return nil },
		})
		if err != nil {
			t.Fatalf("new mcp server: %v", err)
		}
		st, ct := mcp.NewInMemoryTransports()
		if _, err := s.Connect(h2.ctx, st, nil); err != nil {
			t.Fatalf("connect server: %v", err)
		}
		h2.cs, err = mcp.NewClient(&mcp.Implementation{Name: "test"}, nil).Connect(h2.ctx, ct, nil)
		if err != nil {
			t.Fatalf("connect client: %v", err)
		}
		t.Cleanup(func() { _ = h2.cs.Close() })

		var started mcpserver.ConnectResult
		h2.decode("connect", map[string]any{"create": true}, &started)
		link, _ := url.Parse(started.Link)
		q := link.Query()
		if q.Get("poll") != "" || q.Get("vault") != "" || q.Get("redirect") != client+"/callback" ||
			q.Get("permissions") != util.PermSharesManage+","+util.PermRequestsManage {
			t.Fatalf("unexpected connect link %s", started.Link)
		}
		code := authorizeTool(f.api, f.token, map[string]any{
			"clientId": q.Get("client"), "clientName": q.Get("name"), "redirectUri": q.Get("redirect"),
			"challenge": q.Get("challenge"), "permissions": strings.Split(q.Get("permissions"), ","),
		}).Status(http.StatusOK).JSON().Object().Value("code").String().Raw()
		resp, err := http.Get(q.Get("redirect") + "?status=connected&code=" + url.QueryEscape(code) +
			"&state=" + url.QueryEscape(q.Get("state")))
		if err != nil {
			t.Fatalf("return to the assistant: %v", err)
		}
		resp.Body.Close()

		// The assistant asks as the workspace's primary identity.
		identity, _ := newIdentity(t, baseURL, f.token, "Party host", f.userID, f.wsID)
		f.api.Update(util.Coll.Identities, identity, f.token, map[string]any{
			util.Fields.Identity.IsPrimary: true,
		}).Expect().Status(http.StatusOK)
		var req mcpserver.CreatedRequest
		h2.decode("create_request", map[string]any{"label": "RSVP", "maxResponses": 30}, &req)
		if !strings.HasPrefix(req.URL, "revoked://r/") {
			t.Fatalf("unexpected request: %+v", req)
		}
	})
}
