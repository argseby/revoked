package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Switches off PocketBase's "login from a new location" mail for users. It
// keys a location by IP and user agent, so a phone changing networks counts
// as new; it tells the reader to change a password these accounts do not
// have; and a sign-in waits on it for up to 15 seconds when the mail server
// is unreachable. Superusers keep theirs.
func init() {
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		users.AuthAlert.Enabled = false
		return app.Save(users)
	}, func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return nil
		}
		users.AuthAlert.Enabled = true
		return app.Save(users)
	})
}
