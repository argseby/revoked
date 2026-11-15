package tests

import (
	"net/http"
	"testing"

	"revoked/tests/testutils"
	"revoked/util"
)

// A schema stored as a bare list of fields saved without complaint, and every
// request built on it reached the responder with nothing to fill in.
func TestTemplateSchemaMustBeReadableByTheRequestPage(t *testing.T) {
	baseURL, _ := testutils.SetupTestApp(t)
	api := testutils.NewPBClient(t, baseURL)

	userID, token, err := testutils.CreateRandomUser(baseURL)
	if err != nil {
		t.Fatalf("CreateRandomUser: %v", err)
	}
	wsID := api.Get(util.Coll.Users, userID, token).Expect().Status(http.StatusOK).
		JSON().Object().Value(util.Fields.User.ActiveWorkspace).String().Raw()

	fields := []any{
		map[string]any{"key": "legal_name", "label": "Legal company name", "required": true},
		map[string]any{"key": "city", "label": "City"},
	}

	refused := func(t *testing.T, schema any) {
		api.T(t).Create(util.Coll.Templates, token, map[string]any{
			util.Fields.Template.Name:      "Onboarding",
			util.Fields.Template.Workspace: wsID,
			util.Fields.Template.Schema:    schema,
		}).Expect().Status(http.StatusBadRequest).JSON().Object().
			Value("data").Object().Value(util.Fields.Template.Schema).Object().
			Value("code").String().IsEqual(util.Errors.TemplateSchemaInvalid.ErrorCode)
	}

	t.Run("a bare list of fields is refused", func(t *testing.T) { refused(t, fields) })
	t.Run("records that are not a list are refused", func(t *testing.T) {
		refused(t, map[string]any{"records": map[string]any{"key": "city"}})
	})
	t.Run("a record without a key is refused", func(t *testing.T) {
		refused(t, map[string]any{"records": []any{map[string]any{"label": "City"}}})
	})
	t.Run("a section record without a key is refused", func(t *testing.T) {
		refused(t, map[string]any{"sections": []any{map[string]any{"key": "address", "records": []any{map[string]any{}}}}})
	})

	t.Run("an object schema reaches the responder with its fields", func(t *testing.T) {
		templateID := extractID(t, baseURL, util.Coll.Templates, token, map[string]any{
			util.Fields.Template.Name:      "Onboarding",
			util.Fields.Template.Workspace: wsID,
			util.Fields.Template.Schema:    map[string]any{"records": fields},
		})
		identityID, _ := newIdentity(t, baseURL, token, "Agency", userID, wsID)
		slug, _ := setupRequest(t, baseURL, token, userID, wsID, identityID, map[string]any{
			util.Fields.Request.Template: templateID,
		})
		records := testutils.NewPBClient(t, baseURL).E.GET("/api/public/requests/" + slug).
			Expect().Status(http.StatusOK).JSON().Object().
			Value("template").Object().Value("records").Array()
		records.Length().IsEqual(2)
		records.Value(0).Object().Value("key").String().IsEqual("legal_name")
	})

	t.Run("an update to a bare list is refused", func(t *testing.T) {
		templateID := extractID(t, baseURL, util.Coll.Templates, token, map[string]any{
			util.Fields.Template.Name:      "Onboarding",
			util.Fields.Template.Workspace: wsID,
			util.Fields.Template.Schema:    map[string]any{"records": fields},
		})
		api.T(t).Update(util.Coll.Templates, templateID, token, map[string]any{
			util.Fields.Template.Schema: fields,
		}).Expect().Status(http.StatusBadRequest)
	})
}
