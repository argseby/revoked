package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds connected tools.
//
// A connection is a tool the owner connected from the app: it may propose
// shares, read the status of the links its proposals became, and receive the
// links the owner chose to hand it. It never reads the vault, and keeps
// nothing here: what it needs to remember lives on its own side. Two things
// are the owner's to allow per connection: receiving links at all, and
// revoking the links its proposals became — ending a share, never starting
// one. A connection expires unless the owner connects
// the tool again.
//
// connectionTokens holds one row per browser the tool was connected in: first
// a one-time code (bound to a PKCE challenge and the tool's return address),
// then, once exchanged, the hash of the bearer token. Nothing but server code
// reads either collection's secrets; neither is exposed through the
// collection API.
//
// links gains the connection a share was proposed by, the tool's own
// reference for it, and whether the owner handed the link to the tool.
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

		connections := core.NewBaseCollection(util.Coll.Connections)
		connections.Fields.Add(
			&core.RelationField{
				Name:          util.Fields.Connection.User,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.RelationField{
				Name:          util.Fields.Connection.Workspace,
				CollectionId:  workspaces.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			// The tool's origin: scheme, host and optional port, nothing else.
			&core.TextField{
				Name:     util.Fields.Connection.ClientId,
				Required: true,
				Max:      255,
				Pattern:  util.ConnectionOriginPattern,
			},
			// The name the tool gives itself — a claim, shown as one.
			&core.TextField{Name: util.Fields.Connection.ClientName, Max: 40},
			&core.BoolField{Name: util.Fields.Connection.AllowRevoke},
			&core.BoolField{Name: util.Fields.Connection.AllowHandOver},
			&core.DateField{Name: util.Fields.Connection.ExpiresAt},
			&core.DateField{Name: util.Fields.Connection.LastUsedAt},
			&core.AutodateField{Name: util.Fields.Connection.Created, OnCreate: true},
			&core.AutodateField{Name: util.Fields.Connection.Updated, OnCreate: true, OnUpdate: true},
		)
		connections.AddIndex("idxConnectionsClient", true, "user, workspace, clientId", "")

		// The owner sees and disconnects; everything else goes through the
		// connection routes, so create and update stay superuser-only.
		owner := util.UserSelfOnly() + " && workspace = @request.auth.activeWorkspace"
		connections.ListRule = types.Pointer(owner)
		connections.ViewRule = types.Pointer(owner)
		connections.DeleteRule = types.Pointer(owner)
		if err := app.Save(connections); err != nil {
			return err
		}

		tokens := core.NewBaseCollection(util.Coll.ConnectionTokens)
		tokens.Fields.Add(
			&core.RelationField{
				Name:          util.Fields.ConnectionToken.Connection,
				CollectionId:  connections.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.TextField{Name: util.Fields.ConnectionToken.CodeHash, Max: 64, Hidden: true},
			&core.TextField{Name: util.Fields.ConnectionToken.CodeChallenge, Max: 128, Hidden: true},
			&core.DateField{Name: util.Fields.ConnectionToken.CodeExpiresAt},
			&core.TextField{Name: util.Fields.ConnectionToken.RedirectUri, Max: 500},
			&core.TextField{Name: util.Fields.ConnectionToken.TokenHash, Max: 64, Hidden: true},
			&core.DateField{Name: util.Fields.ConnectionToken.LastUsedAt},
			&core.AutodateField{Name: util.Fields.ConnectionToken.Created, OnCreate: true},
		)
		tokens.AddIndex("idxConnectionTokensCode", false, "codeHash", "")
		tokens.AddIndex("idxConnectionTokensToken", false, "tokenHash", "")
		if err := app.Save(tokens); err != nil {
			return err
		}

		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}
		if links.Fields.GetByName(util.Fields.Link.Connection) == nil {
			links.Fields.Add(
				// Cleared, not cascaded, on disconnect: the owner's links outlive
				// the tool that proposed them.
				&core.RelationField{
					Name:         util.Fields.Link.Connection,
					CollectionId: connections.Id,
					MaxSelect:    1,
				},
				&core.TextField{Name: util.Fields.Link.Ref, Max: 80},
				&core.BoolField{Name: util.Fields.Link.HandedOver},
			)
			if err := app.Save(links); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		if links, err := app.FindCollectionByNameOrId(util.Coll.Links); err == nil {
			links.Fields.RemoveByName(util.Fields.Link.Connection)
			links.Fields.RemoveByName(util.Fields.Link.Ref)
			links.Fields.RemoveByName(util.Fields.Link.HandedOver)
			if err := app.Save(links); err != nil {
				return err
			}
		}
		for _, name := range []string{util.Coll.ConnectionTokens, util.Coll.Connections} {
			if c, err := app.FindCollectionByNameOrId(name); err == nil {
				if err := app.Delete(c); err != nil {
					return err
				}
			}
		}
		return nil
	})
}
