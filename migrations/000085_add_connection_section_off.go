package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds connections.sectionOff: the owner switched the tool's own section off
// and kept it. Before, switching it off cleared the tool's vault access, which
// also cut it off from the sections the owner had added; a connection left
// that way has its section switched off.
func init() {
	migrations.Register(func(app core.App) error {
		f := util.Fields.Connection
		connections, err := app.FindCollectionByNameOrId(util.Coll.Connections)
		if err != nil {
			return err
		}
		if connections.Fields.GetByName(f.SectionOff) != nil {
			return nil
		}
		connections.Fields.Add(&core.BoolField{Name: f.SectionOff})
		if err := app.Save(connections); err != nil {
			return err
		}
		rows, err := app.FindRecordsByFilter(util.Coll.Connections,
			f.Section+" != '' && "+f.VaultAccess+" = ''", "", 0, 0)
		if err != nil {
			return err
		}
		for _, conn := range rows {
			conn.Set(f.SectionOff, true)
			if err := app.Save(conn); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		return nil
	})
}
