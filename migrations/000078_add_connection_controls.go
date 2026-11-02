package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Lets a person pause or end what they connected.
//
// signIns gains its status (empty on older rows, which reads as active), a
// generation that moves with every disconnect so nothing issued before it comes
// back to life, and the version of the subject the service knows them by.
// connections gains paused. links gains heldPaused: paused because its tool or
// service was, so activating that again restores only those links and never one
// the owner paused themselves.
func init() {
	migrations.Register(func(app core.App) error {
		signIns, err := app.FindCollectionByNameOrId(util.Coll.SignIns)
		if err != nil {
			return err
		}
		s := util.Fields.SignIn
		if signIns.Fields.GetByName(s.Status) == nil {
			signIns.Fields.Add(
				&core.SelectField{
					Name:      s.Status,
					MaxSelect: 1,
					Values:    []string{util.StatusActive, util.StatusPaused, util.StatusDisconnected},
				},
				&core.NumberField{Name: s.Generation, OnlyInt: true},
				&core.NumberField{Name: s.SubjectVersion, OnlyInt: true},
				&core.DateField{Name: s.DisconnectedAt},
				&core.BoolField{Name: s.NewIdOnReturn},
			)
			if err := app.Save(signIns); err != nil {
				return err
			}
		}

		connections, err := app.FindCollectionByNameOrId(util.Coll.Connections)
		if err != nil {
			return err
		}
		if connections.Fields.GetByName(util.Fields.Connection.Paused) == nil {
			connections.Fields.Add(&core.BoolField{Name: util.Fields.Connection.Paused})
			if err := app.Save(connections); err != nil {
				return err
			}
		}

		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}
		if links.Fields.GetByName(util.Fields.Link.HeldPaused) == nil {
			links.Fields.Add(&core.BoolField{Name: util.Fields.Link.HeldPaused})
			return app.Save(links)
		}
		return nil
	}, func(app core.App) error {
		return nil
	})
}
