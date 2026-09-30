package migrations

import (
	"time"

	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Brings a database that ran the first version of 000057 in line with the
// current one: a connection no longer has a store for the tool's notes, and it
// expires. On a database created with the current 000057 this changes nothing.
//
// A connection that existed before expiry gets a full term from now rather
// than none, which would make it the one connection that never lapses.
func init() {
	migrations.Register(func(app core.App) error {
		connections, err := app.FindCollectionByNameOrId(util.Coll.Connections)
		if err != nil {
			return err
		}
		changed := false
		if connections.Fields.GetByName("storage") != nil {
			connections.Fields.RemoveByName("storage")
			changed = true
		}
		if connections.Fields.GetByName(util.Fields.Connection.ExpiresAt) == nil {
			connections.Fields.Add(&core.DateField{Name: util.Fields.Connection.ExpiresAt})
			changed = true
		}
		if changed {
			if err := app.Save(connections); err != nil {
				return err
			}
		}

		open, err := app.FindRecordsByFilter(util.Coll.Connections,
			util.Fields.Connection.ExpiresAt+" = ''", "", 0, 0)
		if err != nil {
			return err
		}
		for _, conn := range open {
			conn.Set(util.Fields.Connection.ExpiresAt, time.Now().Add(util.ConnectionTTL))
			if err := app.Save(conn); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		return nil
	})
}
