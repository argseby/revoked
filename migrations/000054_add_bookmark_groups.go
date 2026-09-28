package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds bookmark groups: named lists a user files their bookmarks into, like
// playlists. A bookmark may sit in any number of them, or none.
//
// Membership lives on the bookmark (`groups`), so deleting a group only unlinks
// it and every bookmark survives. Groups are as personal as the bookmarks they
// hold, and a bookmark may only name its owner's groups (hooks/bookmarks.go).
func init() {
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}

		groups := core.NewBaseCollection(util.Coll.BookmarkGroups)
		groups.Fields.Add(
			&core.RelationField{
				Name:          util.Fields.BookmarkGroup.User,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.TextField{Name: util.Fields.BookmarkGroup.Name, Required: true, Min: 1, Max: 100},
			&core.AutodateField{Name: util.Fields.BookmarkGroup.Created, OnCreate: true},
			&core.AutodateField{Name: util.Fields.BookmarkGroup.Updated, OnCreate: true, OnUpdate: true},
		)

		owner := util.AccessSpec{Kind: util.AccessUserSelf}
		update := util.AccessSpec{Kind: util.AccessUserSelf, Extra: util.OwnerImmutable}
		groups.ListRule = types.Pointer(owner.Rule())
		groups.ViewRule = types.Pointer(owner.Rule())
		groups.CreateRule = types.Pointer(owner.Rule())
		groups.UpdateRule = types.Pointer(update.Rule())
		groups.DeleteRule = types.Pointer(owner.Rule())
		if err := app.Save(groups); err != nil {
			return err
		}

		bookmarks, err := app.FindCollectionByNameOrId(util.Coll.Bookmarks)
		if err != nil {
			return err
		}
		bookmarks.Fields.Add(&core.RelationField{
			Name:         util.Fields.Bookmark.Groups,
			CollectionId: groups.Id,
			MaxSelect:    100,
		})
		return app.Save(bookmarks)
	}, func(app core.App) error {
		if bookmarks, err := app.FindCollectionByNameOrId(util.Coll.Bookmarks); err == nil {
			bookmarks.Fields.RemoveByName(util.Fields.Bookmark.Groups)
			if err := app.Save(bookmarks); err != nil {
				return err
			}
		}
		groups, err := app.FindCollectionByNameOrId(util.Coll.BookmarkGroups)
		if err != nil {
			return nil
		}
		return app.Delete(groups)
	})
}
