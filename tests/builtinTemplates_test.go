package tests

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"revoked/cmd/revoked/services"
	"revoked/tests/testutils"
	"revoked/util"
	"testing"
)

// writeTemplateFile drops one catalogue file into dir, as an operator would.
func writeTemplateFile(t *testing.T, dir, filename string, tpl map[string]any) {
	t.Helper()
	data, err := json.Marshal(tpl)
	if err != nil {
		t.Fatalf("marshal template: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, filename), data, 0o644); err != nil {
		t.Fatalf("write template file: %v", err)
	}
}

func minimalTemplate(slug, name string) map[string]any {
	return map[string]any{
		"id":          slug,
		"name":        name,
		"description": "test template",
		"schema": map[string]any{
			"records": []map[string]any{
				{"key": "field_one", "label": "Field one", "type": "text"},
			},
		},
	}
}

func TestBuiltinTemplatesSeededOnServe(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	_, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}

	items := api.E.GET("/api/collections/"+util.Coll.Templates+"/records").
		WithHeader("Authorization", token).
		WithQuery("perPage", "100").
		Expect().Status(http.StatusOK).
		JSON().Object().Value("items").Array()

	builtins := 0
	foundWifi := false
	for _, raw := range items.Iter() {
		item := raw.Object().Raw()
		if item[util.Fields.Template.Workspace] != "" {
			continue
		}
		builtins++
		if item["id"] == services.BuiltinTemplateRecordId("wifi_access") {
			foundWifi = true
			if item[util.Fields.Template.Description] == "" {
				t.Error("built-in template is missing its description")
			}
		}
	}
	if builtins < 12 {
		t.Errorf("expected at least the 12 embedded built-in templates, got %d", builtins)
	}
	if !foundWifi {
		t.Error("wifi_access built-in template not found in listing")
	}
}

func TestBuiltinTemplatesInvisibleToGuests(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	// The row-level rule filters every record for an anonymous caller, so the
	// list is a 200 with no items rather than a refusal.
	api.E.GET("/api/collections/" + util.Coll.Templates + "/records").
		Expect().Status(http.StatusOK).
		JSON().Object().Value("items").Array().Length().IsEqual(0)

	api.E.GET("/api/collections/" + util.Coll.Templates + "/records/" + services.BuiltinTemplateRecordId("wifi_access")).
		Expect().Status(http.StatusNotFound)
}

func TestBuiltinTemplatesReadOnlyThroughApi(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	_, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}

	builtinID := services.BuiltinTemplateRecordId("wifi_access")

	// The update/delete rules cannot match a row without a workspace, so the
	// record is invisible to the write path even for a workspace admin.
	api.Update(util.Coll.Templates, builtinID, token, map[string]any{
		util.Fields.Template.Name: "hijacked",
	}).Expect().Status(http.StatusNotFound)

	api.Delete(util.Coll.Templates, builtinID, token).
		Expect().Status(http.StatusNotFound)
}

func TestBuiltinTemplatesDropInLifecycle(t *testing.T) {
	_, app := testutils.SetupTestApp(t)

	dir := t.TempDir()
	dropinID := services.BuiltinTemplateRecordId("dropin_test")

	writeTemplateFile(t, dir, "dropin_test.json", minimalTemplate("dropin_test", "Drop-in"))
	if err := services.SyncBuiltinTemplates(app, dir); err != nil {
		t.Fatalf("sync: %v", err)
	}
	rec, err := app.FindRecordById(util.Coll.Templates, dropinID)
	if err != nil {
		t.Fatalf("drop-in template was not created: %v", err)
	}
	if got := rec.GetString(util.Fields.Template.Name); got != "Drop-in" {
		t.Errorf("expected name 'Drop-in', got %q", got)
	}

	// A re-run with a changed file updates the same row, as a restart would.
	writeTemplateFile(t, dir, "dropin_test.json", minimalTemplate("dropin_test", "Drop-in v2"))
	if err := services.SyncBuiltinTemplates(app, dir); err != nil {
		t.Fatalf("sync: %v", err)
	}
	rec, err = app.FindRecordById(util.Coll.Templates, dropinID)
	if err != nil {
		t.Fatalf("drop-in template vanished on update: %v", err)
	}
	if got := rec.GetString(util.Fields.Template.Name); got != "Drop-in v2" {
		t.Errorf("expected updated name 'Drop-in v2', got %q", got)
	}

	// A drop-in file sharing an embedded id overrides the embedded entry.
	wifiID := services.BuiltinTemplateRecordId("wifi_access")
	writeTemplateFile(t, dir, "wifi.json", minimalTemplate("wifi_access", "Custom Wi-Fi"))
	if err := services.SyncBuiltinTemplates(app, dir); err != nil {
		t.Fatalf("sync: %v", err)
	}
	rec, err = app.FindRecordById(util.Coll.Templates, wifiID)
	if err != nil {
		t.Fatalf("overridden template missing: %v", err)
	}
	if got := rec.GetString(util.Fields.Template.Name); got != "Custom Wi-Fi" {
		t.Errorf("expected override name 'Custom Wi-Fi', got %q", got)
	}

	// With the folder empty again, the drop-in row is removed and the embedded
	// entry wins back its row.
	if err := services.SyncBuiltinTemplates(app, t.TempDir()); err != nil {
		t.Fatalf("sync: %v", err)
	}
	if _, err := app.FindRecordById(util.Coll.Templates, dropinID); err == nil {
		t.Error("drop-in template should be deleted once its file is gone")
	}
	rec, err = app.FindRecordById(util.Coll.Templates, wifiID)
	if err != nil {
		t.Fatalf("embedded template missing after override removal: %v", err)
	}
	if got := rec.GetString(util.Fields.Template.Name); got != "Wi-Fi access" {
		t.Errorf("expected embedded name restored, got %q", got)
	}
}

func TestBuiltinTemplatesReferencedSurvivesRemoval(t *testing.T) {
	baseURL, app := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	dir := t.TempDir()
	writeTemplateFile(t, dir, "referenced.json", minimalTemplate("referenced_test", "Referenced"))
	if err := services.SyncBuiltinTemplates(app, dir); err != nil {
		t.Fatalf("sync: %v", err)
	}
	builtinID := services.BuiltinTemplateRecordId("referenced_test")

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("Failed to create random user: %v", err)
	}
	wsID := activeWorkspaceOf(t, api, userID, token)
	identityID, _ := newIdentity(t, baseURL, token, "tpl-ref", userID, wsID)
	_, requestID := setupRequest(t, baseURL, token, userID, wsID, identityID, map[string]any{
		util.Fields.Request.Template: builtinID,
	})

	if err := services.SyncBuiltinTemplates(app, t.TempDir()); err != nil {
		t.Fatalf("sync: %v", err)
	}
	if _, err := app.FindRecordById(util.Coll.Templates, builtinID); err != nil {
		t.Fatal("built-in template referenced by a request must survive removal from the catalogue")
	}

	// Once nothing references it, the next sync sweeps it away.
	request, err := app.FindRecordById(util.Coll.Requests, requestID)
	if err != nil {
		t.Fatalf("request lookup: %v", err)
	}
	if err := app.Delete(request); err != nil {
		t.Fatalf("request delete: %v", err)
	}
	if err := services.SyncBuiltinTemplates(app, t.TempDir()); err != nil {
		t.Fatalf("sync: %v", err)
	}
	if _, err := app.FindRecordById(util.Coll.Templates, builtinID); err == nil {
		t.Error("unreferenced removed template should be deleted")
	}
}
