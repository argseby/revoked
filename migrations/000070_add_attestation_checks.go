package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds attestationChecks: one person asking another to show an attestation.
//
// A row is the asker's request — the kind of attestation, the attesters and
// claims wanted, a nonce the presentation must commit to — and, once the
// other person answered, the verdict on what they showed. The credential
// itself is never kept, only what was disclosed and whether it verified.
//
// Written by the check routes alone: creating one sets the nonce and the
// audience the server answers for, and answering one is atomic. The owner may
// read and remove their checks; no API key reaches them.
//
// The notification type list is widened for the asker's "it was shown".
func init() {
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return err
		}

		f := util.Fields.AttestationCheck
		checks := core.NewBaseCollection(util.Coll.AttestationChecks)
		checks.Fields.Add(
			&core.RelationField{Name: f.User, CollectionId: users.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			// Who asks, as the other person is shown it. Not required, and not
			// cascading: a check outlives the identity it was asked with.
			&core.RelationField{Name: f.Identity, CollectionId: identities.Id, MaxSelect: 1},
			&core.TextField{Name: f.Type, Max: 255},
			&core.JSONField{Name: f.Issuers, MaxSize: 8 << 10},
			&core.JSONField{Name: f.Claims, MaxSize: 8 << 10},
			&core.TextField{Name: f.Nonce, Required: true, Max: 128, Hidden: true},
			&core.TextField{Name: f.Audience, Required: true, Max: 255},
			&core.SelectField{
				Name:      f.Status,
				Required:  true,
				Values:    util.CheckStatuses,
				MaxSelect: 1,
			},
			&core.DateField{Name: f.ExpiresAt, Required: true},
			&core.JSONField{Name: f.Result, MaxSize: 64 << 10},
			&core.DateField{Name: f.AnsweredAt},
			&core.AutodateField{Name: f.Created, OnCreate: true},
			&core.AutodateField{Name: f.Updated, OnCreate: true, OnUpdate: true},
		)
		checks.AddIndex("idxAttestationChecksUser", false, f.User+", "+f.Created, "")
		owner := util.AccessSpec{Kind: util.AccessUserSelf}
		checks.ListRule = types.Pointer(owner.Rule())
		checks.ViewRule = types.Pointer(owner.Rule())
		checks.DeleteRule = types.Pointer(owner.Rule())
		if err := app.Save(checks); err != nil {
			return err
		}

		notifications, err := app.FindCollectionByNameOrId(util.Coll.Notifications)
		if err != nil {
			return err
		}
		if typeField, ok := notifications.Fields.GetByName(util.Fields.Notification.Type).(*core.SelectField); ok {
			typeField.Values = util.NotificationTypes
		}
		return app.Save(notifications)
	}, func(app core.App) error {
		checks, err := app.FindCollectionByNameOrId(util.Coll.AttestationChecks)
		if err != nil {
			return nil
		}
		return app.Delete(checks)
	})
}
