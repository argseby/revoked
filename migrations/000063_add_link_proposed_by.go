package migrations

import (
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds links.proposedBy — the origin of the tool whose proposal a link came
// from. The connection relation is cleared when the owner disconnects the
// tool; this stays, so the link still says it was not made in the app. Links
// that still have their connection are filled in from it; one whose tool is
// already gone cannot be.
func init() {
	migrations.Register(func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}
		if links.Fields.GetByName(util.Fields.Link.ProposedBy) != nil {
			return nil
		}
		links.Fields.Add(&core.TextField{Name: util.Fields.Link.ProposedBy, Max: 255})
		if err := app.Save(links); err != nil {
			return err
		}
		_, err = app.DB().NewQuery(
			"UPDATE {{" + util.Coll.Links + "}} SET [[" + util.Fields.Link.ProposedBy + "]] = COALESCE((" +
				"SELECT c.[[" + util.Fields.Connection.ClientId + "]] FROM {{" + util.Coll.Connections + "}} c " +
				"WHERE c.id = {{" + util.Coll.Links + "}}.[[" + util.Fields.Link.Connection + "]]), '') " +
				"WHERE [[" + util.Fields.Link.Connection + "]] != {:none}").
			Bind(dbx.Params{"none": ""}).Execute()
		return err
	}, func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return nil
		}
		links.Fields.RemoveByName(util.Fields.Link.ProposedBy)
		return app.Save(links)
	})
}
