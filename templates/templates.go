// Package templates holds the built-in template catalogue every instance
// ships with: one JSON file per template, its filename doubling as the
// template's id. services.SyncBuiltinTemplates seeds them at startup, and
// operators override or extend them by dropping files of the same shape into
// TEMPLATES_DIR.
package templates

import "embed"

//go:embed *.json
var Files embed.FS
