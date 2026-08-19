package migrations

import (
	"revoked/util"
	"strings"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Rotates request-born link slugs minted as grant_<requestSlug>_<n> (SEC-2 in TODO.md).
// The slug is the capability, and that scheme let anyone holding a request slug walk
// _1, _2, _3 … into every responder's live answers, so existing rows must be rotated
// too. Already-distributed grant_* URLs break by design; owners can re-share.
func init() {
	migrations.Register(func(app core.App) error {
		links, err := app.FindRecordsByFilter(
			util.Coll.Links,
			"slug ~ {:prefix} && request != ''",
			"",
			0,
			0,
			map[string]any{"prefix": "grant\\_%"},
		)
		if err != nil {
			return err
		}

		for _, link := range links {
			// The LIKE match can produce false positives; only rotate real legacy slugs.
			if !strings.HasPrefix(link.GetString(util.Fields.Link.Slug), "grant_") {
				continue
			}
			token, err := util.GenerateToken(16)
			if err != nil {
				return err
			}
			link.Set(util.Fields.Link.Slug, "g_"+token)
			if err := app.Save(link); err != nil {
				return err
			}
		}
		return nil
	}, func(app core.App) error {
		// Irreversible by design: the old slugs were the vulnerability.
		return nil
	})
}
