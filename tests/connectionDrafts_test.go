package tests

import (
	"net/http"
	"net/url"
	"strings"
	"testing"

	"revoked/cmd/revoked-mcp/mcpserver"
	"revoked/tests/testutils"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
	"github.com/pocketbase/dbx"
)

func postDraft(api *testutils.PBClient, toolToken string, values map[string]string) *httpexpect.Response {
	return api.E.POST("/api/connection/drafts").
		WithHeader(util.ConnectionHeader, toolToken).
		WithJSON(map[string]any{"values": values}).Expect()
}

func TestAToolSuggestsValuesOnlyItsOwnerSees(t *testing.T) {
	f := newWatermarkFixture(t)
	baseURL, app := testutils.SetupTestApp(t)
	connID, toolToken := connectTool(t, f.api, f.token)

	t.Run("the owner reads the suggestion and discards it", func(t *testing.T) {
		api := f.api.T(t)
		id := postDraft(api, toolToken, map[string]string{"full_name": "Alex Example", "phone": " +49 1 "}).
			Status(http.StatusOK).JSON().Object().Value("id").String().Raw()

		got := api.E.GET("/api/connections/drafts/"+id).WithHeader("Authorization", f.token).
			Expect().Status(http.StatusOK).JSON().Object()
		got.Value("connection").IsEqual(connID)
		got.Value("values").Object().IsEqual(map[string]any{"full_name": "Alex Example", "phone": "+49 1"})

		api.E.DELETE("/api/connections/drafts/"+id).WithHeader("Authorization", f.token).
			Expect().Status(http.StatusNoContent)
		api.E.GET("/api/connections/drafts/"+id).WithHeader("Authorization", f.token).
			Expect().Status(http.StatusNotFound)
	})

	t.Run("nobody else reads it", func(t *testing.T) {
		api := f.api.T(t)
		id := postDraft(api, toolToken, map[string]string{"phone": "+49 1"}).
			Status(http.StatusOK).JSON().Object().Value("id").String().Raw()
		_, otherToken, err := testutils.CreateRandomUser(baseURL)
		if err != nil {
			t.Fatal(err)
		}
		api.E.GET("/api/connections/drafts/"+id).WithHeader("Authorization", otherToken).
			Expect().Status(http.StatusNotFound)
		api.E.DELETE("/api/connections/drafts/"+id).WithHeader("Authorization", otherToken).
			Expect().Status(http.StatusNoContent)
		api.E.GET("/api/connections/drafts/" + id).Expect().Status(http.StatusUnauthorized)
		// The other person's delete did nothing.
		api.E.GET("/api/connections/drafts/"+id).WithHeader("Authorization", f.token).
			Expect().Status(http.StatusOK)
	})

	t.Run("malformed values are refused whole", func(t *testing.T) {
		api := f.api.T(t)
		for _, values := range []map[string]string{
			{},
			{"Full Name": "x"},
			{"a": "  "},
			{"a": "x\x00y"},
			{"a": strings.Repeat("x", 4001)},
		} {
			postDraft(api, toolToken, values).Status(http.StatusBadRequest).
				JSON().Object().Value("message").String().NotEmpty()
		}
		postDraft(api, "not-a-token", map[string]string{"a": "x"}).Status(http.StatusUnauthorized)
	})

	t.Run("a paused tool's suggestion is not shown", func(t *testing.T) {
		api := f.api.T(t)
		id := postDraft(api, toolToken, map[string]string{"a": "x"}).
			Status(http.StatusOK).JSON().Object().Value("id").String().Raw()
		api.E.POST("/api/connections/"+connID+"/pause").WithHeader("Authorization", f.token).
			Expect().Status(http.StatusOK)
		api.E.GET("/api/connections/drafts/"+id).WithHeader("Authorization", f.token).
			Expect().Status(http.StatusNotFound)
		api.E.POST("/api/connections/"+connID+"/resume").WithHeader("Authorization", f.token).
			Expect().Status(http.StatusOK)
	})

	t.Run("the audit log names the keys, never the values", func(t *testing.T) {
		rows, err := app.FindAllRecords(util.Coll.AuditLogs, dbx.HashExp{
			util.Fields.AuditLog.Action:   "tool_drafted_values",
			util.Fields.AuditLog.RecordId: connID,
		})
		if err != nil || len(rows) == 0 {
			t.Fatalf("no audit rows: %v", err)
		}
		for _, r := range rows {
			data := r.GetString(util.Fields.AuditLog.NewData)
			if strings.Contains(data, "Alex Example") || strings.Contains(data, "+49") {
				t.Fatalf("audit row holds a value: %s", data)
			}
		}
	})
}

func TestMCPAssistantSuggestsValuesWithItsProposal(t *testing.T) {
	f := newWatermarkFixture(t)
	baseURL, _ := testutils.SetupTestApp(t)
	h := newMCPHarness(t, baseURL)

	args := map[string]any{
		"label": "Family backup", "keys": []string{"full_name", "phone"},
		"values": map[string]string{"full_name": "Alex Example"},
	}
	h.call("propose_share", args, true) // not connected yet

	var started mcpserver.ConnectResult
	h.decode("connect", nil, &started)
	link, _ := url.Parse(started.Link)
	q := link.Query()
	authorizeTool(f.api, f.token, map[string]any{
		"clientId": q.Get("client"), "clientName": q.Get("name"), "redirectUri": q.Get("redirect"),
		"challenge": q.Get("challenge"), "poll": true,
	}).Status(http.StatusOK)
	var status mcpserver.StatusResult
	h.decode("connection_status", nil, &status)
	if !status.Connected {
		t.Fatalf("not connected: %+v", status)
	}

	h.call("propose_share", map[string]any{
		"label": "x", "keys": []string{"phone"}, "values": map[string]string{"email": "a@b.c"},
	}, true) // a value for a key it did not propose

	var p mcpserver.ProposeResult
	h.decode("propose_share", args, &p)
	got, _ := url.Parse(p.Link)
	draft := got.Query().Get("draft")
	if p.Suggested != 1 || len(draft) != 24 || strings.Contains(p.Link, "Alex") {
		t.Fatalf("unexpected proposal %+v", p)
	}
	f.api.E.GET("/api/connections/drafts/"+draft).WithHeader("Authorization", f.token).
		Expect().Status(http.StatusOK).JSON().Object().
		Value("values").Object().Value("full_name").IsEqual("Alex Example")
}
