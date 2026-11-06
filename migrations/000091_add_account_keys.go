package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Gives each person a key of their own, wrapped only to their own devices, for
// their identities' private keys. Under the workspace key, those would open for
// every member the workspace key is one day handed to (design/e2ee-sharing.md
// §2.6). sealedKeyScope says which key an identity's sealedKey is under; empty
// is the phase 1 form, under the workspace key.
//
// Same shape as workspaceKeyEpochs and workspaceKeyWraps, and the same nil rules:
// clients reach them only through /api/sealed/*.
func init() {
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}

		e := util.Fields.AccountKeyEpoch
		epochs := core.NewBaseCollection(util.Coll.AccountKeyEpochs)
		epochs.Fields.Add(
			&core.RelationField{
				Name:          e.User,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.NumberField{Name: e.Epoch, Required: true, OnlyInt: true},
			&core.TextField{Name: e.PriorWrap, Max: 256},
			&core.BoolField{Name: e.RotationDue},
			&core.AutodateField{Name: e.Created, OnCreate: true},
		)
		epochs.AddIndex("idxAccountKeyEpochs", true, e.User+", "+e.Epoch, "")
		if err := app.Save(epochs); err != nil {
			return err
		}

		w := util.Fields.AccountKeyWrap
		wraps := core.NewBaseCollection(util.Coll.AccountKeyWraps)
		wraps.Fields.Add(
			&core.RelationField{
				Name:          w.User,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.NumberField{Name: w.Epoch, Required: true, OnlyInt: true},
			&core.NumberField{Name: w.DeviceSeq, Required: true, OnlyInt: true},
			&core.TextField{Name: w.Wrap, Required: true, Max: 512},
			&core.NumberField{Name: w.SignerSeq, Required: true, OnlyInt: true},
			&core.NumberField{Name: w.ChainSeq, OnlyInt: true},
			&core.TextField{Name: w.Signature, Required: true, Max: 128},
			&core.AutodateField{Name: w.Created, OnCreate: true},
		)
		wraps.AddIndex("idxAccountKeyWraps", true, w.User+", "+w.Epoch+", "+w.DeviceSeq, "")
		if err := app.Save(wraps); err != nil {
			return err
		}

		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return err
		}
		if identities.Fields.GetByName(util.Fields.Identity.SealedKeyScope) == nil {
			identities.Fields.Add(&core.SelectField{
				Name:      util.Fields.Identity.SealedKeyScope,
				MaxSelect: 1,
				Values:    []string{util.SealedKeyScopeAccount},
			})
		}
		return app.Save(identities)
	}, func(app core.App) error {
		for _, name := range []string{util.Coll.AccountKeyWraps, util.Coll.AccountKeyEpochs} {
			if coll, err := app.FindCollectionByNameOrId(name); err == nil {
				if err := app.Delete(coll); err != nil {
					return err
				}
			}
		}
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return err
		}
		identities.Fields.RemoveByName(util.Fields.Identity.SealedKeyScope)
		return app.Save(identities)
	})
}
