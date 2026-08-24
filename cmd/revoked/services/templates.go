package services

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"revoked/templates"
	"revoked/util"
	"sort"
	"strings"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// TemplatesDirEnv points the loader at an operator's template folder; unset, it
// defaults to a `templates` directory next to pb_data.
const TemplatesDirEnv = "TEMPLATES_DIR"

// BuiltinTemplate is one entry of the built-in catalogue: a stable slug, the
// display name and description, and the same schema JSON a workspace template
// holds.
type BuiltinTemplate struct {
	Id          string         `json:"id"`
	Name        string         `json:"name"`
	Description string         `json:"description"`
	Schema      map[string]any `json:"schema"`
}

var (
	templateSlugPattern = regexp.MustCompile(util.SlugPattern)
	templateFormats     = []string{"", util.FormatDefault, util.FormatHidden, util.FormatMultiline}
)

// BuiltinTemplatesDir resolves the drop-in folder for operator templates.
func BuiltinTemplatesDir(app core.App) string {
	if dir := os.Getenv(TemplatesDirEnv); dir != "" {
		return dir
	}
	return filepath.Join(filepath.Dir(app.DataDir()), "templates")
}

// BuiltinTemplateRecordId derives the record id a catalogue slug maps to. The
// id field only admits 15 lowercase alphanumerics, which a slug is not, so the
// slug is hashed — deterministically, which is what lets a restart update the
// same row instead of minting a new one.
func BuiltinTemplateRecordId(slug string) string {
	sum := sha256.Sum256([]byte("builtin-template:" + slug))
	return hex.EncodeToString(sum[:])[:15]
}

// ParseBuiltinTemplates decodes a catalogue file: either a single template
// object or an array of them.
func ParseBuiltinTemplates(data []byte) ([]BuiltinTemplate, error) {
	trimmed := strings.TrimSpace(string(data))
	if strings.HasPrefix(trimmed, "[") {
		var many []BuiltinTemplate
		if err := json.Unmarshal(data, &many); err != nil {
			return nil, err
		}
		return many, nil
	}
	var one BuiltinTemplate
	if err := json.Unmarshal(data, &one); err != nil {
		return nil, err
	}
	return []BuiltinTemplate{one}, nil
}

// ValidateBuiltinTemplate checks a catalogue entry against the same limits the
// collection enforces, so a bad drop-in file is refused with a message instead
// of surfacing as an opaque save error.
func ValidateBuiltinTemplate(t BuiltinTemplate) error {
	if !templateSlugPattern.MatchString(t.Id) || len(t.Id) > 64 {
		return fmt.Errorf("id %q must match %s and be at most 64 characters", t.Id, util.SlugPattern)
	}
	if t.Name == "" || len(t.Name) > 100 {
		return fmt.Errorf("name must be 1-100 characters")
	}
	if len(t.Description) > util.MaxTemplateDescriptionLength {
		return fmt.Errorf("description exceeds %d characters", util.MaxTemplateDescriptionLength)
	}
	if t.Schema == nil {
		return fmt.Errorf("schema is required")
	}

	total, err := validateTemplateRecords(t.Schema["records"])
	if err != nil {
		return err
	}
	sections, _ := t.Schema["sections"].([]any)
	for _, raw := range sections {
		section, ok := raw.(map[string]any)
		if !ok {
			return fmt.Errorf("each section must be an object")
		}
		key, _ := section["key"].(string)
		if !templateSlugPattern.MatchString(key) {
			return fmt.Errorf("section key %q must match %s", key, util.SlugPattern)
		}
		count, err := validateTemplateRecords(section["records"])
		if err != nil {
			return fmt.Errorf("section %q: %w", key, err)
		}
		total += count
	}
	if total == 0 {
		return fmt.Errorf("template has no fields")
	}
	return nil
}

func validateTemplateRecords(raw any) (int, error) {
	if raw == nil {
		return 0, nil
	}
	records, ok := raw.([]any)
	if !ok {
		return 0, fmt.Errorf("records must be an array")
	}
	for _, entry := range records {
		record, ok := entry.(map[string]any)
		if !ok {
			return 0, fmt.Errorf("each record must be an object")
		}
		key, _ := record["key"].(string)
		if key == "" {
			return 0, fmt.Errorf("a record is missing its key")
		}
		if typ, _ := record["type"].(string); typ != "" && !containsString(util.RecordTypes, typ) {
			return 0, fmt.Errorf("record %q has unknown type %q", key, typ)
		}
		if format, _ := record["format"].(string); !containsString(templateFormats, format) {
			return 0, fmt.Errorf("record %q has unknown format %q", key, format)
		}
		if value, _ := record["value"].(string); len(value) > util.MaxRecordValueLength {
			return 0, fmt.Errorf("record %q default value exceeds %d characters", key, util.MaxRecordValueLength)
		}
	}
	return len(records), nil
}

