package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Removes the personal/business split: there are just workspaces now.
//
// The update rule loses its `type:isset = false` guard along with the column —
// a rule referencing a field that no longer exists is rejected outright, so the
// two must move together.
func init() {
	migrations.Register(func(app core.App) error {
		workspaces, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return err
		}

		spec, ok := util.AccessSpecFor(util.Coll.Workspaces, util.ActionUpdate)
		if ok {
			workspaces.UpdateRule = types.Pointer(spec.Rule())
		}
		workspaces.Fields.RemoveByName("type")

		return app.Save(workspaces)
	}, func(app core.App) error {
		workspaces, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return nil
		}
		workspaces.Fields.Add(&core.SelectField{
			Name:      "type",
			Values:    []string{"personal", "business"},
			Required:  true,
			MaxSelect: 1,
		})
		return app.Save(workspaces)
	})
}
