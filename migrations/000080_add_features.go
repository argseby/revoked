package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds per-account feature choices: which parts of the app a person wants to
// see, kept on the account so every device agrees. An invite may carry a
// starting set, copied to the member's account on accept if it never chose.
//
// Null means "never chosen" and an empty list means "nothing but the vault",
// so the field is JSON rather than a select.
func init() {
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		if users.Fields.GetByName(util.Fields.User.Features) == nil {
			users.Fields.Add(&core.JSONField{Name: util.Fields.User.Features, MaxSize: 2000})
			if err := app.Save(users); err != nil {
				return err
			}
		}

		invites, err := app.FindCollectionByNameOrId(util.Coll.Invites)
		if err != nil {
			return err
		}
		if invites.Fields.GetByName(util.Fields.Invite.Features) == nil {
			invites.Fields.Add(&core.JSONField{Name: util.Fields.Invite.Features, MaxSize: 2000})
			if err := app.Save(invites); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		users.Fields.RemoveByName(util.Fields.User.Features)
		if err := app.Save(users); err != nil {
			return err
		}
		invites, err := app.FindCollectionByNameOrId(util.Coll.Invites)
		if err != nil {
			return err
		}
		invites.Fields.RemoveByName(util.Fields.Invite.Features)
		return app.Save(invites)
	})
}
