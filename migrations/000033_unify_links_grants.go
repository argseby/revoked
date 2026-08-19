package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Makes `links` the single grant object, absorbing what `requestResponses` did: a link
// is now minted either manually or by approving a request (`request`, the `grants`
// key→record map, and `data` as a snapshot fallback for answers with no vault record).
// `user` becomes optional so an account-less guest can still produce a link.
func init() {
	migrations.Register(func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}
		requests, err := app.FindCollectionByNameOrId(util.Coll.Requests)
		if err != nil {
			return err
		}

		links.Fields.Add(
			&core.RelationField{
				Name:          util.Fields.Link.Request,
				CollectionId:  requests.Id,
				MaxSelect:     1,
				CascadeDelete: false,
			},
			&core.JSONField{Name: util.Fields.Link.Grants},
			&core.JSONField{Name: util.Fields.Link.Data},
			&core.TextField{Name: util.Fields.Link.SenderName, Max: 200},
			&core.TextField{Name: util.Fields.Link.Identifier, Max: 200},
		)

		if f := links.Fields.GetByName(util.Fields.Link.User); f != nil {
			if rel, ok := f.(*core.RelationField); ok {
				rel.Required = false
				rel.MinSelect = 0
			}
		}

		return app.Save(links)
	}, func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return nil
		}
		links.Fields.RemoveByName(util.Fields.Link.Request)
		links.Fields.RemoveByName(util.Fields.Link.Grants)
		links.Fields.RemoveByName(util.Fields.Link.Data)
		links.Fields.RemoveByName(util.Fields.Link.SenderName)
		links.Fields.RemoveByName(util.Fields.Link.Identifier)

		if f := links.Fields.GetByName(util.Fields.Link.User); f != nil {
			if rel, ok := f.(*core.RelationField); ok {
				rel.Required = true
				rel.MinSelect = 1
			}
		}

		return app.Save(links)
	})
}
