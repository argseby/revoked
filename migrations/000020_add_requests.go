package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds requests (public data-collection endpoints gated by identity, password,
// expiry and max-responses), requestResponses (one row per submission) and
// handshakes (per-identity token exchange). All three collections stay owner-only;
// public traffic goes through the submission route, which enforces the gates.
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
		identities, err := app.FindCollectionByNameOrId(util.Coll.Identities)
		if err != nil {
			return err
		}
		linksCol, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}

		requests := core.NewBaseCollection(util.Coll.Requests)
		requests.Fields.Add(
			&core.TextField{
				Name:     util.Fields.Request.Slug,
				Required: true,
				Min:      6,
				Max:      100,
				Pattern:  util.SlugPattern,
			},
			&core.TextField{
				Name:     util.Fields.Request.Label,
				Required: true,
				Min:      1,
				Max:      100,
			},
			&core.SelectField{
				Name:      util.Fields.Request.Status,
				Required:  true,
				Values:    util.RequestStatuses,
				MaxSelect: 1,
			},
			&core.RelationField{
				Name:         util.Fields.Request.Identity,
				CollectionId: identities.Id,
				Required:     true,
				MaxSelect:    1,
			},
			// Stored as a bcrypt hash; stripped from responses in the hooks layer.
			&core.TextField{
				Name:     util.Fields.Request.Password,
				Required: false,
				Max:      200,
			},
			&core.DateField{Name: util.Fields.Request.ExpiresAt},
			&core.NumberField{
				Name: util.Fields.Request.MaxResponses,
				Min:  types.Pointer(0.0),
			},
			&core.NumberField{
				Name: util.Fields.Request.ResponseCount,
				Min:  types.Pointer(0.0),
			},
			&core.TextField{
				Name: util.Fields.Request.Identifier,
				Max:  200,
			},
			&core.URLField{Name: util.Fields.Request.CallbackUrl},
			&core.BoolField{Name: util.Fields.Request.RequireHandshake},
			&core.RelationField{
				Name:         util.Fields.Request.User,
				CollectionId: users.Id,
				Required:     true,
				MaxSelect:    1,
			},
			&core.RelationField{
				Name:         util.Fields.Request.Workspace,
				CollectionId: workspaces.Id,
				Required:     true,
				MaxSelect:    1,
			},
			&core.AutodateField{Name: util.Fields.Request.Created, OnCreate: true},
			&core.AutodateField{Name: util.Fields.Request.Updated, OnCreate: true, OnUpdate: true},
		)
		requests.AddIndex("idxRequestsSlug", true, util.Fields.Request.Slug, "")

		requests.ListRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRequestRead))
		requests.ViewRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRequestRead))
		requests.CreateRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRequestCreate))
		requests.UpdateRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRequestUpdate))
		requests.DeleteRule = types.Pointer(legacyWorkspaceSelfOnly(util.ScopeRequestDelete))

		if err := app.Save(requests); err != nil {
			return err
		}

		responses := core.NewBaseCollection(util.Coll.RequestResponses)
		responses.Fields.Add(
			&core.RelationField{
				Name:          util.Fields.RequestResponse.Request,
				CollectionId:  requests.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.RelationField{
				Name:         util.Fields.RequestResponse.Identity,
				CollectionId: identities.Id,
				MaxSelect:    1,
			},
			&core.TextField{Name: util.Fields.RequestResponse.Identifier, Max: 200},
			&core.JSONField{Name: util.Fields.RequestResponse.Data},
			&core.TextField{Name: util.Fields.RequestResponse.SenderName, Max: 200},
			&core.RelationField{
				Name:         util.Fields.RequestResponse.Workspace,
				CollectionId: workspaces.Id,
				Required:     true,
				MaxSelect:    1,
			},
			&core.AutodateField{Name: util.Fields.RequestResponse.Created, OnCreate: true},
		)

		ownerRead := "@request.auth.collectionName = 'users' && @collection.requests.id ?= request && @collection.requests.user ?= @request.auth.id"
		responses.ListRule = types.Pointer(ownerRead)
		responses.ViewRule = types.Pointer(ownerRead)
		responses.CreateRule = nil
		responses.UpdateRule = nil
		responses.DeleteRule = nil

		if err := app.Save(responses); err != nil {
			return err
		}

		handshakes := core.NewBaseCollection(util.Coll.Handshakes)
		handshakes.Fields.Add(
			&core.RelationField{
				Name:          util.Fields.Handshake.Request,
				CollectionId:  requests.Id,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.RelationField{
				Name:          util.Fields.Handshake.Link,
				CollectionId:  linksCol.Id,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.RelationField{
				Name:          util.Fields.Handshake.Identity,
				CollectionId:  identities.Id,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.TextField{
				Name:     util.Fields.Handshake.TokenHash,
				Required: true,
				Hidden:   true,
				Min:      32,
				Max:      200,
			},
			&core.RelationField{
				Name:         util.Fields.Handshake.Workspace,
				CollectionId: workspaces.Id,
				Required:     true,
				MaxSelect:    1,
			},
			&core.AutodateField{Name: util.Fields.Handshake.Created, OnCreate: true},
		)

		handshakes.ListRule = types.Pointer(legacyWorkspaceAnyMember(""))
		handshakes.ViewRule = types.Pointer(legacyWorkspaceAnyMember(""))
		handshakes.CreateRule = nil
		handshakes.UpdateRule = nil
		handshakes.DeleteRule = nil

		return app.Save(handshakes)
	}, func(app core.App) error {
		for _, name := range []string{
			util.Coll.Handshakes,
			util.Coll.RequestResponses,
			util.Coll.Requests,
		} {
			col, err := app.FindCollectionByNameOrId(name)
			if err == nil {
				_ = app.Delete(col)
			}
		}
		return nil
	})
}
