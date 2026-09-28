package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds bookmarks: share links a person was sent and wants to keep, stored on
// their account so they can reopen them later.
//
// A bookmark is a pointer, not a grant. It stores where the link lives and its
// slug, never the data behind it, and the server never follows it — opening one
// is the same public share view as opening the link itself, with every gate and
// view cap still applying. The origin may name another server, so it is kept as
// the host[:port] a deep link carries and nothing here fetches it.
func init() {
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}

		bookmarks := core.NewBaseCollection(util.Coll.Bookmarks)
		bookmarks.Fields.Add(
			&core.RelationField{
				Name:          util.Fields.Bookmark.User,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			// Empty means the server the account lives on.
			&core.TextField{Name: util.Fields.Bookmark.Origin, Max: 255, Pattern: `^[A-Za-z0-9.\-\[\]:]*$`},
			&core.TextField{Name: util.Fields.Bookmark.Slug, Required: true, Min: 1, Max: 100, Pattern: `^[A-Za-z0-9_-]+$`},
			&core.TextField{Name: util.Fields.Bookmark.Label, Max: 200},
			&core.AutodateField{Name: util.Fields.Bookmark.Created, OnCreate: true},
			&core.AutodateField{Name: util.Fields.Bookmark.Updated, OnCreate: true, OnUpdate: true},
		)
		bookmarks.AddIndex("idxBookmarksUserLink", true, "user, origin, slug", "")

		owner := util.AccessSpec{Kind: util.AccessUserSelf}
		update := util.AccessSpec{Kind: util.AccessUserSelf, Extra: util.OwnerImmutable}
		bookmarks.ListRule = types.Pointer(owner.Rule())
		bookmarks.ViewRule = types.Pointer(owner.Rule())
		bookmarks.CreateRule = types.Pointer(owner.Rule())
		bookmarks.UpdateRule = types.Pointer(update.Rule())
		bookmarks.DeleteRule = types.Pointer(owner.Rule())

		return app.Save(bookmarks)
	}, func(app core.App) error {
		bookmarks, err := app.FindCollectionByNameOrId(util.Coll.Bookmarks)
		if err != nil {
			return nil
		}
		return app.Delete(bookmarks)
	})
}
