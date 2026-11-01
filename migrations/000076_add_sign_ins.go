package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds signIns: the services a person approved a sign-in at, one row per
// person and service. It holds which scopes the service has learned, never
// their values, the link its shared entries live in, if any, and where the
// name the person chose for that service comes from.
//
// Personal rather than workspace data, because the identifier a service gets
// derives from the account. Written by the consent route alone, so nobody can
// tidy away a service they signed in to; no API key reaches it.
func init() {
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}

		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return err
		}

		f := util.Fields.SignIn
		signIns := core.NewBaseCollection(util.Coll.SignIns)
		signIns.Fields.Add(
			&core.RelationField{Name: f.User, CollectionId: users.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.TextField{Name: f.ClientId, Required: true, Max: 255},
			&core.JSONField{Name: f.Scopes, MaxSize: 4 << 10},
			// Cleared, not cascaded: the sign-in happened whatever became of the link.
			&core.RelationField{Name: f.Link, CollectionId: links.Id, MaxSelect: 1},
			// One or neither, and cleared with what it points at. The name is read
			// from here each time, so a change reaches the service.
			&core.RelationField{Name: f.NameRecord, CollectionId: records.Id, MaxSelect: 1},
			&core.RelationField{Name: f.NameIdentity, CollectionId: identities.Id, MaxSelect: 1},
			&core.DateField{Name: f.LastSignInAt, Required: true},
			&core.AutodateField{Name: f.Created, OnCreate: true},
			&core.AutodateField{Name: f.Updated, OnCreate: true, OnUpdate: true},
		)
		signIns.AddIndex("idxSignInsClient", true, f.User+", "+f.ClientId, "")
		owner := util.AccessSpec{Kind: util.AccessUserSelf}
		signIns.ListRule = types.Pointer(owner.Rule())
		signIns.ViewRule = types.Pointer(owner.Rule())
		return app.Save(signIns)
	}, func(app core.App) error {
		signIns, err := app.FindCollectionByNameOrId(util.Coll.SignIns)
		if err != nil {
			return nil
		}
		return app.Delete(signIns)
	})
}
