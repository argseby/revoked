package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds the templates collection: readable by the whole workspace, writable only by
// workspace admins.
func init() {
	migrations.Register(func(app core.App) error {
		workspaces, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return err
		}

		templates := core.NewBaseCollection(util.Coll.Templates)
		templates.Fields.Add(
			&core.TextField{
				Name:     util.Fields.Template.Name,
				Required: true,
				Min:      1,
				Max:      100,
			},
			&core.JSONField{
				Name:     util.Fields.Template.Schema,
				Required: true,
			},
			&core.RelationField{
				Name:         util.Fields.Template.Workspace,
				CollectionId: workspaces.Id,
				Required:     true,
				MaxSelect:    1,
			},
			&core.AutodateField{Name: util.Fields.Template.Created, OnCreate: true},
			&core.AutodateField{Name: util.Fields.Template.Updated, OnCreate: true, OnUpdate: true},
		)

		templates.ListRule = types.Pointer(legacyWorkspaceAnyMember(util.ScopeTemplateRead))
		templates.ViewRule = types.Pointer(legacyWorkspaceAnyMember(util.ScopeTemplateRead))

		templates.CreateRule = types.Pointer(legacyWorkspaceAnyAdmin(util.ScopeTemplateCreate, "workspace"))
		templates.UpdateRule = types.Pointer(legacyWorkspaceAnyAdmin(util.ScopeTemplateUpdate, "workspace"))
		templates.DeleteRule = types.Pointer(legacyWorkspaceAnyAdmin(util.ScopeTemplateDelete, "workspace"))

		if err := app.Save(templates); err != nil {
			return err
		}

		return nil
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId(util.Coll.Templates)
		if err != nil {
			return nil
		}

		if err := app.Delete(col); err != nil {
			return err
		}

		return nil
	})
}
