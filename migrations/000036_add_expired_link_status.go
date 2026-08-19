package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Allows "expired" in links.status. 000009 created the field without it, so
// refreshLinkStatus's save failed validation every time (with the error discarded),
// the column never reflected expiry, and link_expired re-fired on every later hit.
func init() {
	migrations.Register(func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}
		links.Fields.Add(&core.SelectField{
			Name:      util.Fields.Link.Status,
			Required:  true,
			Values:    util.LinkStatuses,
			MaxSelect: 1,
		})
		return app.Save(links)
	}, func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return nil
		}
		links.Fields.Add(&core.SelectField{
			Name:      util.Fields.Link.Status,
			Required:  true,
			Values:    []string{util.StatusActive, util.StatusPaused, util.StatusRevoked},
			MaxSelect: 1,
		})
		return app.Save(links)
	})
}
