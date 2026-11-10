package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"revoked/util"
)

func init() {
	migrations.Register(func(app core.App) error {
		col, err := app.FindCollectionByNameOrId(util.Coll.Bookmarks)
		if err != nil {
			return err
		}
		col.Fields.Add(&core.TextField{Name: util.Fields.Bookmark.SealedKey, Max: 128},
			&core.NumberField{Name: util.Fields.Bookmark.KeyEpoch, OnlyInt: true})
		return app.Save(col)
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId(util.Coll.Bookmarks)
		if err != nil {
			return err
		}
		col.Fields.RemoveByName(util.Fields.Bookmark.SealedKey)
		col.Fields.RemoveByName(util.Fields.Bookmark.KeyEpoch)
		return app.Save(col)
	})
}
