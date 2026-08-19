package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Splits every share-related read rule by auth state: a signed-in caller sees only
// their own workspace, an anonymous one only rows reachable from an active link.
// Those anonymous branches are still a bypass; 000030 and 000035 remove them.
func init() {
	migrations.Register(func(app core.App) error {
		linksCol, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}
		linkRule := "(@request.auth.id != '' && workspace = @request.auth.activeWorkspace && user = @request.auth.id) || (@request.auth.id = '' && status = 'active')"
		linksCol.ListRule = types.Pointer(linkRule)
		linksCol.ViewRule = types.Pointer(linkRule)
		if err := app.Save(linksCol); err != nil {
			return err
		}

		requestsCol, err := app.FindCollectionByNameOrId("requests")
		if err != nil {
			return err
		}
		requestRule := "(@request.auth.id != '' && workspace = @request.auth.activeWorkspace && user = @request.auth.id) || (@request.auth.id = '' && status = 'pending')"
		requestsCol.ListRule = types.Pointer(requestRule)
		requestsCol.ViewRule = types.Pointer(requestRule)
		if err := app.Save(requestsCol); err != nil {
			return err
		}

		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}
		recordsViewRule := "(" + legacyWorkspaceSelfOnly(util.ScopeRecordRead) + ") || (@request.auth.id = '' && ((@collection.links.records.id ?= id && @collection.links.status = 'active') || (@collection.links.sections.records.id ?= id && @collection.links.status = 'active')))"
		recordsCol.ListRule = types.Pointer(recordsViewRule)
		recordsCol.ViewRule = types.Pointer(recordsViewRule)
		if err := app.Save(recordsCol); err != nil {
			return err
		}

		sectionsCol, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err != nil {
			return err
		}
		sectionsViewRule := "(" + legacyWorkspaceSelfOnly(util.ScopeSectionRead) + ") || (@request.auth.id = '' && @collection.links.sections.id ?= id && @collection.links.status = 'active')"
		sectionsCol.ListRule = types.Pointer(sectionsViewRule)
		sectionsCol.ViewRule = types.Pointer(sectionsViewRule)
		if err := app.Save(sectionsCol); err != nil {
			return err
		}

		return nil
	}, func(app core.App) error {
		linksCol, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err == nil {
			linksCol.ListRule = types.Pointer("status = 'active'")
			linksCol.ViewRule = types.Pointer("status = 'active'")
			_ = app.Save(linksCol)
		}

		requestsCol, err := app.FindCollectionByNameOrId("requests")
		if err == nil {
			requestsCol.ListRule = types.Pointer("status = 'pending'")
			requestsCol.ViewRule = types.Pointer("status = 'pending'")
			_ = app.Save(requestsCol)
		}

		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err == nil {
			recordsViewRule := legacyWorkspaceSelfOnly(util.ScopeRecordRead) + " || (@collection.links.records.id ?= id && @collection.links.status = 'active') || (@collection.links.sections.records.id ?= id && @collection.links.status = 'active')"
			recordsCol.ListRule = types.Pointer(recordsViewRule)
			recordsCol.ViewRule = types.Pointer(recordsViewRule)
			_ = app.Save(recordsCol)
		}

		sectionsCol, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err == nil {
			sectionsViewRule := legacyWorkspaceSelfOnly(util.ScopeSectionRead) + " || (@collection.links.sections.id ?= id && @collection.links.status = 'active')"
			sectionsCol.ListRule = types.Pointer(sectionsViewRule)
			sectionsCol.ViewRule = types.Pointer(sectionsViewRule)
			_ = app.Save(sectionsCol)
		}

		return nil
	})
}
