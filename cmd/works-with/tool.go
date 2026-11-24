package main

import (
	"bytes"
	"fmt"
	"slices"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// Tool is a developer tool in Works with Revoked: a package or program that
// builds on Revoked, rather than a service with a website of its own. It has
// no origin to prove, so it is listed by where its code and releases live,
// and the online check leaves it out.
type Tool struct {
	Schema         int       `yaml:"schema" json:"-"`
	Kind           string    `yaml:"kind" json:"-"`
	Slug           string    `yaml:"slug" json:"slug"`
	Name           string    `yaml:"name" json:"name"`
	Platform       string    `yaml:"platform" json:"platform"`
	Description    Localized `yaml:"description" json:"description"`
	Install        string    `yaml:"install,omitempty" json:"install,omitempty"`
	Registry       string    `yaml:"registry,omitempty" json:"registry,omitempty"`
	Docs           string    `yaml:"docs,omitempty" json:"docs,omitempty"`
	Source         string    `yaml:"source" json:"source"`
	License        string    `yaml:"license" json:"license"`
	Does           []string  `yaml:"does,omitempty" json:"does"`
	Maintainers    []string  `yaml:"maintainers" json:"-"`
	BuiltByRevoked bool      `yaml:"built_by_revoked,omitempty" json:"built_by_revoked"`
	Reviewed       string    `yaml:"reviewed" json:"reviewed"`
}

const toolKind = "tool"

// The words the app knows for a tool's platform and licence.
var (
	platforms = []string{"mcp", "npm", "flutter"}
	licenses  = []string{"AGPL-3.0", "Apache-2.0", "BSD-3-Clause", "GPL-3.0", "MIT", "MPL-2.0"}
)

// The project's own repository: a tool there counts as built by Revoked.
const officialSource = "https://github.com/argseby/"

const maxInstall = 120

// kindOf reads only the kind field, so a file can be decoded strictly as the
// type it declares.
func kindOf(data []byte) (string, error) {
	var head struct {
		Kind string `yaml:"kind"`
	}
	if err := yaml.Unmarshal(data, &head); err != nil {
		return "", err
	}
	return head.Kind, nil
}

// ParseTool reads one tool strictly, as ParseEntry reads a service.
func ParseTool(data []byte) (*Tool, error) {
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	var t Tool
	if err := dec.Decode(&t); err != nil {
		return nil, err
	}
	return &t, nil
}

// Validate returns every problem with the tool, empty when it is fine.
func (t *Tool) Validate(slug string) []string {
	var p []string
	add := func(format string, args ...any) { p = append(p, fmt.Sprintf(format, args...)) }

	if t.Schema != schemaVersion {
		add("schema must be %d", schemaVersion)
	}
	if t.Kind != toolKind {
		add("kind must be %q", toolKind)
	}
	if !slugPattern.MatchString(t.Slug) {
		add("slug %q: lower-case letters, digits and dashes, 1–40 characters", t.Slug)
	}
	if t.Slug != slug {
		add("slug %q must match the file name %q", t.Slug, slug+".yaml")
	}
	text(&p, "name", t.Name, maxName)
	if !slices.Contains(platforms, t.Platform) {
		add("platform must be one of %s", strings.Join(platforms, ", "))
	}
	localized(&p, "description", t.Description, maxDescription, true)
	if t.Install != "" {
		text(&p, "install", t.Install, maxInstall)
	}
	if t.Registry != "" {
		httpsURL(&p, "registry", t.Registry)
	}
	if t.Docs != "" {
		httpsURL(&p, "docs", t.Docs)
	}
	httpsURL(&p, "source", t.Source)
	if !slices.Contains(licenses, t.License) {
		add("license must be one of %s", strings.Join(licenses, ", "))
	}
	oneOf(&p, "does", t.Does, doesKinds, false)
	if len(t.Maintainers) == 0 {
		add("maintainers must name at least one GitHub account")
	}
	for _, m := range t.Maintainers {
		if !handlePattern.MatchString(m) {
			add("maintainers: %q is not a GitHub account name", m)
		}
	}
	if t.BuiltByRevoked && !strings.HasPrefix(t.Source, officialSource) {
		add("built_by_revoked is only for tools under %s", officialSource)
	}
	if _, err := time.Parse(time.DateOnly, t.Reviewed); err != nil {
		add("reviewed must be a date like 2026-11-09")
	}
	return p
}
