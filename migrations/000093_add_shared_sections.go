package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Lets a section's owner share it with the workspace's members. The collection
// rules stay self-only: members read shared sections through /api/shared/vault,
// where membership and permissions are checked in Go (ACCESS.md).
func init() {
	migrations.Register(func(app core.App) error {
		sections, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err != nil {
			return err
		}
		if sections.Fields.GetByName(util.Fields.Section.Shared) == nil {
			sections.Fields.Add(&core.BoolField{Name: util.Fields.Section.Shared})
		}
		return app.Save(sections)
	}, func(app core.App) error {
		sections, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err != nil {
			return err
		}
		sections.Fields.RemoveByName(util.Fields.Section.Shared)
		return app.Save(sections)
	})
}
