package migrations

import (
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Removes the account's own name. One name per account meant that changing it
// for one service changed it for all of them; a person now picks a name per
// service, from their identities or their vault.
//
// A name someone already set moves into their vault, so they can still pick it.
func init() {
	const accountName = "name"
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		if users.Fields.GetByName(accountName) == nil {
			return nil
		}
		named, err := app.FindRecordsByFilter(util.Coll.Users, accountName+" != ''", "", 0, 0)
		if err != nil {
			return err
		}
		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}
		f := util.Fields.Record
		for _, user := range named {
			workspace := user.GetString(util.Fields.User.ActiveWorkspace)
			if workspace == "" {
				continue
			}
			// Under a key of its own if "name" is already theirs for something else.
			for _, key := range []string{"name", "account_name"} {
				taken, err := app.FindFirstRecordByFilter(util.Coll.Records,
					f.User+" = {:u} && "+f.Workspace+" = {:w} && "+f.Key+" = {:k}",
					dbx.Params{"u": user.Id, "w": workspace, "k": key})
				if err == nil && taken != nil {
					continue
				}
				rec := core.NewRecord(records)
				rec.Set(f.Key, key)
				rec.Set(f.Value, user.GetString(accountName))
				rec.Set(f.Label, "Name")
				rec.Set(f.Type, util.TypeText)
				rec.Set(f.Format, util.FormatDefault)
				rec.Set(f.User, user.Id)
				rec.Set(f.Workspace, workspace)
				if err := app.Save(rec); err != nil {
					return err
				}
				break
			}
		}
		users.Fields.RemoveByName(accountName)
		users.OAuth2.MappedFields.Name = ""
		return app.Save(users)
	}, func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		if users.Fields.GetByName(accountName) != nil {
			return nil
		}
		users.Fields.Add(&core.TextField{Name: accountName, Max: 255})
		return app.Save(users)
	})
}
