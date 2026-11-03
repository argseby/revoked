package tests

import (
	"bytes"
	"fmt"
	"mime/multipart"
	"net/http"
	"strings"
	"testing"
	"time"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/gavv/httpexpect/v2"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// connectWithGrant connects a tool by polling, the way any tool on the web
// connects, and returns the connection id and token.
func connectWithGrant(t *testing.T, api *testutils.PBClient, userToken string, grant map[string]any) (string, string) {
	t.Helper()
	verifier, challenge := pkcePair()
	redirect := toolOrigin + "/"
	body := map[string]any{
		"clientId": toolOrigin, "clientName": "Mietunterlagen", "redirectUri": redirect,
		"challenge": challenge, "poll": true,
	}
	for k, v := range grant {
		body[k] = v
	}
	authorizeTool(api, userToken, body).Status(http.StatusOK)
	resp := api.E.POST("/api/connect/token").WithHeader("Origin", toolOrigin).
		WithJSON(map[string]any{"verifier": verifier, "redirectUri": redirect}).
		Expect().Status(http.StatusOK).JSON().Object()
	return resp.Value("connection").Object().Value("id").String().Raw(), resp.Value("token").String().Raw()
}

func toolVault(api *testutils.PBClient, toolToken, method, path string) *httpexpect.Request {
	return api.E.Request(method, "/api/vault"+path).WithHeader(util.ConnectionHeader, toolToken)
}

func sectionRecords(t *testing.T, app core.App, id string) []string {
	t.Helper()
	s, err := app.FindRecordById(util.Coll.Sections, id)
	if err != nil {
		t.Fatalf("section %s: %v", id, err)
	}
	return s.GetStringSlice(util.Fields.Section.Records)
}

func TestAToolKeepsItsOwnSection(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	f := newWatermarkFixture(t)
	ibanID := newRecord(t, baseURL, f.token, f.userID, f.wsID, "iban", "DE89370400440532013000")

	connID, token := connectWithGrant(t, f.api, f.token, map[string]any{"section": true})
	conn, err := app.FindRecordById(util.Coll.Connections, connID)
	if err != nil {
		t.Fatalf("connection: %v", err)
	}
	sectionID := conn.GetString(util.Fields.Connection.Section)
	section, err := app.FindRecordById(util.Coll.Sections, sectionID)
	if err != nil || section.GetString(util.Fields.Section.Key) != "mietunterlagen" ||
		section.GetString(util.Fields.Section.User) != f.userID {
		t.Fatalf("no own section named after the tool: %v", err)
	}

	var written string
	t.Run("it writes records into its section, marked as its own", func(t *testing.T) {
		obj := toolVault(f.api, token, http.MethodPost, "").
			WithJSON(map[string]any{"key": "move_in", "label": "Move-in date", "value": "2026-12-01"}).
			Expect().Status(http.StatusCreated).JSON().Object()
		obj.Value("writable").Boolean().IsTrue()
		obj.Value("writtenByName").String().IsEqual("Mietunterlagen")
		written = obj.Value("id").String().Raw()

		rec, _ := app.FindRecordById(util.Coll.Records, written)
		if rec.GetString(util.Fields.Record.WrittenBy) != connID || rec.GetString(util.Fields.Record.User) != f.userID {
			t.Fatalf("record not the owner's, written by the tool")
		}
		if got := sectionRecords(t, app, sectionID); len(got) != 1 || got[0] != written {
			t.Fatalf("record not in the tool's section: %v", got)
		}
	})

	t.Run("it uploads a file and reads it back", func(t *testing.T) {
		var buf bytes.Buffer
		mw := multipart.NewWriter(&buf)
		_ = mw.WriteField("key", "contract")
		fw, _ := mw.CreateFormFile("file", "contract.pdf")
		_, _ = fw.Write(f.pdfBytes)
		_ = mw.Close()
		id := toolVault(f.api, token, http.MethodPost, "").
			WithHeader("Content-Type", mw.FormDataContentType()).WithBytes(buf.Bytes()).
			Expect().Status(http.StatusCreated).JSON().Object().Value("id").String().Raw()
		toolVault(f.api, token, http.MethodGet, "/"+id).Expect().Status(http.StatusOK).
			JSON().Object().Value("filename").String().IsEqual("contract.pdf")
		body := toolVault(f.api, token, http.MethodGet, "/"+id+"/file").Expect().Status(http.StatusOK).Body().Raw()
		if body != string(f.pdfBytes) {
			t.Fatalf("file came back different")
		}
	})

	t.Run("it sees nothing else in the vault", func(t *testing.T) {
		raw := toolVault(f.api, token, http.MethodGet, "").Expect().Status(http.StatusOK).Body().Raw()
		if strings.Contains(raw, ibanID) || !strings.Contains(raw, written) {
			t.Fatalf("unexpected list: %s", raw)
		}
		toolVault(f.api, token, http.MethodGet, "/"+ibanID).Expect().Status(http.StatusNotFound)
	})

	t.Run("a record the owner adds is readable and stays the owner's", func(t *testing.T) {
		f.api.Update(util.Coll.Sections, sectionID, f.token, map[string]any{
			util.Fields.Section.Records + "+": ibanID,
		}).Expect().Status(http.StatusOK)
		toolVault(f.api, token, http.MethodGet, "/"+ibanID).Expect().Status(http.StatusOK).
			JSON().Object().Value("writable").Boolean().IsFalse()
		toolVault(f.api, token, http.MethodPatch, "/"+ibanID).WithJSON(map[string]any{"value": "x"}).
			Expect().Status(http.StatusForbidden).JSON().Object().
			Value("code").String().IsEqual(util.Errors.VaultReadOnly.ErrorCode)
		toolVault(f.api, token, http.MethodDelete, "/"+ibanID).Expect().Status(http.StatusForbidden)

		f.api.Update(util.Coll.Sections, sectionID, f.token, map[string]any{
			util.Fields.Section.Records + "-": ibanID,
		}).Expect().Status(http.StatusOK)
		toolVault(f.api, token, http.MethodGet, "/"+ibanID).Expect().Status(http.StatusNotFound)
	})

	t.Run("it changes and deletes what it wrote", func(t *testing.T) {
		toolVault(f.api, token, http.MethodPatch, "/"+written).WithJSON(map[string]any{"value": "2027-01-01"}).
			Expect().Status(http.StatusOK)
		toolVault(f.api, token, http.MethodGet, "/"+written).Expect().Status(http.StatusOK).
			JSON().Object().Value("value").String().IsEqual("2027-01-01")
		toolVault(f.api, token, http.MethodDelete, "/"+written).Expect().Status(http.StatusNoContent)
		toolVault(f.api, token, http.MethodGet, "/"+written).Expect().Status(http.StatusNotFound)
	})

	t.Run("its writes are audited without their values", func(t *testing.T) {
		rows, err := app.FindRecordsByFilter(util.Coll.AuditLogs,
			"collection = 'records' && recordId = {:id}", "", 0, 0, dbx.Params{"id": written})
		if err != nil || len(rows) < 2 {
			t.Fatalf("missing audit rows: %v", err)
		}
		for _, r := range rows {
			if strings.Contains(r.GetString(util.Fields.AuditLog.NewData), "2027-01-01") ||
				strings.Contains(r.GetString(util.Fields.AuditLog.OldData), "2026-12-01") {
				t.Fatalf("audit row kept a value")
			}
		}
	})

	t.Run("nobody sets who wrote a record through the collection API", func(t *testing.T) {
		f.api.Update(util.Coll.Records, ibanID, f.token, map[string]any{
			util.Fields.Record.WrittenBy: connID, util.Fields.Record.WrittenByName: "Mietunterlagen",
		}).Expect().Status(http.StatusBadRequest)
	})

	t.Run("it stops at its storage cap", func(t *testing.T) {
		t.Setenv(util.ConnectionStorageEnv, "1")
		toolVault(f.api, token, http.MethodPost, "").
			WithJSON(map[string]any{"key": "big", "value": strings.Repeat("x", 2<<20)}).
			Expect().Status(http.StatusRequestEntityTooLarge).JSON().Object().
			Value("code").String().IsEqual(util.Errors.VaultStorageExceeded.ErrorCode)
	})

	t.Run("taking the section away keeps it, and giving it back brings the same one", func(t *testing.T) {
		setPermissions(f.api, connID, f.token, map[string]any{"section": false}).Status(http.StatusOK).
			JSON().Object().Value("sectionOff").Boolean().IsTrue()
		toolVault(f.api, token, http.MethodGet, "").Expect().Status(http.StatusForbidden)
		setPermissions(f.api, connID, f.token, map[string]any{"section": true}).Status(http.StatusOK).
			JSON().Object().Value("section").String().IsEqual(sectionID)
		toolVault(f.api, token, http.MethodGet, "").Expect().Status(http.StatusOK)
	})

	t.Run("a section the owner added stays readable while its own is off", func(t *testing.T) {
		note := toolVault(f.api, token, http.MethodPost, "").
			WithJSON(map[string]any{"key": "own_note", "value": "mine"}).
			Expect().Status(http.StatusCreated).JSON().Object().Value("id").String().Raw()
		added := extractID(t, baseURL, util.Coll.Sections, f.token, map[string]any{
			util.Fields.Section.Key: "banking", util.Fields.Section.Name: "Banking",
			util.Fields.Section.Records: []string{ibanID},
			util.Fields.Section.User:    f.userID, util.Fields.Section.Workspace: f.wsID,
		})
		setPermissions(f.api, connID, f.token, map[string]any{"section": false, "sections": []string{added}}).
			Status(http.StatusOK)
		toolVault(f.api, token, http.MethodGet, "/"+ibanID).Expect().Status(http.StatusOK)
		raw := toolVault(f.api, token, http.MethodGet, "").Expect().Status(http.StatusOK).Body().Raw()
		if strings.Contains(raw, note) || !strings.Contains(raw, ibanID) {
			t.Fatalf("its own section is still in reach while off: %s", raw)
		}
		setPermissions(f.api, connID, f.token, map[string]any{"section": true, "sections": []string{}}).
			Status(http.StatusOK)
	})

	t.Run("read only means read only", func(t *testing.T) {
		setPermissions(f.api, connID, f.token, map[string]any{
			"section": true, "permissions": []string{util.PermVaultRead},
		}).Status(http.StatusOK).JSON().Object().Value("vaultAccess").String().IsEqual(util.VaultAccessRead)
		toolVault(f.api, token, http.MethodPost, "").WithJSON(map[string]any{"key": "nope", "value": "x"}).
			Expect().Status(http.StatusForbidden)
		setPermissions(f.api, connID, f.token, map[string]any{
			"permissions": []string{util.PermVaultWrite},
		}).Status(http.StatusOK)
	})

	t.Run("the section and its records stay the owner's after a disconnect", func(t *testing.T) {
		id := toolVault(f.api, token, http.MethodPost, "").
			WithJSON(map[string]any{"key": "kept", "value": "still here"}).
			Expect().Status(http.StatusCreated).JSON().Object().Value("id").String().Raw()
		f.api.E.POST("/api/connections/"+connID+"/disconnect").WithHeader("Authorization", f.token).
			WithJSON(map[string]any{}).Expect().Status(http.StatusNoContent)
		if _, err := app.FindRecordById(util.Coll.Sections, sectionID); err != nil {
			t.Fatalf("section gone after disconnect: %v", err)
		}
		rec, err := app.FindRecordById(util.Coll.Records, id)
		if err != nil || rec.GetString(util.Fields.Record.WrittenByName) != "Mietunterlagen" {
			t.Fatalf("record lost after disconnect: %v", err)
		}
	})
}

func TestAToolDoesWhatItsPermissionsAllow(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	f := newWatermarkFixture(t)
	ibanID := newRecord(t, baseURL, f.token, f.userID, f.wsID, "iban", "DE89370400440532013000")

	t.Run("it can't be given what only people and keys hold", func(t *testing.T) {
		_, challenge := pkcePair()
		authorizeTool(f.api, f.token, map[string]any{
			"clientId": toolOrigin, "redirectUri": toolOrigin + "/", "challenge": challenge,
			"poll": true, "permissions": []string{util.PermMembersAdd},
		}).Status(http.StatusBadRequest).JSON().Object().
			Value("code").String().IsEqual(util.Errors.ConnectionPermissionInvalid.ErrorCode)
	})

	connID, token := connectWithGrant(t, f.api, f.token, map[string]any{
		"section": true, "permissions": []string{util.PermSharesManage, util.PermRequestsManage},
	})

	t.Run("it says what it may do", func(t *testing.T) {
		obj := toolGet(f.api, token).Status(http.StatusOK).JSON().Object()
		obj.Value("permissions").Array().ContainsAll(util.PermSharesManage, util.PermRequestsManage, util.PermVaultWrite)
		obj.Value("vaultAccess").String().IsEqual(util.VaultAccessWrite)
	})

	own := toolVault(f.api, token, http.MethodPost, "").
		WithJSON(map[string]any{"key": "guest_list", "value": "Ada, Grace"}).
		Expect().Status(http.StatusCreated).JSON().Object().Value("id").String().Raw()

	t.Run("it shares what is within reach, and nothing else", func(t *testing.T) {
		obj := f.api.E.POST("/api/connection/links").WithHeader(util.ConnectionHeader, token).
			WithJSON(map[string]any{"label": "Guests", "records": []string{own}, "ref": "party"}).
			Expect().Status(http.StatusCreated).JSON().Object()
		obj.Value("url").String().Contains("/s/")
		obj.Value("ref").String().IsEqual("party")
		f.api.E.POST("/api/connection/links").WithHeader(util.ConnectionHeader, token).
			WithJSON(map[string]any{"label": "Steal", "records": []string{ibanID}}).
			Expect().Status(http.StatusNotFound)
		toolGet(f.api, token).Status(http.StatusOK).JSON().Object().Value("links").Array().Length().IsEqual(1)
	})

	t.Run("it creates a request in the owner's workspace, never by polling", func(t *testing.T) {
		f.api.E.POST("/api/connection/requests").WithHeader(util.ConnectionHeader, token).
			WithJSON(map[string]any{"label": "RSVP"}).
			Expect().Status(http.StatusForbidden).JSON().Object().
			Value("code").String().IsEqual(util.Errors.ConnectionPolled.ErrorCode)

		verifier, challenge := pkcePair()
		redirect := toolOrigin + "/"
		code := authorizeTool(f.api, f.token, map[string]any{
			"clientId": toolOrigin, "redirectUri": redirect, "challenge": challenge,
		}).Status(http.StatusOK).JSON().Object().Value("code").String().Raw()
		direct := f.api.E.POST("/api/connect/token").WithJSON(map[string]any{
			"code": code, "verifier": verifier, "redirectUri": redirect,
		}).Expect().Status(http.StatusOK).JSON().Object().Value("token").String().Raw()

		f.api.E.POST("/api/connection/requests").WithHeader(util.ConnectionHeader, direct).
			WithJSON(map[string]any{"label": "RSVP"}).
			Expect().Status(http.StatusForbidden).JSON().Object().
			Value("code").String().IsEqual(util.Errors.IdentityRequired.ErrorCode)
		identity, _ := newIdentity(t, baseURL, f.token, "Party host", f.userID, f.wsID)
		f.api.E.POST("/api/connection/requests").WithHeader(util.ConnectionHeader, direct).
			WithJSON(map[string]any{"label": "RSVP", "maxResponses": 30, "identity": identity}).
			Expect().Status(http.StatusCreated).JSON().Object().
			Value("url").String().HasPrefix("revoked://r/")
	})

	t.Run("without the permission it is refused", func(t *testing.T) {
		setPermissions(f.api, connID, f.token, map[string]any{"permissions": []string{}}).Status(http.StatusOK)
		f.api.E.POST("/api/connection/links").WithHeader(util.ConnectionHeader, token).
			WithJSON(map[string]any{"label": "Guests", "records": []string{own}}).
			Expect().Status(http.StatusForbidden).JSON().Object().
			Value("code").String().IsEqual(util.Errors.ConnectionNotPermitted.ErrorCode)
		toolVault(f.api, token, http.MethodGet, "").Expect().Status(http.StatusForbidden)
	})

	t.Run("the owner can add one of their sections to it", func(t *testing.T) {
		sectionID := extractID(t, baseURL, util.Coll.Sections, f.token, map[string]any{
			util.Fields.Section.Key: "banking", util.Fields.Section.Name: "Banking",
			util.Fields.Section.Records: []string{ibanID},
			util.Fields.Section.User:    f.userID, util.Fields.Section.Workspace: f.wsID,
		})
		setPermissions(f.api, connID, f.token, map[string]any{
			"permissions": []string{util.PermVaultRead}, "sections": []string{sectionID},
		}).Status(http.StatusOK)
		toolVault(f.api, token, http.MethodGet, "/"+ibanID).Expect().Status(http.StatusOK)

		other := newWatermarkFixture(t)
		foreign := extractID(t, baseURL, util.Coll.Sections, other.token, map[string]any{
			util.Fields.Section.Key: "theirs", util.Fields.Section.Name: "Theirs",
			util.Fields.Section.User: other.userID, util.Fields.Section.Workspace: other.wsID,
		})
		setPermissions(f.api, connID, f.token, map[string]any{"sections": []string{foreign}}).
			Status(http.StatusBadRequest).JSON().Object().
			Value("code").String().IsEqual(util.Errors.VaultSectionInvalid.ErrorCode)
	})
}

func TestAKeyReachesOnlyItsSections(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)
	userID, token, _ := testutils.CreateRandomUser(baseURL)
	refreshed := api.AuthRefresh(util.Coll.Users, token).Expect().Status(http.StatusOK)
	token = testutils.ExtractString(refreshed, "token")
	wsID := refreshed.JSON().Object().Value("record").Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	ibanID := newRecord(t, baseURL, token, userID, wsID, "iban", "DE89370400440532013000")
	sectionID := extractID(t, baseURL, util.Coll.Sections, token, map[string]any{
		util.Fields.Section.Key: "steam", util.Fields.Section.Name: "Steam",
		util.Fields.Section.User: userID, util.Fields.Section.Workspace: wsID,
	})

	newKey := func(scopes, sections []string) *httpexpect.Response {
		return api.Create(util.Coll.ApiKeys, token, map[string]any{
			"label": fmt.Sprintf("key-%d", time.Now().UnixNano()), "workspace": wsID, "user": userID,
			"scopes": scopes, "sections": sections,
		}).Expect()
	}

	t.Run("a key with vault access needs sections", func(t *testing.T) {
		newKey([]string{util.PermVaultWrite}, nil).Status(http.StatusBadRequest)
	})

	resp := newKey([]string{util.PermVaultWrite, util.PermSharesManage}, []string{sectionID}).Status(http.StatusOK)
	resp.JSON().Object().Value(util.Fields.ApiKey.VaultAccess).String().IsEqual(util.VaultAccessWrite)
	resp.JSON().Object().Value(util.Fields.ApiKey.Scopes).Array().NotContainsAny(util.ScopeRecordRead, util.ScopeRecordCreate)
	plain := resp.Header("X-Plain-Token").Raw()
	keyed := func(method, path string) *httpexpect.Request {
		return api.E.Request(method, "/api/vault"+path).WithHeader("X-API-Key", plain)
	}

	t.Run("it writes into its section and reads it back", func(t *testing.T) {
		id := keyed(http.MethodPost, "").WithJSON(map[string]any{"key": "now_playing", "value": "Hunt: Showdown"}).
			Expect().Status(http.StatusCreated).JSON().Object().Value("id").String().Raw()
		keyed(http.MethodGet, "/"+id).Expect().Status(http.StatusOK).
			JSON().Object().Value("value").String().IsEqual("Hunt: Showdown")
		keyed(http.MethodPatch, "/"+id).WithJSON(map[string]any{"value": "Not playing"}).Expect().Status(http.StatusOK)
	})

	t.Run("the rest of the vault stays out of reach", func(t *testing.T) {
		keyed(http.MethodGet, "/"+ibanID).Expect().Status(http.StatusNotFound)
		raw := api.E.GET("/api/collections/records/records").WithHeader("X-API-Key", plain).Expect().Body().Raw()
		if strings.Contains(raw, "DE8937") || strings.Contains(raw, ibanID) {
			t.Fatalf("the collection API opened the vault to a key: %s", raw)
		}
	})

	t.Run("a key without vault access reaches none of it", func(t *testing.T) {
		other := newKey([]string{util.PermSharesRead}, []string{sectionID}).Status(http.StatusOK)
		api.E.GET("/api/vault").WithHeader("X-API-Key", other.Header("X-Plain-Token").Raw()).
			Expect().Status(http.StatusForbidden).JSON().Object().
			Value("code").String().IsEqual(util.Errors.VaultNotAllowed.ErrorCode)
	})

	t.Run("only the creator's own sections can be chosen", func(t *testing.T) {
		otherID, otherToken, _ := testutils.CreateRandomUser(baseURL)
		otherWS := activeWorkspaceOf(t, api, otherID, otherToken)
		foreign := extractID(t, baseURL, util.Coll.Sections, otherToken, map[string]any{
			util.Fields.Section.Key: "theirs", util.Fields.Section.Name: "Theirs",
			util.Fields.Section.User: otherID, util.Fields.Section.Workspace: otherWS,
		})
		newKey([]string{util.PermVaultRead}, []string{foreign}).Status(http.StatusBadRequest)
	})
}
