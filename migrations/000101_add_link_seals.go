package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Lets a link carry an end-to-end encrypted record (design/e2ee-sharing.md §3).
//
// linkSeals holds, per link and record, the record's current value key wrapped
// for the link's viewers, and the key to that wrap for whoever writes the
// record next. Rows live apart from the link so that a record write is not a
// change to the link. Nil rules, as for the key collections: clients reach
// them only through /api/sealed/* and the public link read.
//
// links.sealedKeyWraps keeps the link's key, which otherwise exists only in
// its address, for the devices that may show that address again.
func init() {
	migrations.Register(func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}
		records, err := app.FindCollectionByNameOrId(util.Coll.Records)
		if err != nil {
			return err
		}

		s := util.Fields.LinkSeal
		if _, err := app.FindCollectionByNameOrId(util.Coll.LinkSeals); err != nil {
			seals := core.NewBaseCollection(util.Coll.LinkSeals)
			seals.Fields.Add(
				&core.RelationField{
					Name:          s.Link,
					CollectionId:  links.Id,
					Required:      true,
					MaxSelect:     1,
					CascadeDelete: true,
				},
				&core.RelationField{
					Name:          s.Record,
					CollectionId:  records.Id,
					Required:      true,
					MaxSelect:     1,
					CascadeDelete: true,
				},
				&core.NumberField{Name: s.Version, Required: true, OnlyInt: true},
				&core.TextField{Name: s.ViewerWrap, Required: true, Max: 512},
				&core.TextField{Name: s.WriterWrap, Required: true, Max: 256},
				&core.AutodateField{Name: s.Created, OnCreate: true},
				&core.AutodateField{Name: s.Updated, OnCreate: true, OnUpdate: true},
			)
			seals.AddIndex("idxLinkSealsLinkRecord", true, s.Link+", "+s.Record, "")
			seals.AddIndex("idxLinkSealsRecord", false, s.Record, "")
			if err := app.Save(seals); err != nil {
				return err
			}
		}

		if links.Fields.GetByName(util.Fields.Link.SealedKeyWraps) == nil {
			links.Fields.Add(&core.JSONField{
				Name:    util.Fields.Link.SealedKeyWraps,
				MaxSize: 8192,
			})
		}
		return app.Save(links)
	}, func(app core.App) error {
		if coll, err := app.FindCollectionByNameOrId(util.Coll.LinkSeals); err == nil {
			if err := app.Delete(coll); err != nil {
				return err
			}
		}
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}
		links.Fields.RemoveByName(util.Fields.Link.SealedKeyWraps)
		return app.Save(links)
	})
}
