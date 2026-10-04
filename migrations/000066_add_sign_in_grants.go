package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds links.signInClient — the origin of the service a link was given to
// when its owner signed in there with Revoked and agreed to share entries.
// Such a link is read by that service with a token (grantTokenHash), like a
// grant on another server, and is otherwise an ordinary link its owner sees,
// pauses and revokes. One link per owner and service: signing in again
// updates it.
func init() {
	migrations.Register(func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}
		if links.Fields.GetByName(util.Fields.Link.SignInClient) != nil {
			return nil
		}
		links.Fields.Add(&core.TextField{Name: util.Fields.Link.SignInClient, Max: 255})
		links.AddIndex("idxLinksSignInClient", false,
			util.Fields.Link.User+", "+util.Fields.Link.SignInClient, "")
		return app.Save(links)
	}, func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return nil
		}
		links.RemoveIndex("idxLinksSignInClient")
		links.Fields.RemoveByName(util.Fields.Link.SignInClient)
		return app.Save(links)
	})
}
