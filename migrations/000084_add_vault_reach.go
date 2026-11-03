package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Gives keys and connected tools one access model: scopes from the permission
// catalogue, plus a reach into the vault (ACCESS.md).
//
//   - connections gain scopes, vaultAccess, their own section and the sections
//     the owner added. allowRevoke and allowHandOver fold into scopes, exactly
//     as narrow as they were: ending what the tool proposed, and receiving
//     links. allowVaultRead stays: it is the whole-vault reach.
//   - apiKeys gain vaultAccess and the sections chosen for them.
//   - records gain writtenBy, the key or connection that wrote one, and its
//     name at the time, which outlives a disconnect.
func init() {
	migrations.Register(func(app core.App) error {
		sections, err := app.FindCollectionByNameOrId(util.Coll.Sections)
		if err != nil {
			return err
		}

		connections, err := app.FindCollectionByNameOrId(util.Coll.Connections)
		if err != nil {
			return err
		}
		cf := util.Fields.Connection
		if connections.Fields.GetByName(cf.Scopes) == nil {
			connections.Fields.Add(
				&core.JSONField{Name: cf.Scopes, MaxSize: 4000},
				&core.SelectField{Name: cf.VaultAccess, Values: util.VaultAccessValues, MaxSelect: 1},
				&core.RelationField{Name: cf.Section, CollectionId: sections.Id, MaxSelect: 1},
				&core.RelationField{Name: cf.Sections, CollectionId: sections.Id, MaxSelect: 50},
			)
			if err := app.Save(connections); err != nil {
				return err
			}
		}
		if connections.Fields.GetByName("allowRevoke") != nil {
			rows, err := app.FindAllRecords(util.Coll.Connections)
			if err != nil {
				return err
			}
			for _, conn := range rows {
				scopes := []string{}
				if conn.GetBool("allowRevoke") {
					scopes = append(scopes, util.ConnectionEndScopes...)
				}
				if conn.GetBool("allowHandOver") {
					scopes = append(scopes, util.ConnectionHandOverScope)
				}
				conn.Set(cf.Scopes, scopes)
				if conn.GetBool(cf.AllowVaultRead) {
					conn.Set(cf.VaultAccess, util.VaultAccessRead)
				}
				if err := app.Save(conn); err != nil {
					return err
				}
			}
			connections.Fields.RemoveByName("allowRevoke")
			connections.Fields.RemoveByName("allowHandOver")
			if err := app.Save(connections); err != nil {
				return err
			}
		}

		apiKeys, err := app.FindCollectionByNameOrId(util.Coll.ApiKeys)
		if err != nil {
			return err
		}
		if apiKeys.Fields.GetByName(util.Fields.ApiKey.Sections) == nil {
			apiKeys.Fields.Add(
				&core.SelectField{Name: util.Fields.ApiKey.VaultAccess, Values: util.VaultAccessValues, MaxSelect: 1},
				&core.RelationField{Name: util.Fields.ApiKey.Sections, CollectionId: sections.Id, MaxSelect: 50},
			)
			if err := app.Save(apiKeys); err != nil {
				return err
			}
		}

		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}
		if records.Fields.GetByName(util.Fields.Record.WrittenBy) == nil {
			records.Fields.Add(
				&core.TextField{Name: util.Fields.Record.WrittenBy, Max: 32},
				&core.TextField{Name: util.Fields.Record.WrittenByName, Max: 80},
			)
			if err := app.Save(records); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		return nil
	})
}