func containsString(list []string, s string) bool {
	for _, item := range list {
		if item == s {
			return true
		}
	}
	return false
}

// mergeCatalogueFiles reads every *.json in fsys into catalogue, overriding
// entries already merged under the same id. A single-template file that names
// no id takes its filename, so dropping in `template_name.json` is enough on
// its own; only an array file must carry an id per entry. A file that fails to
// read or parse is logged under origin and skipped.
func mergeCatalogueFiles(app core.App, catalogue map[string]BuiltinTemplate, fsys fs.FS, origin string) {
	entries, err := fs.ReadDir(fsys, ".")
	if err != nil {
		if !errors.Is(err, fs.ErrNotExist) {
			app.Logger().Error("Failed to read templates directory", "error", err, "dir", origin)
		}
		return
	}
	for _, entry := range entries {
		name := entry.Name()
		if entry.IsDir() || !strings.HasSuffix(name, ".json") {
			continue
		}
		data, err := fs.ReadFile(fsys, name)
		if err != nil {
			app.Logger().Error("Failed to read template file", "error", err, "file", name, "dir", origin)
			continue
		}
		parsed, err := ParseBuiltinTemplates(data)
		if err != nil {
			app.Logger().Error("Failed to parse template file", "error", err, "file", name, "dir", origin)
			continue
		}
		if len(parsed) == 1 && parsed[0].Id == "" {
			parsed[0].Id = strings.TrimSuffix(name, ".json")
		}
		for _, t := range parsed {
			catalogue[t.Id] = t
		}
	}
}

// SyncBuiltinTemplates reconciles the built-in template rows (workspace = ”)
// with the shipped catalogue (templates/*.json at the repository root,
// embedded at build) plus any *.json files in dir, which override shipped
// entries sharing an id. It runs at startup, so the files are the source of
// truth: entries are created or updated in place, and rows whose entry
// disappeared are deleted — unless a request still references them, in which
// case they are kept and logged. A malformed file is logged and skipped; it
// never blocks the remaining catalogue.
func SyncBuiltinTemplates(app core.App, dir string) error {
	catalogue := map[string]BuiltinTemplate{}
	mergeCatalogueFiles(app, catalogue, templates.Files, "embedded")
	mergeCatalogueFiles(app, catalogue, os.DirFS(dir), dir)

	collection, err := app.FindCollectionByNameOrId(util.Coll.Templates)
	if err != nil {
		return err
	}

	slugs := make([]string, 0, len(catalogue))
	for slug := range catalogue {
		slugs = append(slugs, slug)
	}
	sort.Strings(slugs)

	want := map[string]bool{}
	for _, slug := range slugs {
		t := catalogue[slug]
		if err := ValidateBuiltinTemplate(t); err != nil {
			app.Logger().Error("Skipping invalid built-in template", "error", err, "template", slug)
			continue
		}

		id := BuiltinTemplateRecordId(slug)
		want[id] = true

		schemaJSON, err := json.Marshal(t.Schema)
		if err != nil {
			app.Logger().Error("Skipping unserializable built-in template", "error", err, "template", slug)
			continue
		}

		record, err := app.FindRecordById(util.Coll.Templates, id)
		if err != nil {
			record = core.NewRecord(collection)
			record.Set("id", id)
		} else if record.GetString(util.Fields.Template.Name) == t.Name &&
			record.GetString(util.Fields.Template.Description) == t.Description &&
			record.GetString(util.Fields.Template.Schema) == string(schemaJSON) {
			continue
		}

		record.Set(util.Fields.Template.Name, t.Name)
		record.Set(util.Fields.Template.Description, t.Description)
		record.Set(util.Fields.Template.Schema, string(schemaJSON))
		record.Set(util.Fields.Template.Workspace, "")
		if err := app.Save(record); err != nil {
			app.Logger().Error("Failed to save built-in template", "error", err, "template", slug)
		}
	}

	stale, err := app.FindAllRecords(util.Coll.Templates, dbx.NewExp("workspace = ''"))
	if err != nil {
		return err
	}
	for _, record := range stale {
		if want[record.Id] {
			continue
		}
		references, err := app.CountRecords(util.Coll.Requests,
			dbx.HashExp{util.Fields.Request.Template: record.Id})
		if err != nil || references > 0 {
			app.Logger().Warn("Keeping removed built-in template still referenced by requests",
				"template", record.GetString(util.Fields.Template.Name), "references", references)
			continue
		}
		if err := app.Delete(record); err != nil {
			app.Logger().Error("Failed to delete stale built-in template", "error", err, "template", record.Id)
		}
	}

	return nil
}
