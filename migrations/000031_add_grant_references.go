package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Lets a response reference the responder's own vault records instead of only a frozen
// copy, so editing a record updates the grant and revoking stops it resolving. The
// responder also gains read access to their own grants, to review and revoke them.
func init() {
	migrations.Register(func(app core.App) error {
		responses, err := app.FindCollectionByNameOrId(util.Coll.RequestResponses)
		if err != nil {
			return err
		}
		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}

		responses.Fields.Add(
			&core.RelationField{
				Name:         util.Fields.RequestResponse.Records,
				CollectionId: records.Id,
				MaxSelect:    500,
			},
			&core.RelationField{
				Name:         util.Fields.RequestResponse.Responder,
				CollectionId: users.Id,
				MaxSelect:    1,
			},
			&core.SelectField{
				Name:      util.Fields.RequestResponse.Status,
				Values:    []string{util.StatusActive, util.StatusRevoked},
				MaxSelect: 1,
			},
		)

		ownerRead := "@request.auth.collectionName = 'users' && @collection.requests.id ?= request && @collection.requests.user ?= @request.auth.id"
		responderRead := "@request.auth.collectionName = 'users' && responder ?= @request.auth.id"
		rule := "(" + ownerRead + ") || (" + responderRead + ")"
		responses.ListRule = types.Pointer(rule)
		responses.ViewRule = types.Pointer(rule)

		return app.Save(responses)
	}, func(app core.App) error {
		responses, err := app.FindCollectionByNameOrId(util.Coll.RequestResponses)
		if err != nil {
			return nil
		}
		responses.Fields.RemoveByName(util.Fields.RequestResponse.Records)
		responses.Fields.RemoveByName(util.Fields.RequestResponse.Responder)
		responses.Fields.RemoveByName(util.Fields.RequestResponse.Status)

		ownerRead := "@request.auth.collectionName = 'users' && @collection.requests.id ?= request && @collection.requests.user ?= @request.auth.id"
		responses.ListRule = types.Pointer(ownerRead)
		responses.ViewRule = types.Pointer(ownerRead)
		return app.Save(responses)
	})
}
