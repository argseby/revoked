package routes

import (
	"bytes"
	"html/template"
	"strings"

	"revoked/cmd/revoked/server"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// The page runs no script at all: language and store come from the request.
const appPageCSP = "default-src 'none'; style-src 'unsafe-inline'; img-src data:; " +
	"base-uri 'none'; form-action 'none'; frame-ancestors 'none'"

type appPageText struct {
	Lang, Title, Lead, Open, NoApp, AppStore, PlayStore, Server string
}

var appPageCopy = map[string]appPageText{
	"en": {
		Lang:      "en",
		Title:     "Open the app",
		Lead:      "Tap Open to start Revoked on this phone.",
		Open:      "Open Revoked",
		NoApp:     "No app yet?",
		AppStore:  "Get it on the App Store",
		PlayStore: "Get it on Google Play",
		Server:    "Your server",
	},
	"de": {
		Lang:      "de",
		Title:     "App öffnen",
		Lead:      "Tippe auf Öffnen, um Revoked auf diesem Handy zu starten.",
		Open:      "Revoked öffnen",
		NoApp:     "Noch keine App?",
		AppStore:  "Im App Store laden",
		PlayStore: "Bei Google Play laden",
		Server:    "Dein Server",
	},
}

type appPageData struct {
	T         appPageText
	Host      string
	AppStore  string
	PlayStore string
}

// AppPageRoute serves /app, where the QR code the app shows on a computer
// leads: it hands the person over to the app on their phone.
func AppPageRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/app", func(re *core.RequestEvent) error {
			return serveAppPage(re, root)
		})
		return e.Next()
	})
}

func serveAppPage(re *core.RequestEvent, root *server.RootKey) error {
	data := appPageData{
		T:         appPageCopy[pageLanguage(re.Request.Header.Get("Accept-Language"))],
		Host:      pageOrigin(re, root),
		AppStore:  util.AppStoreURL(),
		PlayStore: util.PlayStoreURL(),
	}
	// A phone is shown only its own store; anything else sees both.
	ua := re.Request.UserAgent()
	switch {
	case strings.Contains(ua, "iPhone") || strings.Contains(ua, "iPad"):
		data.PlayStore = ""
	case strings.Contains(ua, "Android"):
		data.AppStore = ""
	}

	var buf bytes.Buffer
	if err := appPageTemplate.Execute(&buf, data); err != nil {
		return re.InternalServerError("Failed to render the page.", err)
	}
	h := re.Response.Header()
	h.Set("Content-Security-Policy", appPageCSP)
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("Referrer-Policy", "no-referrer")
	h.Set("Cache-Control", "no-store")
	return writeText(re, "text/html", buf.String())
}

// pageLanguage picks German when the browser ranks it above English, as the
// passkey page does from navigator.languages.
func pageLanguage(acceptLanguage string) string {
	for _, part := range strings.Split(acceptLanguage, ",") {
		tag := strings.ToLower(strings.TrimSpace(strings.SplitN(part, ";", 2)[0]))
		switch {
		case tag == "de" || strings.HasPrefix(tag, "de-"):
			return "de"
		case tag == "en" || strings.HasPrefix(tag, "en-"):
			return "en"
		}
	}
	return "en"
}

var appPageTemplate = template.Must(template.New("app").Funcs(brandFuncs).Parse(`<!doctype html>
<html lang="{{.T.Lang}}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<link rel="icon" type="image/svg+xml" href="{{logoLight}}" media="(prefers-color-scheme: light)">
<link rel="icon" type="image/svg+xml" href="{{logoDark}}" media="(prefers-color-scheme: dark)">
<title>{{.T.Title}} · Revoked</title>
<style>
:root { color-scheme: light; --bg: #f6f5f1; --fg: #14171c; --fg-muted: #5a5f68; --control: #7f7b73; --subtle: #efede7; --primary: #14171c; --primary-fg: #ffffff; }
@media (prefers-color-scheme: dark) {
:root { color-scheme: dark; --bg: #171a1f; --fg: #f2f1ec; --fg-muted: #a3a8b0; --control: #727883; --subtle: #1f232a; --primary: #f2f1ec; --primary-fg: #14171c; }
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
background: var(--bg); color: var(--fg);
font-family: system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
font-size: 16px; line-height: 1.45; min-height: 100vh; -webkit-font-smoothing: antialiased;
}
main {
max-width: 440px; min-height: 100vh; margin: 0 auto;
padding: 24px 20px calc(32px + env(safe-area-inset-bottom));
display: flex; flex-direction: column; gap: 14px;
}
.space { flex: 1; }
.tile { width: 64px; height: 64px; border-radius: 18px; overflow: hidden; }
.tile img { width: 64px; height: 64px; display: block; }
.tile img.dark { display: none; }
@media (prefers-color-scheme: dark) { .tile img.light { display: none; } .tile img.dark { display: block; } }
h1 { font-size: 26px; font-weight: 650; line-height: 1.2; letter-spacing: -0.015em; }
.lead { color: var(--fg-muted); }
.btn {
min-height: 52px; border-radius: 12px; padding: 12px 16px;
display: flex; align-items: center; justify-content: center;
font-size: 16px; font-weight: 650; text-decoration: none; text-align: center;
}
.primary { background: var(--primary); color: var(--primary-fg); }
.quiet { border: 1px solid var(--control); color: var(--fg); font-weight: 600; }
.btn:focus-visible { outline: 2px solid var(--fg); outline-offset: 2px; }
.label { color: var(--fg-muted); font-size: 14px; text-align: center; }
.server { margin-top: 8px; padding: 10px 12px; border-radius: 12px; background: var(--subtle); font-size: 13px; color: var(--fg-muted); text-align: center; }
.server b { color: var(--fg); font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-weight: 500; }
</style>
</head>
<body>
<main>
<div class="space"></div>
<div class="tile"><img class="light" src="{{logoLight}}" alt="Revoked"><img class="dark" src="{{logoDark}}" alt="Revoked"></div>
<h1>{{.T.Title}}</h1>
<p class="lead">{{.T.Lead}}</p>
<div class="space"></div>
<a class="btn primary" href="revoked://open">{{.T.Open}}</a>
{{if or .AppStore .PlayStore}}<p class="label">{{.T.NoApp}}</p>{{end}}
{{if .AppStore}}<a class="btn quiet" href="{{.AppStore}}" rel="noopener noreferrer">{{.T.AppStore}}</a>{{end}}
{{if .PlayStore}}<a class="btn quiet" href="{{.PlayStore}}" rel="noopener noreferrer">{{.T.PlayStore}}</a>{{end}}
<p class="server">{{.T.Server}}: <b>{{.Host}}</b></p>
</main>
</body>
</html>
`))
