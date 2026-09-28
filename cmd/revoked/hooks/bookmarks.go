package hooks

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// BindBookmarkHooks keeps a bookmark's groups within its owner's own.
func BindBookmarkHooks(app core.App) {
	app.OnRecordCreate(util.Coll.Bookmarks).BindFunc(func(e *core.RecordEvent) error {
		if err := validateBookmarkGroups(app, e.Record); err != nil {
			return err
		}
		return e.Next()
	})
	app.OnRecordUpdate(util.Coll.Bookmarks).BindFunc(func(e *core.RecordEvent) error {
		if err := validateBookmarkGroups(app, e.Record); err != nil {
			return err
		}
		return e.Next()
	})
}

// validateBookmarkGroups refuses a group owned by anyone but the bookmark's
// owner. Relation validation only proves the id exists, and group ids travel
// in API responses, so without this a bookmark could be filed into a stranger's
// group.
func validateBookmarkGroups(app core.App, bookmark *core.Record) error {
	owner := bookmark.GetString(util.Fields.Bookmark.User)
	for _, id := range bookmark.GetStringSlice(util.Fields.Bookmark.Groups) {
		group, err := app.FindRecordById(util.Coll.BookmarkGroups, id)
		if err != nil || group.GetString(util.Fields.BookmarkGroup.User) != owner {
			return util.AsFieldValidationError(util.Fields.Bookmark.Groups, util.Errors.BookmarkGroupNotOwned)
		}
	}
	return nil
}
