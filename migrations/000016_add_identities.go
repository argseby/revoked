package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds the identities collection: a named keypair plus server-issued certificate,
// attachable to links and requests. Only the certificate is ever exposed publicly.
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

		identities := core.NewBaseCollection(util.Coll.Identities)
		identities.Fields.Add(
			&core.TextField{
				Name:     util.Fields.Identity.Name,
				Required: true,
				Min:      1,
				Max:      100,
			},
			&core.TextField{
				Name:     util.Fields.Identity.Certificate,
				Required: true,
				Min:      20,
				Max:      20000,
			},
			// Not Hidden: pocketbase's form upsert silently discards writes to hidden
			// fields for non-superuser auth, so the owner could never rotate their key.
			// The stripPrivateKeyFromResponses hook keeps it out of responses instead.
			&core.TextField{
				Name:     util.Fields.Identity.PrivateKey,
				Required: false,
				Max:      20000,
			},
			&core.TextField{
				Name:     util.Fields.Identity.Fingerprint,
				Required: false,
				Max:      200,
			},
			&core.RelationField{
				Name:          util.Fields.Identity.User,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.RelationField{
				Name:          util.Fields.Identity.Workspace,
				CollectionId:  workspaces.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.AutodateField{Name: util.Fields.Identity.Created, OnCreate: true},
			&core.AutodateField{Name: util.Fields.Identity.Updated, OnCreate: true, OnUpdate: true},
		)
		identities.AddIndex("idxIdentityFingerprint", true, util.Fields.Identity.Fingerprint, "")

		identities.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeIdentityRead))
		identities.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeIdentityRead))
		identities.CreateRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeIdentityCreate))
		identities.UpdateRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeIdentityUpdate))
		identities.DeleteRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeIdentityDelete))

		return app.Save(identities)
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return nil
		}
		return app.Delete(col)
	})
}
