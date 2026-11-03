package tests

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"path/filepath"
	"strings"
	"testing"

	"revoked/cmd/revoked-mcp/mcpserver"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/pocketbase/dbx"
)

func vaultGet(api *testutils.PBClient, toolToken, path string) *httpexpect.Response {
	return api.E.GET("/api/connection/vault"+path).WithHeader(util.ConnectionHeader, toolToken).Expect()
}

// connectForVault connects a tool through its return address, the one way a
// token can read the vault, and returns the connection id and token.
func connectForVault(t *testing.T, api *testutils.PBClient, userToken string, allow bool) (string, string) {
	t.Helper()
	verifier, challenge := pkcePair()
	redirect := toolOrigin + "/"
	grant := authorizeTool(api, userToken, map[string]any{
		"clientId": toolOrigin, "clientName": "Assistant", "redirectUri": redirect,
		"challenge": challenge, "allowVaultRead": allow,
	}).Status(http.StatusOK).JSON().Object()
	resp := api.E.POST("/api/connect/token").WithJSON(map[string]any{
		"code": grant.Value("code").String().Raw(), "verifier": verifier, "redirectUri": redirect,
	}).Expect().Status(http.StatusOK).JSON().Object()
	return resp.Value("connection").Object().Value("id").String().Raw(), resp.Value("token").String().Raw()
}

func TestConnectedToolReadsTheVaultOnlyWhenAllowed(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	f := newWatermarkFixture(t)
	ibanID := newRecord(t, baseURL, f.token, f.userID, f.wsID, "iban", "DE89370400440532013000")
	sealedID := newRecord(t, baseURL, f.token, f.userID, f.wsID, "diary", "kept to myself")
	// Stands in for an encrypted record: only its flag matters here.
	if _, err := app.DB().NewQuery("UPDATE {{" + util.Coll.Records + "}} SET [[" + util.Fields.Record.Sealed +
		"]] = TRUE, [[" + util.Fields.Record.Value + "]] = '' WHERE id = {:id}").
		Bind(dbx.Params{"id": sealedID}).Execute(); err != nil {
		t.Fatalf("seal record: %v", err)
	}
	other := newWatermarkFixture(t)
	foreignID := newRecord(t, baseURL, other.token, other.userID, other.wsID, "iban", "GB33BUKB20201555555555")

	t.Run("a polled answer can never carry the vault", func(t *testing.T) {
		_, challenge := pkcePair()
		authorizeTool(f.api, f.token, map[string]any{
			"clientId": toolOrigin, "redirectUri": toolOrigin + "/", "challenge": challenge,
			"poll": true, "allowVaultRead": true,
		}).Status(http.StatusBadRequest).JSON().Object().
			Value("code").String().IsEqual(util.Errors.ConnectionVaultPolled.ErrorCode)
	})

	connID, token := connectForVault(t, f.api, f.token, true)

	t.Run("it lists the owner's records without values, and reads one", func(t *testing.T) {
		toolGet(f.api, token).Status(http.StatusOK).JSON().Object().Value("vaultReadable").Boolean().IsTrue()

		raw := vaultGet(f.api, token, "").Status(http.StatusOK).Body().Raw()
		if strings.Contains(raw, "DE8937") || strings.Contains(raw, sealedID) ||
			strings.Contains(raw, foreignID) || !strings.Contains(raw, ibanID) {
			t.Fatalf("unexpected vault list: %s", raw)
		}
		vaultGet(f.api, token, "/"+ibanID).Status(http.StatusOK).JSON().Object().
			Value("value").String().IsEqual("DE89370400440532013000")
		vaultGet(f.api, token, "/"+sealedID).Status(http.StatusNotFound)
		vaultGet(f.api, token, "/"+foreignID).Status(http.StatusNotFound)
	})

	t.Run("each read is in the audit log by key, never by value", func(t *testing.T) {
		rows, err := app.FindRecordsByFilter(util.Coll.AuditLogs,
			util.Fields.AuditLog.RecordId+" = {:c} && "+util.Fields.AuditLog.Action+" = 'tool_read_record'",
			"", 0, 0, dbx.Params{"c": connID})
		if err != nil || len(rows) == 0 {
			t.Fatalf("no audit row for the read: %v", err)
		}
		data := rows[0].GetString(util.Fields.AuditLog.NewData)
		if !strings.Contains(data, `"key":"iban"`) || strings.Contains(data, "DE8937") {
			t.Fatalf("unexpected audit data: %s", data)
		}
	})

	t.Run("a token collected by polling cannot read it", func(t *testing.T) {
		verifier, challenge := pkcePair()
		redirect := toolOrigin + "/"
		authorizeTool(f.api, f.token, map[string]any{
			"clientId": toolOrigin, "redirectUri": redirect, "challenge": challenge, "poll": true,
		}).Status(http.StatusOK)
		polled := f.api.E.POST("/api/connect/token").WithHeader("Origin", toolOrigin).
			WithJSON(map[string]any{"verifier": verifier, "redirectUri": redirect}).
			Expect().Status(http.StatusOK).JSON().Object().Value("token").String().Raw()
		toolGet(f.api, polled).Status(http.StatusOK).JSON().Object().Value("vaultReadable").Boolean().IsFalse()
		vaultGet(f.api, polled, "").Status(http.StatusForbidden).JSON().Object().
			Value("code").String().IsEqual(util.Errors.ConnectionVaultPolled.ErrorCode)
	})

	t.Run("the owner can withdraw it, and only a new connect grants it again", func(t *testing.T) {
		setPermissions(f.api, connID, f.token, map[string]any{"allowVaultRead": true}).
			Status(http.StatusBadRequest).JSON().Object().
			Value("code").String().IsEqual(util.Errors.ConnectionVaultReconnect.ErrorCode)
		setPermissions(f.api, connID, f.token, map[string]any{"allowVaultRead": false}).Status(http.StatusOK)
		vaultGet(f.api, token, "").Status(http.StatusForbidden).JSON().Object().
			Value("code").String().IsEqual(util.Errors.ConnectionVaultNotAllowed.ErrorCode)
	})

	t.Run("a tool that was not allowed cannot read it", func(t *testing.T) {
		_, plain := connectForVault(t, other.api, other.token, false)
		vaultGet(other.api, plain, "").Status(http.StatusForbidden)
	})
}

