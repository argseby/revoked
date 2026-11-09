package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Lets a workspace choose who sees a new item of each area that names no
// audience of its own (VISIBILITY.md §4.4, phase 5). Empty keeps every area's
// built-in default: private for the vault, shares and requests, the
// workspace for templates, contacts and attestations. A default never grants
// anything by itself, and never changes existing items.
func init() {
	migrations.Register(func(app core.App) error {
		ws, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return err
		}
		if ws.Fields.GetByName(util.Fields.Workspace.DefaultAudience) == nil {
			ws.Fields.Add(&core.JSONField{Name: util.Fields.Workspace.DefaultAudience, MaxSize: 2000})
		}
		return app.Save(ws)
	}, func(app core.App) error {
		ws, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return err
		}
		ws.Fields.RemoveByName(util.Fields.Workspace.DefaultAudience)
		return app.Save(ws)
	})
}
