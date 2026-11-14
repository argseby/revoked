package tests

import (
	"net/http"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"
)

func TestConnectionSections(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	f := newWatermarkFixture(t)
	conn, token := connectWithGrant(t, f.api, f.token, map[string]any{"section": true, "permissions": []string{"vault:write", "shares:manage"}, "allowHandOver": true})
	section := f.api.E.POST("/api/connection/sections").WithHeader(util.ConnectionHeader, token).WithJSON(map[string]any{"name": "First packet", "key": "packet_custom"}).Expect().Status(http.StatusCreated).JSON().Object()
	sectionID := section.Value("id").String().Raw()
	record := toolVault(f.api, token, http.MethodPost, "").WithJSON(map[string]any{"section": sectionID, "key": "packet_text", "label": "Name", "value": "Ada"}).Expect().Status(http.StatusCreated).JSON().Object().Value("id").String().Raw()
	snapshot := f.api.E.GET("/api/connection/sections").WithHeader(util.ConnectionHeader, token).Expect().Status(http.StatusOK).JSON().Object()
	snapshot.Value("sections").Array().Length().IsEqual(1)
	snapshot.Value("records").Array().Value(0).Object().Value("value").String().IsEqual("Ada")
	toolVault(f.api, token, http.MethodPatch, "/"+record).WithJSON(map[string]any{"key": "renamed_key", "type": "number", "value": "42"}).Expect().Status(http.StatusOK)
	toolVault(f.api, token, http.MethodGet, "/"+record).Expect().Status(http.StatusOK).JSON().Object().Value("type").String().IsEqual("number")
	f.api.E.PATCH("/api/connection/sections/"+sectionID).WithHeader(util.ConnectionHeader, token).WithJSON(map[string]any{"name": "Renamed packet"}).Expect().Status(http.StatusNoContent)
	link := f.api.E.POST("/api/connection/links").WithHeader(util.ConnectionHeader, token).WithJSON(map[string]any{"label": "Anna", "records": []string{record}, "sections": []string{sectionID}, "ref": "packet:" + sectionID, "password": "secret"}).Expect().Status(http.StatusCreated).JSON().Object()
	url := link.Value("url").String().Raw()
	_ = url
	linkID := link.Value("id").String().Raw()
	_, app := testutils.SetupTestApp(t)
	saved, _ := app.FindRecordById(util.Coll.Links, linkID)
	slug := saved.GetString(util.Fields.Link.Slug)
	f.api.E.GET("/api/public/links/" + slug).Expect().Status(http.StatusOK).JSON().Object().Value("requiresPassword").Boolean().IsTrue()
	f.api.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{"password": "wrong"}).Expect().Status(http.StatusUnauthorized)
	// A later record in the same section is visible through the existing link.
	toolVault(f.api, token, http.MethodPost, "").WithJSON(map[string]any{"section": sectionID, "key": "later", "label": "Later", "value": "Added"}).Expect().Status(http.StatusCreated)
	sectionSnapshot := f.api.E.GET("/api/connection/sections").WithHeader(util.ConnectionHeader, token).Expect().Status(http.StatusOK).JSON().Object()
	ids := sectionSnapshot.Value("sections").Array().Value(0).Object().Value("records").Array().Raw()
	f.api.E.PATCH("/api/connection/links/"+linkID).WithHeader(util.ConnectionHeader, token).WithJSON(map[string]any{"records": ids, "sections": []string{sectionID}}).Expect().Status(http.StatusOK)
	f.api.E.POST("/api/public/links/" + slug).WithJSON(map[string]any{"password": "secret"}).Expect().Status(http.StatusOK).JSON().Object().Value("records").Array().Length().IsEqual(2)
	// The same owner connecting a different tool still grants no access to this group.
	verifier, challenge := pkcePair()
	grant := authorizeTool(f.api, f.token, map[string]any{"clientId": "https://other-tool.example", "clientName": "Other tool", "redirectUri": "https://other-tool.example/", "challenge": challenge, "section": true, "permissions": []string{"vault:write", "shares:manage"}}).Status(http.StatusOK).JSON().Object()
	otherToken := f.api.E.POST("/api/connect/token").WithJSON(map[string]any{"code": grant.Value("code").String().Raw(), "verifier": verifier, "redirectUri": "https://other-tool.example/"}).Expect().Status(http.StatusOK).JSON().Object().Value("token").String().Raw()
	f.api.E.GET("/api/connection/sections").WithHeader(util.ConnectionHeader, otherToken).Expect().Status(http.StatusOK).JSON().Object().Value("sections").Array().Length().IsEqual(0)
	f.api.E.PATCH("/api/connection/sections/"+sectionID).WithHeader(util.ConnectionHeader, otherToken).WithJSON(map[string]any{"name": "No"}).Expect().Status(http.StatusNotFound)
	f.api.E.PATCH("/api/connection/links/"+linkID).WithHeader(util.ConnectionHeader, otherToken).WithJSON(map[string]any{"records": []string{}, "sections": []string{}}).Expect().Status(http.StatusNotFound)
	// A different connection cannot read, write, attach or share these sections.
	stranger := newWatermarkFixture(t)
	_, other := connectWithGrant(t, stranger.api, stranger.token, map[string]any{"section": true, "permissions": []string{"vault:write", "shares:manage"}})
	stranger.api.E.GET("/api/connection/sections").WithHeader(util.ConnectionHeader, other).Expect().Status(http.StatusOK).JSON().Object().Value("sections").Array().Length().IsEqual(0)
	stranger.api.E.PATCH("/api/connection/sections/"+sectionID).WithHeader(util.ConnectionHeader, other).WithJSON(map[string]any{"name": "Hijack"}).Expect().Status(http.StatusNotFound)
	toolVault(stranger.api, other, http.MethodPost, "").WithJSON(map[string]any{"section": sectionID, "key": "attack", "value": "No"}).Expect().Status(http.StatusForbidden)
	stranger.api.E.POST("/api/connection/links").WithHeader(util.ConnectionHeader, other).WithJSON(map[string]any{"label": "No", "sections": []string{sectionID}}).Expect().Status(http.StatusNotFound)
	// Owner-created records cannot be smuggled into a tool group by id.
	ownerRecord := newRecord(t, baseURL, f.token, f.userID, f.wsID, "private_owner_value", "Private")
	f.api.E.PATCH("/api/connection/sections/"+sectionID).WithHeader(util.ConnectionHeader, token).WithJSON(map[string]any{"records+": []string{ownerRecord}}).Expect().Status(http.StatusForbidden)
	// Taking the own-section grant away cuts off descendants immediately.
	setPermissions(f.api, conn, f.token, map[string]any{"section": false}).Status(http.StatusOK)
	f.api.E.GET("/api/connection/sections").WithHeader(util.ConnectionHeader, token).Expect().Status(http.StatusForbidden)
	toolVault(f.api, token, http.MethodGet, "/"+record).Expect().Status(http.StatusForbidden)
}
