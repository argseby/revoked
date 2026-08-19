package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds password, expiry, max-views, view-count, identity and handshake fields to
// links, and revokes the anonymous read paths 000009 opened on links, records and
// sections: public access must go through /api/public/links/:slug, which enforces
// every gate server-side.
func init() {
	migrations.Register(func(app core.App) error {
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return err
		}

		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}

		if links.Fields.GetByName(util.Fields.Link.Password) == nil {
			// Bcrypt hash, not Hidden: pocketbase's form upsert silently discards
			// writes to hidden fields for non-superusers. The links hook strips it.
			links.Fields.Add(&core.TextField{
				Name:     util.Fields.Link.Password,
				Required: false,
				Max:      200,
			})
		}
		if links.Fields.GetByName(util.Fields.Link.ExpiresAt) == nil {
			links.Fields.Add(&core.DateField{
				Name:     util.Fields.Link.ExpiresAt,
				Required: false,
			})
		}
		if links.Fields.GetByName(util.Fields.Link.MaxViews) == nil {
			links.Fields.Add(&core.NumberField{
				Name:     util.Fields.Link.MaxViews,
				Required: false,
				Min:      types.Pointer(0.0),
			})
		}
		if links.Fields.GetByName(util.Fields.Link.ViewCount) == nil {
			links.Fields.Add(&core.NumberField{
				Name:     util.Fields.Link.ViewCount,
				Required: false,
				Min:      types.Pointer(0.0),
			})
		}
		if links.Fields.GetByName(util.Fields.Link.Identity) == nil {
			links.Fields.Add(&core.RelationField{
				Name:         util.Fields.Link.Identity,
				CollectionId: identities.Id,
				Required:     false,
				MaxSelect:    1,
			})
		}
		if links.Fields.GetByName(util.Fields.Link.RequireHandshake) == nil {
			links.Fields.Add(&core.BoolField{
				Name: util.Fields.Link.RequireHandshake,
			})
		}

		links.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeLinkRead))
		links.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeLinkRead))
		links.CreateRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeLinkCreate))
		links.UpdateRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeLinkUpdate))
		links.DeleteRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeLinkDelete))

		if err := app.Save(links); err != nil {
			return err
		}

		recordsCol, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err == nil {
			recordsCol.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRecordRead))
			recordsCol.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRecordRead))
			if err := app.Save(recordsCol); err != nil {
				return err
			}
		}

		sectionsCol, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err == nil {
			sectionsCol.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeSectionRead))
			sectionsCol.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeSectionRead))
			if err := app.Save(sectionsCol); err != nil {
				return err
			}
		}

		return nil
	}, func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return nil
		}

		for _, name := range []string{
			util.Fields.Link.Password,
			util.Fields.Link.ExpiresAt,
			util.Fields.Link.MaxViews,
			util.Fields.Link.ViewCount,
			util.Fields.Link.Identity,
			util.Fields.Link.RequireHandshake,
		} {
			links.Fields.RemoveByName(name)
		}

		links.ListRule = types.Pointer("status = 'active'")
		links.ViewRule = types.Pointer("status = 'active'")
		return app.Save(links)
	})
}