func freeLoopbackPort(t *testing.T) int {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("free port: %v", err)
	}
	defer ln.Close()
	return ln.Addr().(*net.TCPAddr).Port
}

func TestMCPAssistantReadsTheVaultAfterTheOwnerAllowsIt(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	f := newWatermarkFixture(t)
	ibanID := newRecord(t, baseURL, f.token, f.userID, f.wsID, "iban", "DE89370400440532013000")

	client := fmt.Sprintf("http://127.0.0.1:%d", freeLoopbackPort(t))
	h := &mcpHarness{t: t, ctx: context.Background()}
	s, err := mcpserver.New(mcpserver.Config{
		Server: baseURL, Client: client, Name: "Test assistant",
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

	h.call("list_vault", nil, true)

	var started mcpserver.ConnectResult
	h.decode("connect", map[string]any{"vault": true}, &started)
	link, _ := url.Parse(started.Link)
	q := link.Query()
	if q.Get("vault") != "read" || q.Get("poll") != "" || started.CheckCode != "" ||
		q.Get("redirect") != client+"/callback" {
		t.Fatalf("unexpected vault connect link %s", started.Link)
	}

	var status mcpserver.StatusResult
	h.decode("connection_status", nil, &status)
	if !status.Pending || status.Connected {
		t.Fatalf("not waiting for the owner: %+v", status)
	}

	code := authorizeTool(f.api, f.token, map[string]any{
		"clientId": q.Get("client"), "clientName": q.Get("name"), "redirectUri": q.Get("redirect"),
		"challenge": q.Get("challenge"), "allowVaultRead": true,
	}).Status(http.StatusOK).JSON().Object().Value("code").String().Raw()

	// What the app opens in the owner's browser; a wrong state is turned away.
	back := q.Get("redirect") + "?status=connected&code=" + url.QueryEscape(code)
	if resp, err := http.Get(back + "&state=forged"); err != nil || resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("a forged state was accepted: %v", err)
	}
	resp, err := http.Get(back + "&state=" + url.QueryEscape(q.Get("state")))
	if err != nil {
		t.Fatalf("return to the assistant: %v", err)
	}
	page, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !strings.Contains(string(page), "is connected") {
		t.Fatalf("unexpected return page: %s", page)
	}

	h.decode("connection_status", nil, &status)
	if !status.Connected || !status.ReadsVault {
		t.Fatalf("not reading the vault after the owner allowed it: %+v", status)
	}

	var list mcpserver.VaultList
	raw := h.call("list_vault", nil, false)
	_ = json.Unmarshal([]byte(raw), &list)
	found := false
	for _, r := range list.Records {
		found = found || r.ID == ibanID
	}
	if !found || strings.Contains(raw, "DE8937") {
		t.Fatalf("unexpected vault list: %s", raw)
	}
	var rec mcpserver.VaultRecord
	h.decode("read_record", map[string]any{"id": ibanID}, &rec)
	if rec.Key != "iban" || rec.Value != "DE89370400440532013000" {
		t.Fatalf("unexpected record: %+v", rec)
	}
}
