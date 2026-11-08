package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds an authenticator app as a second factor after the passkey. The secrets
// are hidden: no rule, filter or API response ever carries them, and they are
// only set through /api/2fa (and cleared by `revoked user reset-2fa`).
// totpEnabledAt is the readable trace that the account has one turned on.
func init() {
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		if users.Fields.GetByName(util.Fields.User.TotpSecret) == nil {
			users.Fields.Add(&core.TextField{Name: util.Fields.User.TotpSecret, Max: 64, Hidden: true})
		}
		if users.Fields.GetByName(util.Fields.User.TotpPending) == nil {
			users.Fields.Add(&core.TextField{Name: util.Fields.User.TotpPending, Max: 64, Hidden: true})
		}
		if users.Fields.GetByName(util.Fields.User.TotpEnabledAt) == nil {
			users.Fields.Add(&core.DateField{Name: util.Fields.User.TotpEnabledAt})
		}
		// The last accepted code's time step: a code is refused unless it is
		// newer, so none can be replayed inside its window.
		if users.Fields.GetByName(util.Fields.User.TotpLastStep) == nil {
			users.Fields.Add(&core.NumberField{Name: util.Fields.User.TotpLastStep, Hidden: true, OnlyInt: true})
		}
		return app.Save(users)
	}, func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		users.Fields.RemoveByName(util.Fields.User.TotpSecret)
		users.Fields.RemoveByName(util.Fields.User.TotpPending)
		users.Fields.RemoveByName(util.Fields.User.TotpEnabledAt)
		users.Fields.RemoveByName(util.Fields.User.TotpLastStep)
		return app.Save(users)
	})
}
