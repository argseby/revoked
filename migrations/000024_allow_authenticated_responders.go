package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Re-opens links and requests to any session and lets any session view records and
// sections attached to an active link, so an authenticated responder can read a share.
// This reintroduces the bypass that 000030 and 000035 then close for good.
func init() {
	migrations.Register(func(app core.App) error {
		linksCol, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}
		linkRule := "status = 'active' || (workspace = @request.auth.activeWorkspace && user = @request.auth.id)"
		linksCol.ListRule = types.Pointer(linkRule)
		linksCol.ViewRule = types.Pointer(linkRule)
		if err := app.Save(linksCol); err != nil {
			return err
		}

		requestsCol, err := app.FindCollectionByNameOrId("requests")
		if err != nil {
			return err
		}
		requestRule := "status = 'pending' || (workspace = @request.auth.activeWorkspace && user = @request.auth.id)"
		requestsCol.ListRule = types.Pointer(requestRule)
		requestsCol.ViewRule = types.Pointer(requestRule)
		if err := app.Save(requestsCol); err != nil {
			return err
		}

		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}
		recordsCol.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRecordRead))
		recordsViewRule := "(" + legacyWorkspaceSelfOnly(util.ScopeRecordRead) + ") || (@collection.links.records.id ?= id && @collection.links.status = 'active') || (@collection.links.sections.records.id ?= id && @collection.links.status = 'active')"
		recordsCol.ViewRule = types.Pointer(recordsViewRule)
		if err := app.Save(recordsCol); err != nil {
			return err
		}

		sectionsCol, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err != nil {
			return err
		}
		sectionsCol.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeSectionRead))
		sectionsViewRule := "(" + legacyWorkspaceSelfOnly(util.ScopeSectionRead) + ") || (@collection.links.sections.id ?= id && @collection.links.status = 'active')"
		sectionsCol.ViewRule = types.Pointer(sectionsViewRule)
		if err := app.Save(sectionsCol); err != nil {
			return err
		}

		return nil
	}, func(app core.App) error {
		// Restores the 000023 state.
		linksCol, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err == nil {
			linkRule := "(@request.auth.id != '' && workspace = @request.auth.activeWorkspace && user = @request.auth.id) || (@request.auth.id = '' && status = 'active')"
			linksCol.ListRule = types.Pointer(linkRule)
			linksCol.ViewRule = types.Pointer(linkRule)
			_ = app.Save(linksCol)
		}

		requestsCol, err := app.FindCollectionByNameOrId("requests")
		if err == nil {
			requestRule := "(@request.auth.id != '' && workspace = @request.auth.activeWorkspace && user = @request.auth.id) || (@request.auth.id = '' && status = 'pending')"
			requestsCol.ListRule = types.Pointer(requestRule)
			requestsCol.ViewRule = types.Pointer(requestRule)
			_ = app.Save(requestsCol)
		}

		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err == nil {
			recordsCol.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRecordRead))
			recordsViewRule := "(" + legacyWorkspaceSelfOnly(util.ScopeRecordRead) + ") || (@request.auth.id = '' && ((@collection.links.records.id ?= id && @collection.links.status = 'active') || (@collection.links.sections.records.id ?= id && @collection.links.status = 'active')))"
			recordsCol.ViewRule = types.Pointer(recordsViewRule)
			_ = app.Save(recordsCol)
		}

		sectionsCol, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err == nil {
			sectionsCol.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeSectionRead))
			sectionsViewRule := "(" + legacyWorkspaceSelfOnly(util.ScopeSectionRead) + ") || (@request.auth.id = '' && @collection.links.sections.id ?= id && @collection.links.status = 'active')"
			sectionsCol.ViewRule = types.Pointer(sectionsViewRule)
			_ = app.Save(sectionsCol)
		}

		return nil
	})
}
