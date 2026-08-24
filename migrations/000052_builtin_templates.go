package migrations

import (
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Prepares the templates collection for the built-in catalogue that
// services.SyncBuiltinTemplates writes at startup: a built-in template is a row
// with an empty workspace, so the relation becomes optional, a description
// column is added, and the read rules admit any authenticated caller to the
// workspace-less rows. The write rules are untouched — none of their branches
// can match an empty workspace, so built-ins stay read-only through the API.
func init() {
	// The 000010 read rule with the built-in branch appended. Frozen as a
	// literal, like every rule at and after 000040.
	const readRule = "(@request.auth.collectionName = 'users' && workspace = @request.auth.activeWorkspace && @collection.workspaceMembers.workspace ?= workspace && @collection.workspaceMembers.user ?= @request.auth.id) || (@request.auth.collectionName = 'apiKeys' && workspace = @request.auth.workspace.id && @request.auth.scopes ~ 'template:read') || (@request.auth.id != '' && workspace = '')"

	migrations.Register(func(app core.App) error {
		templates, err := app.FindCollectionByNameOrId(util.Coll.Templates)
		if err != nil {
			return err
		}

		if ws, ok := templates.Fields.GetByName(util.Fields.Template.Workspace).(*core.RelationField); ok {
			ws.Required = false
		}

		if templates.Fields.GetByName(util.Fields.Template.Description) == nil {
			templates.Fields.Add(&core.TextField{
				Name: util.Fields.Template.Description,
				Max:  util.MaxTemplateDescriptionLength,
			})
		}

		templates.ListRule = types.Pointer(readRule)
		templates.ViewRule = types.Pointer(readRule)

		return app.Save(templates)
	}, func(app core.App) error {
		templates, err := app.FindCollectionByNameOrId(util.Coll.Templates)
		if err != nil {
			return nil
		}

		builtins, err := app.FindAllRecords(util.Coll.Templates, dbx.NewExp("workspace = ''"))
		if err == nil {
			for _, rec := range builtins {
				_ = app.Delete(rec)
			}
		}

		if ws, ok := templates.Fields.GetByName(util.Fields.Template.Workspace).(*core.RelationField); ok {
			ws.Required = true
		}
		templates.Fields.RemoveByName(util.Fields.Template.Description)

		templates.ListRule = types.Pointer(legacyWorkspaceAnyMember("template:read"))
		templates.ViewRule = types.Pointer(legacyWorkspaceAnyMember("template:read"))

		return app.Save(templates)
	})
}
