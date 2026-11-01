package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Lets a grant be handed to a contact who has an account here.
//
// The tray for what someone was handed already exists: bookmarks. What it
// could not say is whether a slug is a share to read or a request to answer,
// because until now only shares arrived — so `kind` is added, with empty
// reading as a share so nothing saved before this needs rewriting. The unique
// index gains it too: link slugs and request slugs come from separate
// collections and may coincide, and without `kind` the second arrival would be
// refused as a duplicate of the first.
//
// The notification select is re-applied because migration 000022 snapshotted
// the type list; the two new kinds are inert until it is widened.
func init() {
	migrations.Register(func(app core.App) error {
		bookmarks, err := app.FindCollectionByNameOrId(util.Coll.Bookmarks)
		if err != nil {
			return err
		}
		if bookmarks.Fields.GetByName(util.Fields.Bookmark.Kind) == nil {
			bookmarks.Fields.Add(&core.SelectField{
				Name:      util.Fields.Bookmark.Kind,
				Values:    util.BookmarkKinds,
				MaxSelect: 1,
			})
		}
		bookmarks.RemoveIndex("idxBookmarksUserLink")
		bookmarks.AddIndex("idxBookmarksUserLink", true, "user, origin, slug, kind", "")
		if err := app.Save(bookmarks); err != nil {
			return err
		}

		notifications, err := app.FindCollectionByNameOrId(util.Coll.Notifications)
		if err != nil {
			return err
		}
		if typeField, ok := notifications.Fields.GetByName(util.Fields.Notification.Type).(*core.SelectField); ok {
			typeField.Values = util.NotificationTypes
		}
		return app.Save(notifications)
	}, func(app core.App) error {
		bookmarks, err := app.FindCollectionByNameOrId(util.Coll.Bookmarks)
		if err != nil {
			return nil
		}
		bookmarks.Fields.RemoveByName(util.Fields.Bookmark.Kind)
		bookmarks.RemoveIndex("idxBookmarksUserLink")
		bookmarks.AddIndex("idxBookmarksUserLink", true, "user, origin, slug", "")
		return app.Save(bookmarks)
	})
}
