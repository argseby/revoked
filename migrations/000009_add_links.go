package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds the links collection: a shareable bundle of records and sections. The public
// read rules opened here (any active link, and any record or section attached to one)
// are bypasses later closed by 000030 and 000035.
func init() {
	migrations.Register(func(app core.App) error {

		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}

		workspaces, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return err
		}

		sectionsCol, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err != nil {
			return err
		}

		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}

		links := core.NewBaseCollection(util.Coll.Links)
		links.Fields.Add(
			&core.TextField{
				Name:     util.Fields.Link.Slug,
				Required: true,
				Min:      6,
				Max:      100,
				Pattern:  "^[a-z0-9_-]+$",
			},
			&core.TextField{
				Name:     util.Fields.Link.Label,
				Required: true,
				Min:      1,
				Max:      100,
			},
			&core.SelectField{
				Name:      util.Fields.Link.Status,
				Required:  true,
				Values:    []string{"active", "paused", "revoked"},
				MaxSelect: 1,
			},
			&core.RelationField{
				Name:         util.Fields.Link.Sections,
				CollectionId: sectionsCol.Id,
				MaxSelect:    100,
			},
			&core.RelationField{
				Name:         util.Fields.Link.Records,
				CollectionId: recordsCol.Id,
				MaxSelect:    100,
			},

			&core.AutodateField{Name: util.Fields.Link.Created, OnCreate: true},
			&core.AutodateField{Name: util.Fields.Link.Updated, OnCreate: true, OnUpdate: true},
			&core.RelationField{
				Name:         util.Fields.Link.User,
				CollectionId: users.Id,
				Required:     true,
				MaxSelect:    1,
			},
			&core.RelationField{
				Name:         util.Fields.Link.Workspace,
				CollectionId: workspaces.Id,
				Required:     true,
				MaxSelect:    1,
			},
		)
		links.AddIndex("idxLinksSlug", true, util.Fields.Link.Slug, "")

		links.ListRule = types.Pointer("status = 'active'")
		links.ViewRule = types.Pointer("status = 'active'")

		links.CreateRule = types.Pointer(legacyWorkspaceSelfOnly(""))
		links.UpdateRule = types.Pointer(legacyWorkspaceSelfOnly(""))
		links.DeleteRule = types.Pointer(legacyWorkspaceSelfOnly(""))

		if err := app.Save(links); err != nil {
			return err
		}

		recordsViewRule := legacyWorkspaceSelfOnly(util.ScopeRecordRead) + " || (@collection.links.records ?= id && @collection.links.status = 'active') || (@collection.links.sections.records ?= id && @collection.links.status = 'active')"
		recordsCol.ViewRule = types.Pointer(recordsViewRule)
		recordsCol.ListRule = types.Pointer(recordsViewRule)
		if err := app.Save(recordsCol); err != nil {
			return err
		}

		sectionsViewRule := legacyWorkspaceSelfOnly(util.ScopeSectionRead) + " || (@collection.links.sections ?= id && @collection.links.status = 'active')"
		sectionsCol.ViewRule = types.Pointer(sectionsViewRule)
		sectionsCol.ListRule = types.Pointer(sectionsViewRule)
		if err := app.Save(sectionsCol); err != nil {
			return err
		}

		return nil

	}, func(app core.App) error {
		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err == nil {
			recordsCol.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRecordRead))
			recordsCol.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRecordRead))
			_ = app.Save(recordsCol)
		}

		sectionsCol, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err == nil {
			sectionsCol.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeSectionRead))
			sectionsCol.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeSectionRead))
			_ = app.Save(sectionsCol)
		}

		col, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return nil
		}

		if err := app.Delete(col); err != nil {
			return err
		}

		return nil
	})
}
