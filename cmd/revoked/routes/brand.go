package routes

import (
	"embed"
	"encoding/base64"
	"html/template"
)

// Copies of app/assets/icon/*.svg; TestBrandLogosMatchApp keeps them in step.
//
//go:embed brand/*.svg
var brandFS embed.FS

var brandFuncs = template.FuncMap{
	"logoLight": brandLogo("brand/revoced-mark-redacted-black-on-white.svg"),
	"logoDark":  brandLogo("brand/revoced-mark-redacted-white-on-black.svg"),
}

func brandLogo(name string) func() template.URL {
	svg, err := brandFS.ReadFile(name)
	if err != nil {
		panic(err)
	}
	uri := template.URL("data:image/svg+xml;base64," + base64.StdEncoding.EncodeToString(svg))
	return func() template.URL { return uri }
}
