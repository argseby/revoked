package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Parenthesizes the workspaces update rule. PocketBase renders a filter into one SQL
// string where AND binds tighter than OR, so 000002's `users || apiKeys && type-not-set`
// guarded only the API-key branch: any workspace admin could PATCH `type` and escape
// the workspace and member limits, which are enforced only at create time.
func init() {
	migrations.Register(func(app core.App) error {
		workspaces, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return err
		}
		workspaces.UpdateRule = types.Pointer(
			"(" + legacyWorkspaceAnyAdmin(util.ScopeWorkspacesUpdate, "id") + ") && " + util.WorkspaceTypeImmutable,
		)
		return app.Save(workspaces)
	}, func(app core.App) error {
		workspaces, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return nil
		}
		workspaces.UpdateRule = types.Pointer(
			legacyWorkspaceAnyAdmin(util.ScopeWorkspacesUpdate, "id") + " && " + util.WorkspaceTypeImmutable,
		)
		return app.Save(workspaces)
	})
}
