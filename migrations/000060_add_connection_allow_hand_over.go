package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds connections.allowHandOver — whether the owner lets a tool receive
// links at all — to a database whose connections collection was created
// before the field existed. A connection that already holds a handed-over
// link keeps receiving: that was the owner's choice under the old rule, where
// every connection could.
func init() {
	migrations.Register(func(app core.App) error {
		connections, err := app.FindCollectionByNameOrId(util.Coll.Connections)
		if err != nil {
			return err
		}
		if connections.Fields.GetByName(util.Fields.Connection.AllowHandOver) != nil {
			return nil
		}
		connections.Fields.Add(&core.BoolField{Name: util.Fields.Connection.AllowHandOver})
		if err := app.Save(connections); err != nil {
			return err
		}

		handed, err := app.FindRecordsByFilter(util.Coll.Links,
			util.Fields.Link.HandedOver+" = true && "+util.Fields.Link.Connection+" != ''", "", 0, 0)
		if err != nil {
			return err
		}
		seen := map[string]bool{}
		for _, link := range handed {
			id := link.GetString(util.Fields.Link.Connection)
			if seen[id] {
				continue
			}
			seen[id] = true
			conn, err := app.FindRecordById(util.Coll.Connections, id)
			if err != nil {
				continue
			}
			conn.Set(util.Fields.Connection.AllowHandOver, true)
			if err := app.Save(conn); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		return nil
	})
}
