package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Re-applies the rules that drifted from util/rules.go in 000024. Rules are snapshots
// in the database, so editing a builder there does not change a deployed collection —
// only a migration does. 000024's records/sections view rules let any caller fetch a
// row by id via any active link, bypassing that link's password and handshake gates;
// its requests rule also dropped the API-key branch WorkspaceSelfOnly provides.
func init() {
	migrations.Register(func(app core.App) error {
		requests, err := app.FindCollectionByNameOrId(util.Coll.Requests)
		if err != nil {
			return err
		}
		requests.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRequestRead))
		requests.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRequestRead))
		if err := app.Save(requests); err != nil {
			return err
		}

		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}
		records.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRecordRead))
		records.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRecordRead))
		if err := app.Save(records); err != nil {
			return err
		}

		sections, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err != nil {
			return err
		}
		sections.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeSectionRead))
		sections.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeSectionRead))
		return app.Save(sections)
	}, func(app core.App) error {
		// Restores the 000024 state.
		requests, err := app.FindCollectionByNameOrId(util.Coll.Requests)
		if err == nil {
			rule := "status = 'pending' || (workspace = @request.auth.activeWorkspace && user = @request.auth.id)"
			requests.ListRule = types.Pointer(rule)
			requests.ViewRule = types.Pointer(rule)
			_ = app.Save(requests)
		}

		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err == nil {
			records.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRecordRead))
			viewRule := "(" + legacyWorkspaceSelfOnly(util.ScopeRecordRead) + ") || (@collection.links.records.id ?= id && @collection.links.status = 'active') || (@collection.links.sections.records.id ?= id && @collection.links.status = 'active')"
			records.ViewRule = types.Pointer(viewRule)
			_ = app.Save(records)
		}

		sections, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err == nil {
			sections.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeSectionRead))
			viewRule := "(" + legacyWorkspaceSelfOnly(util.ScopeSectionRead) + ") || (@collection.links.sections.id ?= id && @collection.links.status = 'active')"
			sections.ViewRule = types.Pointer(viewRule)
			_ = app.Save(sections)
		}

		return nil
	})
}
