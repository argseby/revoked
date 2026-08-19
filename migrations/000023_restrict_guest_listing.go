package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Drops the anonymous branch from the records/sections list rules so a guest can no
// longer scan the whole vault. The view rules keep it, so expanding a specific share
// still resolves individual rows.
func init() {
	migrations.Register(func(app core.App) error {
		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}
		recordsCol.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRecordRead))
		recordsViewRule := "(" + legacyWorkspaceSelfOnly(util.ScopeRecordRead) + ") || (@request.auth.id = '' && ((@collection.links.records.id ?= id && @collection.links.status = 'active') || (@collection.links.sections.records.id ?= id && @collection.links.status = 'active')))"
		recordsCol.ViewRule = types.Pointer(recordsViewRule)

		if err := app.Save(recordsCol); err != nil {
			return err
		}

		sectionsCol, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err != nil {
			return err
		}
		sectionsCol.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeSectionRead))
		sectionsViewRule := "(" + legacyWorkspaceSelfOnly(util.ScopeSectionRead) + ") || (@request.auth.id = '' && @collection.links.sections.id ?= id && @collection.links.status = 'active')"
		sectionsCol.ViewRule = types.Pointer(sectionsViewRule)

		if err := app.Save(sectionsCol); err != nil {
			return err
		}

		return nil
	}, func(app core.App) error {
		// Restores the 000021 state.
		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err == nil {
			recordsViewRule := "(" + legacyWorkspaceSelfOnly(util.ScopeRecordRead) + ") || (@request.auth.id = '' && ((@collection.links.records.id ?= id && @collection.links.status = 'active') || (@collection.links.sections.records.id ?= id && @collection.links.status = 'active')))"
			recordsCol.ListRule = types.Pointer(recordsViewRule)
			recordsCol.ViewRule = types.Pointer(recordsViewRule)
			_ = app.Save(recordsCol)
		}

		sectionsCol, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err == nil {
			sectionsViewRule := "(" + legacyWorkspaceSelfOnly(util.ScopeSectionRead) + ") || (@request.auth.id = '' && @collection.links.sections.id ?= id && @collection.links.status = 'active')"
			sectionsCol.ListRule = types.Pointer(sectionsViewRule)
			sectionsCol.ViewRule = types.Pointer(sectionsViewRule)
			_ = app.Save(sectionsCol)
		}

		return nil
	})
}
