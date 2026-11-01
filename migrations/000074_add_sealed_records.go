package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds end-to-end encrypted records; E2EE.md is the design.
//
// A sealed record's `value` stays empty, so a path nobody taught about sealing
// finds nothing to serve. The ciphertext gets its own field for that reason,
// and an explicit Max because PocketBase otherwise caps text at 5000: the
// longest value pads to 4096 bytes, which is about 5500 once base64-encoded.
//
// The three new collections keep every rule nil (superuser-only). Clients reach
// them through /api/sealed/*, which checks access itself and makes a record and
// its key material land in one transaction. rotationDue lives here rather than
// on `workspaces`, where a workspace admin could clear it through the API.
func init() {
	migrations.Register(func(app core.App) error {
		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		workspaces, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return err
		}

		r := util.Fields.Record
		records.Fields.Add(
			&core.BoolField{Name: r.Sealed},
			&core.TextField{Name: r.SealedValue, Max: 8192},
			&core.NumberField{Name: r.SealedVersion, OnlyInt: true},
			&core.NumberField{Name: r.KeyEpoch, OnlyInt: true},
			&core.TextField{Name: r.KeyWrap, Max: 256},
		)
		if err := app.Save(records); err != nil {
			return err
		}

		d := util.Fields.DeviceKey
		devices := core.NewBaseCollection(util.Coll.DeviceKeys)
		devices.Fields.Add(
			&core.RelationField{
				Name:          d.User,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.NumberField{Name: d.Seq, Required: true, OnlyInt: true},
			&core.SelectField{
				Name:      d.Action,
				Required:  true,
				MaxSelect: 1,
				Values:    []string{util.SealedActionAdd, util.SealedActionRemove},
			},
			&core.TextField{Name: d.Kind, Max: 16},
			&core.TextField{Name: d.Label, Max: 255},
			&core.TextField{Name: d.HpkePublicKey, Max: 128},
			&core.TextField{Name: d.SigningPublicKey, Max: 128},
			&core.NumberField{Name: d.TargetSeq, OnlyInt: true},
			&core.TextField{Name: d.PreviousHash, Max: 64},
			&core.NumberField{Name: d.SignerSeq, Required: true, OnlyInt: true},
			&core.TextField{Name: d.Signature, Required: true, Max: 128},
			&core.AutodateField{Name: d.Created, OnCreate: true},
		)
		devices.AddIndex("idxDeviceKeysUserSeq", true, d.User+", "+d.Seq, "")
		if err := app.Save(devices); err != nil {
			return err
		}

		e := util.Fields.WorkspaceKeyEpoch
		epochs := core.NewBaseCollection(util.Coll.WorkspaceKeyEpochs)
		epochs.Fields.Add(
			&core.RelationField{
				Name:          e.Workspace,
				CollectionId:  workspaces.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.NumberField{Name: e.Epoch, Required: true, OnlyInt: true},
			&core.TextField{Name: e.PriorWrap, Max: 256},
			&core.BoolField{Name: e.RotationDue},
			&core.RelationField{
				Name:         e.CreatedBy,
				CollectionId: users.Id,
				MaxSelect:    1,
			},
			&core.AutodateField{Name: e.Created, OnCreate: true},
		)
		epochs.AddIndex("idxWorkspaceKeyEpochs", true, e.Workspace+", "+e.Epoch, "")
		if err := app.Save(epochs); err != nil {
			return err
		}

		w := util.Fields.WorkspaceKeyWrap
		wraps := core.NewBaseCollection(util.Coll.WorkspaceKeyWraps)
		wraps.Fields.Add(
			&core.RelationField{
				Name:          w.Workspace,
				CollectionId:  workspaces.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.NumberField{Name: w.Epoch, Required: true, OnlyInt: true},
			&core.RelationField{
				Name:          w.User,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.NumberField{Name: w.DeviceSeq, Required: true, OnlyInt: true},
			&core.TextField{Name: w.Wrap, Required: true, Max: 512},
			&core.NumberField{Name: w.SignerSeq, Required: true, OnlyInt: true},
			&core.TextField{Name: w.Signature, Required: true, Max: 128},
			&core.AutodateField{Name: w.Created, OnCreate: true},
		)
		wraps.AddIndex("idxWorkspaceKeyWraps", true,
			w.Workspace+", "+w.Epoch+", "+w.User+", "+w.DeviceSeq, "")
		wraps.AddIndex("idxWorkspaceKeyWrapsUser", false, w.User, "")
		return app.Save(wraps)
	}, func(app core.App) error {
		for _, name := range []string{
			util.Coll.WorkspaceKeyWraps,
			util.Coll.WorkspaceKeyEpochs,
			util.Coll.DeviceKeys,
		} {
			if coll, err := app.FindCollectionByNameOrId(name); err == nil {
				if err := app.Delete(coll); err != nil {
					return err
				}
			}
		}
		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}
		r := util.Fields.Record
		for _, name := range []string{r.Sealed, r.SealedValue, r.SealedVersion, r.KeyEpoch, r.KeyWrap} {
			records.Fields.RemoveByName(name)
		}
		return app.Save(records)
	})
}
