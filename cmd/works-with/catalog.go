package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"
)

// Catalog is what the app bundles and fetches: every reviewed entry, in a
// stable order, with nothing that changes between builds of the same
// entries, so CI can tell a stale copy from an up-to-date one.
type Catalog struct {
	Schema   int      `json:"schema"`
	Services []*Entry `json:"services"`
}

// LoadEntries reads and validates every services/*.yaml. It returns the
// entries and every problem found, prefixed with the file it is in.
func LoadEntries(dir string, blocked *Blocklist) ([]*Entry, []string) {
	files, err := filepath.Glob(filepath.Join(dir, "*.yaml"))
	if err != nil {
		return nil, []string{err.Error()}
	}
	sort.Strings(files)
	var entries []*Entry
	var problems []string
	origins := map[string]string{}
	for _, file := range files {
		name := filepath.Base(file)
		data, err := os.ReadFile(file)
		if err != nil {
			problems = append(problems, fmt.Sprintf("%s: %v", name, err))
			continue
		}
		e, err := ParseEntry(data)
		if err != nil {
			problems = append(problems, fmt.Sprintf("%s: %v", name, err))
			continue
		}
		for _, p := range e.Validate(strings.TrimSuffix(name, ".yaml"), blocked) {
			problems = append(problems, fmt.Sprintf("%s: %s", name, p))
		}
		if other, ok := origins[e.Origin]; ok {
			problems = append(problems, fmt.Sprintf("%s: origin %s is already listed in %s", name, e.Origin, other))
		}
		origins[e.Origin] = name
		entries = append(entries, e)
	}
	return entries, problems
}

// Build orders the entries and fills defaults, so the JSON has no nulls and
// the same entries always give the same bytes.
func Build(entries []*Entry) *Catalog {
	out := make([]*Entry, 0, len(entries))
	for _, e := range entries {
		c := *e
		if c.Status == "" {
			c.Status = "listed"
		}
		c.Servers = nonNil(c.Servers)
		c.Languages = sorted(c.Languages)
		c.Categories = nonNil(c.Categories)
		c.Does = nonNil(c.Does)
		c.Permissions = nonNilPerm(c.Permissions)
		if s := c.Proposes.Shares; s != nil {
			s2 := *s
			s2.Templates, s2.Keys = nonNil(s2.Templates), nonNil(s2.Keys)
			c.Proposes.Shares = &s2
		}
		out = append(out, &c)
	}
	sort.SliceStable(out, func(i, j int) bool {
		a, b := strings.ToLower(out[i].Name), strings.ToLower(out[j].Name)
		if a != b {
			return a < b
		}
		return out[i].Slug < out[j].Slug
	})
	return &Catalog{Schema: schemaVersion, Services: out}
}

// Encode writes the catalog as indented JSON with a trailing newline.
func (c *Catalog) Encode() ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	if err := enc.Encode(c); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func nonNil(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}

func sorted(s []string) []string {
	s = slices.Clone(nonNil(s))
	slices.Sort(s)
	return s
}

func nonNilPerm(p []Permission) []Permission {
	if p == nil {
		return []Permission{}
	}
	return p
}
