package services

import (
	"errors"

	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// SlugBytes gives every minted slug 128 bits of entropy.
const SlugBytes = 16

// MintUniqueSlug returns an unused capability slug for a collection. It fails
// rather than falling back to anything derivable: the slug is the only thing
// guarding what it names.
func MintUniqueSlug(app core.App, collection, prefix string) (string, error) {
	var lastErr error
	for attempt := 0; attempt < 5; attempt++ {
		token, err := util.GenerateToken(SlugBytes)
		if err != nil {
			lastErr = err
			continue
		}
		slug := prefix + token
		existing, _ := app.FindFirstRecordByFilter(collection, "slug = {:s}", map[string]any{"s": slug})
		if existing == nil {
			return slug, nil
		}
	}
	if lastErr == nil {
		lastErr = errors.New("exhausted slug attempts")
	}
	return "", lastErr
}

// MintSlugWhenEmpty gives a new share or request the server's own slug when
// the client chose none. A chosen slug is kept as the client's vanity address.
func MintSlugWhenEmpty(app core.App, rec *core.Record, field string) error {
	if rec.GetString(field) != "" {
		return nil
	}
	slug, err := MintUniqueSlug(app, rec.Collection().Name, "")
	if err != nil {
		return err
	}
	rec.Set(field, slug)
	return nil
}
