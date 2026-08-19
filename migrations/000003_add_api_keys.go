package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds the apiKeys collection. Keys are self-service and never updatable (rotate by
// delete + create), and no rule here accepts apiKey auth, so a key cannot mint keys.
func init() {
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}

		workspaces, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return err
		}

		apiKeys := core.NewBaseCollection(util.Coll.ApiKeys)
		apiKeys.Fields.Add(
			&core.TextField{
				Name:     util.Fields.ApiKey.Token,
				Required: false,
			},
			&core.TextField{
				Name:     util.Fields.ApiKey.Label,
				Required: true,
				Min:      1,
				Max:      100,
			},
			&core.RelationField{
				Name:          util.Fields.ApiKey.User,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.RelationField{
				Name:          util.Fields.ApiKey.Workspace,
				CollectionId:  workspaces.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.SelectField{
				Name:      util.Fields.ApiKey.Scopes,
				Required:  false,
				MaxSelect: len(util.AllScopes),
				Values:    util.AllScopes,
			},
			&core.AutodateField{
				Name:     util.Fields.ApiKey.LastUsedAt,
				OnCreate: true,
			},
			&core.AutodateField{
				Name:     util.Fields.ApiKey.Created,
				OnCreate: true,
			},
			&core.AutodateField{
				Name:     util.Fields.ApiKey.Updated,
				OnCreate: true,
				OnUpdate: true,
			},
		)

		apiKeys.AddIndex("idxApiKeyToken", true, util.Fields.ApiKey.Token, "")

		apiKeys.ListRule = types.Pointer(legacyUserSelfOnly())
		apiKeys.ViewRule = types.Pointer(legacyUserSelfOnly())
		apiKeys.DeleteRule = types.Pointer(legacyUserSelfOnly())
		apiKeys.CreateRule = types.Pointer(legacyWorkspaceAdminSelfOnly("", util.Fields.ApiKey.Workspace))
		apiKeys.UpdateRule = nil

		if err := app.Save(apiKeys); err != nil {
			return err
		}

		return nil
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId(util.Coll.ApiKeys)
		if err != nil {
			return nil
		}
		return app.Delete(col)
	})
}
