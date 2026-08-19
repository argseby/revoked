package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Reverts 000024's `status = 'active' || (owner)` links rule, which let any anonymous
// client list and read every active link. Public access must go through
// /api/public/links/{slug}, which enforces password, expiry, max views and handshake.
func init() {
	migrations.Register(func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}
		links.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeLinkRead))
		links.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeLinkRead))
		return app.Save(links)
	}, func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return nil
		}
		rule := "status = 'active' || (workspace = @request.auth.activeWorkspace && user = @request.auth.id)"
		links.ListRule = types.Pointer(rule)
		links.ViewRule = types.Pointer(rule)
		return app.Save(links)
	})
}
