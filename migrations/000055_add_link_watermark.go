package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds per-share watermarking: when set, every file the share serves is stamped
// on the way out with a line naming the share, so a leaked copy or screenshot
// shows who it was sent to. The stored file is never modified.
//
// watermarkText replaces the share's label in that line; it is a single line,
// since it is drawn across images and PDF pages.
func init() {
	migrations.Register(func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}
		if links.Fields.GetByName(util.Fields.Link.Watermark) == nil {
			links.Fields.Add(&core.BoolField{Name: util.Fields.Link.Watermark})
		}
		if links.Fields.GetByName(util.Fields.Link.WatermarkText) == nil {
			links.Fields.Add(&core.TextField{
				Name:    util.Fields.Link.WatermarkText,
				Max:     120,
				Pattern: `^[^\r\n\t]*$`,
			})
		}
		return app.Save(links)
	}, func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return nil
		}
		links.Fields.RemoveByName(util.Fields.Link.Watermark)
		links.Fields.RemoveByName(util.Fields.Link.WatermarkText)
		return app.Save(links)
	})
}
