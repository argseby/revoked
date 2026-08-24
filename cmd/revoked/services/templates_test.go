package services

import (
	"io/fs"
	"revoked/templates"
	"strings"
	"testing"
)

// Every shipped catalogue file must be one template, valid on its own, with
// the filename supplying the id — a broken file would otherwise only surface
// as a quiet skip in the startup log.
func TestShippedTemplateCatalogueIsValid(t *testing.T) {
	entries, err := fs.ReadDir(templates.Files, ".")
	if err != nil {
		t.Fatalf("read embedded catalogue: %v", err)
	}

	seen := 0
	for _, entry := range entries {
		name := entry.Name()
		if !strings.HasSuffix(name, ".json") {
			continue
		}
		seen++

		data, err := fs.ReadFile(templates.Files, name)
		if err != nil {
			t.Errorf("%s: read: %v", name, err)
			continue
		}
		parsed, err := ParseBuiltinTemplates(data)
		if err != nil {
			t.Errorf("%s: parse: %v", name, err)
			continue
		}
		if len(parsed) != 1 {
			t.Errorf("%s: expected exactly one template, got %d", name, len(parsed))
			continue
		}

		tpl := parsed[0]
		if tpl.Id == "" {
			tpl.Id = strings.TrimSuffix(name, ".json")
		} else if tpl.Id != strings.TrimSuffix(name, ".json") {
			t.Errorf("%s: id %q disagrees with the filename", name, tpl.Id)
		}
		if err := ValidateBuiltinTemplate(tpl); err != nil {
			t.Errorf("%s: %v", name, err)
		}
	}

	if seen < 12 {
		t.Errorf("expected at least 12 shipped templates, found %d", seen)
	}
}
