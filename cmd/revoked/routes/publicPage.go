package routes

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"html/template"
	"net"
	"net/url"
	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"strconv"
	"strings"

	"github.com/pocketbase/pocketbase/core"
)

// The page fetches nothing but its own origin and the two DoH resolvers it
// needs to check this server's DNS pin. No CDN, no analytics, no fonts: a
// secret-sharing page that phones anywhere else is a page that leaks slugs.
const pageCSP = "default-src 'none'; " +
	"style-src 'unsafe-inline'; " +
	"img-src 'self' data: blob:; " +
	// A stamped PDF is previewed from memory; the frame inherits this policy, and
	// the browser's PDF viewer counts as an object.
	"frame-src blob:; object-src blob:; " +
	"connect-src 'self' https://cloudflare-dns.com https://dns.google; " +
	"base-uri 'none'; form-action 'none'; frame-ancestors 'none'"

// pageData is everything the shell renders without spending a view.
type pageData struct {
	Slug             string
	Label            string
	Domain           string
	Origin           string
	RootFingerprint  string
	SharerName       string
	SharerDomain     string
	SharerPrint      string
	SharerRevoked    bool
	Status           string
	Gated            bool
	RequireHandshake bool
	Watermarked      bool
	Purpose          string
	MaxViews         int
	ViewCount        int
	AppLink          template.URL
	Nonce            string
}

func wantsHTML(accept string) bool {
	return strings.Contains(strings.ToLower(accept), "text/html")
}

// pageOrigin returns the authority the handoff link must name: the one the
// reader actually reached, port and all.
//
// The configured DOMAIN is what the trust chain is anchored to, but it is not
// necessarily where this reader is. A dev server configured for the production
// domain still serves its own database on localhost:3000, and a link naming the
// production domain sends the app to a server that has never heard of the slug.
//
// The Host header is client-controlled, so it is only trusted when it names the
// configured domain or a loopback address — anything else falls back to the
// configured domain rather than letting a forged header redirect the app.
func pageOrigin(re *core.RequestEvent, root *server.RootKey) string {
	host := re.Request.Host
	if host == "" {
		return root.Domain()
	}
	name := host
	if h, port, err := net.SplitHostPort(host); err == nil {
		// SplitHostPort does not check that the port is a port: it splits on
		// the last colon and returns whatever follows. This value reaches a
		// template.URL, which is exempt from the URL sanitizer, so it is
		// checked here rather than resting on Go's Host-header validation.
		if n, convErr := strconv.Atoi(port); convErr != nil || n < 1 || n > 65535 {
			return root.Domain()
		}
		name = h
	}
	if strings.EqualFold(name, root.Domain()) || isLoopbackName(name) {
		return host
	}
	return root.Domain()
}

// isLoopbackName matches only the loopback host itself. A lookalike such as
// localhost.evil.com must not qualify, or a forged Host header would aim the
// handoff link at someone else's server.
func isLoopbackName(name string) bool {
	if strings.EqualFold(name, "localhost") {
		return true
	}
	ip := net.ParseIP(strings.Trim(name, "[]"))
	return ip != nil && ip.IsLoopback()
}

func servePublicPage(app core.App, re *core.RequestEvent, root *server.RootKey, link *core.Record, slug string) error {
	nonceBytes := make([]byte, 16)
	if _, err := rand.Read(nonceBytes); err != nil {
		return re.InternalServerError("Failed to render the page.", err)
	}
	nonce := base64.StdEncoding.EncodeToString(nonceBytes)

	origin := pageOrigin(re, root)
	data := pageData{
		Slug:             slug,
		Label:            link.GetString(util.Fields.Link.Label),
		Domain:           root.Domain(),
		Origin:           origin,
		RootFingerprint:  root.Fingerprint(),
		Status:           link.GetString(util.Fields.Link.Status),
		Gated:            link.GetString(util.Fields.Link.Password) != "",
		RequireHandshake: link.GetBool(util.Fields.Link.RequireHandshake),
		Watermarked:      link.GetBool(util.Fields.Link.Watermark),
		Purpose:          link.GetString(util.Fields.Link.Purpose),
		MaxViews:         link.GetInt(util.Fields.Link.MaxViews),
		ViewCount:        link.GetInt(util.Fields.Link.ViewCount),
		AppLink:          template.URL("revoked://s/" + origin + "/" + url.PathEscape(slug)),
		Nonce:            nonce,
	}
	if id, err := app.FindRecordById(util.Coll.Identities, link.GetString(util.Fields.Link.Identity)); err == nil && id != nil {
		data.SharerName = id.GetString(util.Fields.Identity.Name)
		data.SharerDomain = id.GetString(util.Fields.Identity.DomainAtIssue)
		data.SharerPrint = id.GetString(util.Fields.Identity.Fingerprint)
		data.SharerRevoked = !services.IdentityIsActive(id)
	}

	var buf bytes.Buffer
	if err := pageTemplate.Execute(&buf, data); err != nil {
		return re.InternalServerError("Failed to render the page.", err)
	}

	h := re.Response.Header()
	h.Set("Content-Security-Policy", strings.Replace(pageCSP, "style-src", "script-src 'nonce-"+nonce+"'; style-src", 1))
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("Referrer-Policy", "no-referrer")
	h.Set("Cache-Control", "no-store")
	return writeText(re, "text/html", buf.String())
}

var pageTemplate = template.Must(template.New("page").Funcs(brandFuncs).Parse(`{{define "heading"}}{{if eq .Purpose "application"}}Bewerbung{{if .Label}} · {{.Label}}{{end}}{{else if .Label}}{{.Label}}{{else}}Shared Items{{end}}{{end}}<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<link rel="icon" type="image/svg+xml" href="{{logoLight}}" media="(prefers-color-scheme: light)">
<link rel="icon" type="image/svg+xml" href="{{logoDark}}" media="(prefers-color-scheme: dark)">
<title>{{template "heading" .}} · Revoked</title>
<style>
:root {
--font-sans: system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
--font-mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
--ease: cubic-bezier(.2, .8, .2, 1);
}

:root,
html[data-theme="light"] {
color-scheme: light;
--bg: #f4f6fb;
--card: #ffffff;
--surface-subtle: #eceef4;
--surface-hover: #e1e4ec;
--border: #dde1e8;
--border-strong: #73777f;
--fg: #191c20;
--fg-muted: #555b64;
--primary: #35618e;
--primary-subtle: #d8e7fb;
--primary-fg: #ffffff;
--ok: #216a4d;
--ok-subtle: #d7f3e3;
--bad: #ba1a1a;
--bad-subtle: #ffdad6;
--warn: #6f5100;
--warn-subtle: #fff0c7;
--violet: #5b4a9e;
--violet-subtle: #e9e3ff;
--shadow: 0 1px 2px rgba(16, 24, 40, .04), 0 4px 16px rgba(16, 24, 40, .06);
}

html[data-theme="dark"] {
color-scheme: dark;
--bg: #0f1216;
--card: #181c21;
--surface-subtle: #24282e;
--surface-hover: #2d3238;
--border: #2c3137;
--border-strong: #8d9199;
--fg: #e3e5ea;
--fg-muted: #a9aeb7;
--primary: #a0cafd;
--primary-subtle: #1c3b5c;
--primary-fg: #003258;
--ok: #8ed5b1;
--ok-subtle: #11382a;
--bad: #ffb4ab;
--bad-subtle: #5c1512;
--warn: #f2c24b;
--warn-subtle: #3d2f08;
--violet: #cfbcff;
--violet-subtle: #34295e;
--shadow: none;
}

@media (prefers-color-scheme: dark) {
html:not([data-theme="light"]) {
color-scheme: dark;
--bg: #0f1216;
--card: #181c21;
--surface-subtle: #24282e;
--surface-hover: #2d3238;
--border: #2c3137;
--border-strong: #8d9199;
--fg: #e3e5ea;
--fg-muted: #a9aeb7;
--primary: #a0cafd;
--primary-subtle: #1c3b5c;
--primary-fg: #003258;
--ok: #8ed5b1;
--ok-subtle: #11382a;
--bad: #ffb4ab;
--bad-subtle: #5c1512;
--warn: #f2c24b;
--warn-subtle: #3d2f08;
--violet: #cfbcff;
--violet-subtle: #34295e;
--shadow: none;
}
}

* { box-sizing: border-box; margin: 0; padding: 0; }
body {
background: var(--bg);
color: var(--fg);
font-family: var(--font-sans);
font-size: 15px;
line-height: 1.5;
min-height: 100vh;
-webkit-font-smoothing: antialiased;
-webkit-tap-highlight-color: transparent;
}
svg { display: block; flex: none; }
a { color: var(--primary); text-decoration: none; }
a:hover { text-decoration: underline; }
button { font: inherit; }

header {
position: sticky;
top: 0;
z-index: 10;
background: color-mix(in srgb, var(--bg) 85%, transparent);
-webkit-backdrop-filter: blur(12px);
backdrop-filter: blur(12px);
border-bottom: 1px solid var(--border);
}
.nav {
max-width: 640px;
margin: 0 auto;
padding: 10px 16px;
display: flex;
align-items: center;
justify-content: space-between;
}
.brand { display: flex; align-items: center; gap: 8px; font-weight: 700; font-size: 16px; letter-spacing: -0.02em; color: var(--fg); }
.brand:hover { text-decoration: none; opacity: .8; }
.logo { width: 24px; height: 24px; border-radius: 6px; }
.logo-dark { display: none; }
html[data-theme="dark"] .logo-light { display: none; }
html[data-theme="dark"] .logo-dark { display: block; }
@media (prefers-color-scheme: dark) {
html:not([data-theme="light"]) .logo-light { display: none; }
html:not([data-theme="light"]) .logo-dark { display: block; }
}

main {
max-width: 640px;
margin: 0 auto;
padding: 18px 16px 24px;
display: flex;
flex-direction: column;
gap: 16px;
}
@media (min-width: 600px) { main { padding: 32px 24px 32px; gap: 18px; } }

.hero { display: flex; align-items: center; gap: 14px; }
.hero-tile {
width: 48px; height: 48px; border-radius: 15px; flex: none;
display: flex; align-items: center; justify-content: center;
background: var(--primary-subtle); color: var(--primary);
}
.hero h1 { font-size: 21px; font-weight: 650; line-height: 1.25; letter-spacing: -0.015em; overflow-wrap: anywhere; }
@media (min-width: 600px) { .hero h1 { font-size: 24px; } }

.card {
background: var(--card);
border: 1px solid var(--border);
border-radius: 18px;
box-shadow: var(--shadow);
overflow: hidden;
}

.nav-actions { display: flex; align-items: center; gap: 8px; }
.app-btn {
display: inline-flex; align-items: center; gap: 8px; height: 38px;
padding: 0 12px 0 8px; border-radius: 11px; border: 1px solid var(--border);
background: var(--card); color: var(--fg); font-size: 14px; font-weight: 600; white-space: nowrap;
}
.app-btn:hover { background: var(--surface-subtle); text-decoration: none; }
.app-btn .logo { width: 22px; height: 22px; }
.big-logo { width: 24px; height: 24px; }
@media (max-width: 360px) { .brand-t { display: none; } }

/* Sender: one verdict, then each fact marked where it cannot be vouched for. */
.sender { transition: border-color .3s, box-shadow .3s; }
/* While the server is checked only the button says so; the verdict and the
   server's badge arrive together with the answer. */
.sender[data-state="checking"] .verdict,
.sender[data-state="checking"] [data-dns] { display: none; }
.sender[data-state="checking"] .facts { border-top: 0; }
.verdict { animation: rise .4s var(--ease) both; }
.sender[data-state="bad"] { border-color: var(--bad); box-shadow: 0 0 0 1px var(--bad); }
.verdict { display: flex; align-items: center; gap: 12px; padding: 14px; }
.verdict .tile { color: var(--fg-muted); background: var(--surface-subtle); }
.sender[data-state="ok"] .verdict .tile { background: var(--ok-subtle); color: var(--ok); }
.sender[data-state="warn"] .verdict .tile { background: var(--warn-subtle); color: var(--warn); }
.sender[data-state="bad"] .verdict { background: var(--bad-subtle); }
.sender[data-state="bad"] .verdict .tile { background: var(--bad); color: var(--card); }
.verdict-t { font-weight: 650; font-size: 16px; line-height: 1.3; }
.sender[data-state="bad"] .verdict-t { color: var(--bad); }
.verdict-d { color: var(--fg-muted); font-size: 13px; line-height: 1.4; margin-top: 2px; overflow-wrap: anywhere; }
.facts { border-top: 1px solid var(--border); padding: 4px 14px 12px; }
.fact { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 9px 0; font-size: 14px; }
.fact + .fact { border-top: 1px solid var(--border); }
.fact-k { display: flex; align-items: center; gap: 10px; color: var(--fg-muted); flex: none; }
.fact-v { display: flex; align-items: center; justify-content: flex-end; flex-wrap: wrap; gap: 6px 8px; min-width: 0; text-align: right; }
.fact-name { display: inline-flex; align-items: center; gap: 5px; font-weight: 600; overflow-wrap: anywhere; min-width: 0; }
.fact.is-bad .fact-name { color: var(--bad); }
.fact.is-warn .fact-name { color: var(--warn); }
.fact-note { font-size: 12px; color: var(--fg-muted); margin-top: 6px; line-height: 1.45; }
.fact-note.mono { margin-top: 2px; }
.bad-t { color: var(--bad); }
.warn-t { color: var(--warn); }
.pill.warn { background: var(--warn-subtle); color: var(--warn); }

.pill {
display: inline-flex; align-items: center; gap: 5px;
padding: 3px 10px; border-radius: 999px;
font-size: 12px; font-weight: 500; white-space: nowrap;
background: var(--surface-subtle); color: var(--fg-muted);
}
.pill.ok { background: var(--ok-subtle); color: var(--ok); }
.pill.bad { background: var(--bad-subtle); color: var(--bad); }
.strip { display: flex; flex-wrap: wrap; gap: 6px; }

/* The trust gate: the one decision on the page before anything loads. */
.gate {
padding: 16px;
transition: opacity .3s var(--ease), transform .35s var(--ease), max-height .45s var(--ease),
padding .45s var(--ease), margin .45s var(--ease), border-width .45s;
}
.gate.gone { opacity: 0; transform: translateY(-6px) scale(.98); max-height: 0 !important; padding-top: 0; padding-bottom: 0; margin-bottom: -16px; border-width: 0; }
.callout {
display: flex; gap: 12px; align-items: flex-start;
padding: 14px; border-radius: 14px;
background: var(--warn-subtle); color: var(--warn);
font-size: 14px; line-height: 1.45;
}
.callout strong { display: block; font-size: 16px; font-weight: 650; margin-bottom: 2px; }
.callout.bad { background: var(--bad-subtle); color: var(--bad); }
.callout.info { background: var(--primary-subtle); color: var(--primary); }
.checks { margin: 8px 0 2px; }
.check {
display: flex; align-items: center; justify-content: space-between; gap: 12px;
padding: 11px 2px; border-bottom: 1px solid var(--border); font-size: 14px;
}
.check:last-child { border-bottom: 0; }
.check > span:first-child { display: flex; align-items: center; gap: 10px; color: var(--fg-muted); }
.check > span:last-child { text-align: right; min-width: 0; overflow-wrap: anywhere; }
.big {
width: 100%; min-height: 54px; margin-top: 14px;
border: 0; border-radius: 15px;
background: var(--primary); color: var(--primary-fg);
font-size: 16px; font-weight: 650;
display: flex; align-items: center; justify-content: center; gap: 10px;
padding: 12px 16px; text-align: center;
cursor: pointer; text-decoration: none;
transition: transform .12s var(--ease), filter .15s;
}
.big:hover { filter: brightness(1.06); text-decoration: none; }
.big:active { transform: scale(.985); }
.big:disabled { cursor: progress; opacity: .75; }
.spin { width: 18px; height: 18px; border-radius: 50%; border: 2px solid currentColor; border-right-color: transparent; animation: spin .7s linear infinite; display: none; flex: none; }
.big.loading .spin { display: block; }
.big.loading .big-ic { display: none; }
.fine { text-align: center; color: var(--fg-muted); font-size: 12px; margin-top: 10px; }
.fine:empty { display: none; }

/* Revealed content */
#out { display: flex; flex-direction: column; gap: 18px; }
.sec { animation: rise .5s var(--ease) both; }
.sh {
display: flex; align-items: center; justify-content: space-between; gap: 10px;
padding: 0 6px 8px; font-size: 13px; color: var(--fg-muted);
}
.sh-t { font-weight: 600; color: var(--fg); min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.sh-r { display: flex; align-items: center; gap: 8px; flex: none; }
.item + .item { border-top: 1px solid var(--border); }
.rec { display: flex; align-items: center; gap: 12px; padding: 12px 12px 12px 14px; min-height: 66px; }
.tile { width: 40px; height: 40px; border-radius: 12px; flex: none; display: flex; align-items: center; justify-content: center; }
.tone-neutral { background: var(--surface-subtle); color: var(--fg-muted); }
.tone-ok { background: var(--ok-subtle); color: var(--ok); }
.tone-primary { background: var(--primary-subtle); color: var(--primary); }
.tone-violet { background: var(--violet-subtle); color: var(--violet); }
.tone-warn { background: var(--warn-subtle); color: var(--warn); }
.tone-bad { background: var(--bad-subtle); color: var(--bad); }
.tx { flex: 1; min-width: 0; }
.lb { font-size: 12px; color: var(--fg-muted); line-height: 1.3; }
.v { font-size: 15px; line-height: 1.4; overflow-wrap: anywhere; white-space: pre-wrap; margin-top: 1px; }
.acts { display: flex; gap: 6px; flex: none; }
.ib {
width: 40px; height: 40px; border-radius: 12px;
border: 1px solid var(--border); background: transparent; color: var(--fg);
display: inline-flex; align-items: center; justify-content: center;
cursor: pointer; text-decoration: none;
transition: background .15s, color .15s, border-color .15s, transform .1s var(--ease);
}
.ib:hover { background: var(--surface-subtle); text-decoration: none; }
.ib:active { transform: scale(.9); }
.ib.done { background: var(--ok-subtle); color: var(--ok); border-color: transparent; }
.ib.done svg { animation: pop .3s var(--ease); }
.ib:disabled { opacity: .5; cursor: progress; }
.act {
height: 40px; padding: 0 14px; border-radius: 12px; border: 0;
display: inline-flex; align-items: center; gap: 6px;
font-size: 14px; font-weight: 650; cursor: pointer; text-decoration: none;
transition: transform .1s var(--ease), filter .15s;
}
.act:hover { filter: brightness(.97); text-decoration: none; }
.act:active { transform: scale(.95); }
.act.ok { background: var(--ok-subtle); color: var(--ok); }
.act.primary { background: var(--primary); color: var(--primary-fg); }
.act:disabled { opacity: .6; cursor: progress; }
@media (max-width: 350px) {
.rec { gap: 10px; padding-left: 12px; }
.tile { width: 36px; height: 36px; }
.act.ok .act-t { display: none; }
.act.ok { width: 40px; padding: 0; justify-content: center; }
}
.preview {
margin: 0 12px 12px; border-radius: 12px; overflow: hidden;
border: 1px solid var(--border); background: var(--surface-subtle);
animation: rise .4s var(--ease) both;
}
.preview img { display: block; max-width: 100%; height: auto; margin: 0 auto; }
.preview iframe { display: block; width: 100%; height: 70vh; border: 0; }
.err { color: var(--bad); font-size: 13px; padding: 10px 14px; }
.bar { display: flex; align-items: center; gap: 12px; padding: 12px 12px 12px 14px; }
.bar .tx { font-size: 14px; color: var(--fg-muted); }
.empty { padding: 16px; color: var(--fg-muted); font-size: 14px; }

.mono { font-family: var(--font-mono); font-size: 12px; overflow-wrap: anywhere; color: var(--fg-muted); margin-top: 4px; }
.muted { color: var(--fg-muted); }
[hidden] { display: none !important; }

.toast {
position: fixed; left: 50%; bottom: calc(18px + env(safe-area-inset-bottom));
transform: translate(-50%, 16px); opacity: 0; pointer-events: none;
max-width: calc(100vw - 32px); z-index: 50;
display: flex; align-items: center; gap: 8px;
padding: 11px 16px; border-radius: 14px;
background: var(--fg); color: var(--bg);
font-size: 14px; font-weight: 500;
box-shadow: 0 8px 24px rgba(0, 0, 0, .18);
transition: opacity .25s var(--ease), transform .3s var(--ease);
}
.toast span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.toast.on { opacity: 1; transform: translate(-50%, 0); }

main { padding-bottom: calc(40px + env(safe-area-inset-bottom)); }
.theme {
width: 38px; height: 38px; border-radius: 11px; border: 1px solid var(--border);
background: var(--card); color: var(--fg); cursor: pointer;
display: inline-flex; align-items: center; justify-content: center;
}

.wm-host { position: relative; }
.wm-overlay { position: absolute; inset: 0; overflow: hidden; pointer-events: none; z-index: 5; }
.wm-overlay-inner {
position: absolute; top: -50%; left: -50%; width: 200%; height: 200%;
transform: rotate(-30deg);
display: flex; flex-direction: column; justify-content: space-around;
color: var(--fg); opacity: 0.1; font-size: 13px; font-weight: 600; white-space: nowrap;
}

@keyframes spin { to { transform: rotate(360deg); } }
@keyframes rise { from { opacity: 0; transform: translateY(14px); } to { opacity: 1; transform: none; } }
@keyframes pop { 0% { transform: scale(.5); } 70% { transform: scale(1.15); } 100% { transform: scale(1); } }
@media (prefers-reduced-motion: reduce) {
*, *::before, *::after { animation: none !important; transition: none !important; }
}
</style>
</head>
<body>

<header>
<div class="nav">
<a class="brand" href="https://revoked.link" target="_blank" rel="noopener noreferrer" title="Learn more about Revoked at revoked.link">
<img class="logo logo-light" src="{{logoLight}}" alt="">
<img class="logo logo-dark" src="{{logoDark}}" alt="">
<span class="brand-t">Revoked</span>
</a>
<div class="nav-actions">
{{if not (or .Gated .RequireHandshake)}}<a href="{{.AppLink}}" class="app-btn" aria-label="Open in the Revoked app">
<img class="logo logo-light" src="{{logoLight}}" alt="">
<img class="logo logo-dark" src="{{logoDark}}" alt="">
<span>Open in app</span>
</a>{{end}}
<button class="theme" id="theme-toggle" aria-label="Toggle visual theme"></button>
</div>
</div>
</header>

<main{{if eq .Purpose "application"}} data-purpose="application"{{end}}>

<div class="hero">
<div class="hero-tile"><i data-i="{{if eq .Purpose "application"}}briefcase{{else}}link{{end}}" data-s="24"></i></div>
<h1>{{template "heading" .}}</h1>
</div>

{{/* The one place that says who this is from and how far that can be trusted.
     Every fact in it that cannot be vouched for is marked where it stands. */}}
<section class="card sender" id="sender" data-state="checking">
<div class="verdict">
<div class="tile" id="verdict-tile"></div>
<div style="min-width: 0;">
<div class="verdict-t" id="verdict-t"></div>
<div class="verdict-d" id="verdict-d"></div>
</div>
</div>
<div class="facts">
<div class="fact" id="fact-server">
<span class="fact-k"><i data-i="server"></i>Server</span>
<span class="fact-v"><span class="fact-name">{{.Domain}}</span><span class="pill" data-dns>Checking…</span></span>
</div>
<div class="fact{{if .SharerRevoked}} is-bad{{else if not .SharerName}} is-warn{{end}}" id="fact-sender">
<span class="fact-k"><i data-i="user"></i>Sender</span>
<span class="fact-v">
{{if .SharerName}}<span class="fact-name">{{if .SharerRevoked}}<i data-i="alert" data-s="15"></i>{{end}}{{.SharerName}}</span>
{{if .SharerRevoked}}<span class="pill bad">Withdrawn</span>{{else}}<span class="pill" id="sender-pill" title="This name is provided by the server. The Revoked app can verify the signature behind it.">Reported by server</span>{{end}}
{{else}}<span class="fact-name"><i data-i="alert" data-s="15"></i>Not specified</span><span class="pill warn">Unsigned</span>{{end}}
</span>
</div>
{{if .SharerPrint}}<div class="fact-note mono">Key fingerprint {{.SharerPrint}}</div>{{end}}
{{if .SharerRevoked}}<div class="fact-note bad-t">{{.Domain}} has withdrawn this sender's identity. The link was signed while the identity was still valid, but the domain no longer stands behind it.</div>
{{else if not .SharerName}}<div class="fact-note warn-t">This link isn't signed by a named person, so anyone with access to {{.Domain}} could have created it.</div>
{{else}}<div class="fact-note">This is the name the server reports for the sender. A browser can't confirm it on its own; <a href="{{.AppLink}}">open the link in the Revoked app</a> to verify the sender's signature.</div>{{end}}
</div>
</section>

{{if or .Gated .RequireHandshake}}
<div class="card gate">
<div class="callout info">
<i data-i="lock" data-s="22"></i>
<div>
<strong>This link opens in the Revoked app</strong>
It's protected by {{if .RequireHandshake}}a verified identity{{else}}a password{{end}}. The app confirms the server's identity before it sends anything, so your credentials only reach the genuine server. Please don't enter passwords or other secrets on a web page hosted by the sender, as it could have been altered.
</div>
</div>
<a href="{{.AppLink}}" class="big"><img class="logo logo-light big-logo" src="{{logoLight}}" alt=""><img class="logo logo-dark big-logo" src="{{logoDark}}" alt="">Open in the Revoked app</a>
</div>
{{else}}
<div class="strip" id="strip" hidden>
{{if gt .MaxViews 0}}<span class="pill"><i data-i="eye" data-s="13"></i><span id="views-text">{{.ViewCount}} of {{.MaxViews}} views used</span></span>{{end}}
{{if .Watermarked}}<span class="pill"><i data-i="droplet" data-s="13"></i>Watermarked files</span>{{end}}
</div>

<div class="card gate" id="gate">
<div class="callout" id="gate-callout">
<i data-i="alert" data-s="22"></i>
<div>
<strong id="gate-t">Make sure you trust the sender</strong>
<span id="gate-d">This page is served directly from the sender's own server. Please review the details above before you open the shared information.</span>
</div>
</div>
{{/* Held until the sender check has an answer, so nobody opens the data before
     the page could say whether to trust it. */}}
<button class="big loading" id="reveal" disabled><span class="spin"></span><i class="big-ic" data-i="lock-open"></i><span id="reveal-t">Verifying the server…</span></button>
<div class="fine" id="capnote">{{if gt .MaxViews 0}}Opening this link uses one of its remaining views ({{.ViewCount}} of {{.MaxViews}} already used).{{end}}{{if .Watermarked}} Downloaded files carry a watermark that traces them back to this link.{{end}}</div>
</div>

<div id="out"></div>
{{end}}

</main>


<div class="toast" id="toast" role="status" aria-live="polite"><i data-i="check" data-s="16"></i><span id="toast-t"></span></div>

<script nonce="{{.Nonce}}">
(function(){
var slug={{.Slug}}, domain={{.Domain}}, pin={{.RootFingerprint}}, maxViews={{.MaxViews}}, viewCount={{.ViewCount}};

// Icons are drawn here rather than fetched: the page loads nothing but its
// own origin.
var ICONS = {
'link': '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
'briefcase': '<rect x="2" y="7" width="20" height="14" rx="2"/><path d="M16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2M2 13h20"/>',
'alert': '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3z"/><path d="M12 9v4M12 17h.01"/>',
'lock': '<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',
'lock-open': '<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 9.9-1"/>',
'shield': '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>',
'server': '<rect x="2" y="2" width="20" height="8" rx="2"/><rect x="2" y="14" width="20" height="8" rx="2"/><path d="M6 6h.01M6 18h.01"/>',
'user': '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
'eye': '<path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/>',
'droplet': '<path d="M12 2.69l5.66 5.66a8 8 0 1 1-11.31 0z"/>',
'phone': '<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/>',
'mail': '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-10 6L2 7"/>',
'send': '<path d="m22 2-7 20-4-9-9-4z"/><path d="M22 2 11 13"/>',
'globe': '<circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>',
'external': '<path d="M15 3h6v6M10 14 21 3M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
'calendar': '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
'hash': '<path d="M4 9h16M4 15h16M10 3 8 21M16 3l-2 18"/>',
'toggle': '<rect x="1" y="5" width="22" height="14" rx="7"/><circle cx="16" cy="12" r="3"/>',
'pin': '<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0z"/><circle cx="12" cy="10" r="3"/>',
'building': '<rect x="4" y="2" width="16" height="20" rx="2"/><path d="M9 22v-4h6v4M8 6h.01M12 6h.01M16 6h.01M8 10h.01M12 10h.01M16 10h.01M8 14h.01M12 14h.01M16 14h.01"/>',
'text': '<path d="M17 6H3M21 12H3M15 18H3"/>',
'file': '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>',
'file-text': '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M16 13H8M16 17H8M10 9H8"/>',
'image': '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-5-5L5 21"/>',
'download': '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3"/>',
'archive': '<rect x="2" y="3" width="20" height="5" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8M10 12h4"/>',
'copy': '<rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
'check': '<path d="M20 6 9 17l-5-5"/>',
'sun': '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/>',
'moon': '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>'
};

function svg(name, size) {
var s = size || 18;
var box = document.createElement('span');
box.innerHTML = '<svg width="' + s + '" height="' + s + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (ICONS[name] || '') + '</svg>';
return box.firstChild;
}

function fillIcons(root) {
Array.prototype.forEach.call(root.querySelectorAll('i[data-i]'), function(n) {
var icon = svg(n.getAttribute('data-i'), Number(n.getAttribute('data-s')) || 18);
if (n.className) icon.setAttribute('class', n.className);
n.replaceWith(icon);
});
}
fillIcons(document);

function el(t, c, txt) {
var e = document.createElement(t);
if (c) e.className = c;
if (txt != null) e.textContent = txt;
return e;
}

function fmtBytes(n) {
if (n < 1024) return n + ' B';
var u = ['KB','MB','GB'], i = -1;
do { n /= 1024; i++; } while (n >= 1024 && i < u.length - 1);
return n.toFixed(n >= 100 ? 0 : 1) + ' ' + u[i];
}

// ---- Theme ----------------------------------------------------------------
var themeToggle = document.getElementById('theme-toggle');
function isDark() {
var current = document.documentElement.getAttribute('data-theme');
if (current === 'dark') return true;
if (current === 'light') return false;
return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
}
function updateToggle() {
if (!themeToggle) return;
themeToggle.textContent = '';
themeToggle.appendChild(svg(isDark() ? 'sun' : 'moon', 16));
themeToggle.setAttribute('aria-label', isDark() ? 'Switch to light theme' : 'Switch to dark theme');
}
function applyTheme(theme) {
if (theme === 'light' || theme === 'dark') document.documentElement.setAttribute('data-theme', theme);
else document.documentElement.removeAttribute('data-theme');
updateToggle();
}
var savedTheme = null;
try { savedTheme = localStorage.getItem('revoked_theme'); } catch (e) {}
applyTheme(savedTheme);
if (themeToggle) {
themeToggle.addEventListener('click', function() {
var next = isDark() ? 'light' : 'dark';
try { localStorage.setItem('revoked_theme', next); } catch (e) {}
applyTheme(next);
});
}
if (window.matchMedia) {
var mq = window.matchMedia('(prefers-color-scheme: dark)');
if (mq.addEventListener) mq.addEventListener('change', updateToggle);
else if (mq.addListener) mq.addListener(updateToggle);
}

// ---- Toast ----------------------------------------------------------------
var toastNode = document.getElementById('toast');
var toastTimer = null;
function toast(msg) {
document.getElementById('toast-t').textContent = msg;
toastNode.classList.add('on');
clearTimeout(toastTimer);
toastTimer = setTimeout(function() { toastNode.classList.remove('on'); }, 2200);
}

// The Clipboard API needs a secure context; a plain-http self-hosted page
// falls back to copying a selection.
function copyText(text) {
if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
return new Promise(function(resolve, reject) {
var span = el('span', '', text);
span.style.position = 'fixed';
span.style.opacity = '0';
span.style.whiteSpace = 'pre';
document.body.appendChild(span);
var range = document.createRange();
range.selectNodeContents(span);
var sel = window.getSelection();
sel.removeAllRanges();
sel.addRange(range);
var ok = false;
try { ok = document.execCommand('copy'); } catch (e) {}
sel.removeAllRanges();
span.remove();
if (ok) resolve(); else reject();
});
}

// ---- Sender verdict --------------------------------------------------------
// The server's DNS check and the sender's identity make one verdict, shown in
// the sender card, and anything that fails is marked where it is shown.
var signer = {{if .SharerRevoked}}'withdrawn'{{else if .SharerName}}'stated'{{else}}'none'{{end}};

var SERVER_PILLS = {
ok: ['ok', 'Verified'],
spoofed: ['bad', 'Spoofed'],
unverified: ['bad', 'Unverified'],
local: ['', 'Local']
};

function verdictFor(server) {
if (server === 'spoofed') return ['bad', 'Possible impersonation',
'The key used by this server doesn\'t match the one published for ' + domain + '. Someone may be impersonating it, so please don\'t rely on anything shown on this page.'];
if (server === 'unverified') return ['bad', 'Server couldn\'t be verified',
domain + ' doesn\'t publish a DNS record that confirms its identity, so there\'s no way to tell whether this page comes from the genuine server.'];
if (signer === 'withdrawn') return ['bad', 'Sender no longer trusted',
domain + ' has withdrawn the identity that signed this link.'];
if (server === 'local') return [signer === 'none' ? 'warn' : 'neutral', 'Local server',
'This page is served from a local or private address, so it can\'t be checked against public DNS records.' +
(signer === 'none' ? ' The link also isn\'t signed by a named person.' : '')];
if (signer === 'none') return ['warn', 'Server verified, sender unknown',
'You\'re connected to the genuine ' + domain + ' server, but no named person has signed this link.'];
return ['ok', 'Server verified', 'The key used by ' + domain + ' matches the one published in its DNS records, so you\'re connected to the genuine server.'];
}

function setServer(server, title) {
var pill = SERVER_PILLS[server];
Array.prototype.forEach.call(document.querySelectorAll('[data-dns]'), function(n) {
n.className = 'pill' + (pill[0] ? ' ' + pill[0] : '');
n.textContent = '';
if (server === 'ok') n.appendChild(svg('check', 13));
n.appendChild(document.createTextNode(pill[1]));
if (title) n.title = title;
});

var fact = document.getElementById('fact-server');
var bad = server === 'spoofed' || server === 'unverified';
fact.classList.toggle('is-bad', bad);
var name = fact.querySelector('.fact-name');
if (bad && !name.querySelector('svg')) name.insertBefore(svg('alert', 15), name.firstChild);

// A name is only as good as the server stating it: when the server fails,
// the name is marked too.
var senderFact = document.getElementById('fact-sender');
var senderPill = document.getElementById('sender-pill');
if (bad && senderPill) {
senderFact.classList.add('is-bad');
senderPill.className = 'pill bad';
senderPill.textContent = 'Unconfirmed';
senderPill.title = 'This name comes from a server that failed verification, so it can\'t be relied on.';
var senderName = senderFact.querySelector('.fact-name');
if (!senderName.querySelector('svg')) senderName.insertBefore(svg('alert', 15), senderName.firstChild);
}

var v = verdictFor(server);
var card = document.getElementById('sender');
card.setAttribute('data-state', v[0]);
var tile = document.getElementById('verdict-tile');
tile.textContent = '';
tile.appendChild(svg(v[0] === 'ok' ? 'shield' : v[0] === 'neutral' ? 'server' : 'alert', 20));
document.getElementById('verdict-t').textContent = v[1];
document.getElementById('verdict-d').textContent = v[2];

// The check has an answer, so the reader can now decide.
var reveal = document.getElementById('reveal');
if (reveal) {
reveal.disabled = false;
reveal.classList.remove('loading');
document.getElementById('reveal-t').textContent = 'Yes, I trust the sender';
}

// A failed check turns the gate's warning from a caution into a stop.
var callout = document.getElementById('gate-callout');
if (callout && v[0] === 'bad') {
callout.classList.add('bad');
document.getElementById('gate-t').textContent = 'Proceed with caution';
document.getElementById('gate-d').textContent = "The sender couldn't be verified. Only continue if you know for certain who sent you this link.";
}
}

function checkDNS() {
var d = String(domain || '');
// Local/dev hosts have no public DNS record to pin against.
var isLocal = d === '' || d === 'localhost' || d.indexOf('.') === -1 ||
d.indexOf(':') !== -1 || /^\d+\.\d+\.\d+\.\d+$/.test(d) ||
/\.(localhost|local|test|internal)$/i.test(d);
if (isLocal) {
setServer('local', 'DNS verification isn\'t available for local or private addresses.');
return;
}
var name = '_revoked.' + d;
var urls = [
'https://cloudflare-dns.com/dns-query?type=TXT&name=' + encodeURIComponent(name),
'https://dns.google/resolve?type=TXT&name=' + encodeURIComponent(name)
];
var done = false;
urls.forEach(function(u) {
fetch(u, { headers: { accept: 'application/dns-json' } })
.then(function(r) { return r.json(); })
.then(function(j) {
if (done) return;
var answers = (j && j.Answer) || [];
for (var i = 0; i < answers.length; i++) {
var txt = String(answers[i].data || '').replace(/^"|"$/g, '').replace(/""/g, '');
var m = /k=sha256\/([a-f0-9]{64})/i.exec(txt);
if (m) {
done = true;
if (m[1].toLowerCase() === String(pin).toLowerCase()) setServer('ok');
else setServer('spoofed', 'This server\'s key doesn\'t match the one published in its DNS records.');
return;
}
}
}).catch(function(){});
});
setTimeout(function() {
if (done) return;
setServer('unverified', 'No DNS record confirms this server\'s key.');
}, 5000);
}

// ---- What a value is --------------------------------------------------------
var KINDS = {
phone: { icon: 'phone', tone: 'ok' },
email: { icon: 'mail', tone: 'primary' },
url: { icon: 'globe', tone: 'violet' },
date: { icon: 'calendar', tone: 'warn' },
number: { icon: 'hash', tone: 'neutral' },
bool: { icon: 'toggle', tone: 'neutral' },
person: { icon: 'user', tone: 'neutral' },
place: { icon: 'pin', tone: 'neutral' },
work: { icon: 'building', tone: 'neutral' },
text: { icon: 'text', tone: 'neutral' },
pdf: { icon: 'file-text', tone: 'bad' },
image: { icon: 'image', tone: 'primary' },
file: { icon: 'file', tone: 'neutral' }
};

function digitCount(v) { return (v.match(/\d/g) || []).length; }

// Told from the record's type first, then from what the value looks like, and
// last from its key or label — a text record holding "+49 170 …" is a phone.
function kindOf(r) {
var t = r.type || 'text';
var v = r.value == null ? '' : String(r.value).trim();
var hint = (String(r.key || '') + ' ' + String(r.label || '')).toLowerCase();
if (t === 'file') {
var m = String(r.mime || '').toLowerCase(), f = String(r.filename || '').toLowerCase();
if (m.indexOf('pdf') !== -1 || /\.pdf$/.test(f)) return 'pdf';
if (m.indexOf('image/') === 0 || /\.(png|jpe?g|gif|webp|heic)$/.test(f)) return 'image';
return 'file';
}
if (t === 'boolean') return 'bool';
if (/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v)) return 'email';
if (t === 'url' || /^https?:\/\/\S+$/i.test(v) || /^www\.\S+\.\S+$/i.test(v)) return 'url';
var n = digitCount(v);
if (/^\+?[\d\s()\/.\-]+$/.test(v) && n >= 6 && n <= 15 &&
(/^(\+|0)/.test(v) || /phone|tel|mobil|handy|fax/.test(hint))) return 'phone';
if (t === 'datetime' || /^\d{4}-\d{2}-\d{2}([T ]|$)/.test(v)) return 'date';
if (t === 'number') return 'number';
if (/address|adresse|street|stra(ss|ß)e/.test(hint)) return 'place';
if (/employer|company|arbeitgeber|firma/.test(hint)) return 'work';
if (/name/.test(hint)) return 'person';
return 'text';
}

function displayValue(kind, v) {
if (kind === 'bool') {
if (/^true$/i.test(v)) return 'Yes';
if (/^false$/i.test(v)) return 'No';
}
if (kind === 'date') {
var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
try {
if (m) return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3])).toLocaleDateString(undefined, { dateStyle: 'long', timeZone: 'UTC' });
var d = new Date(v);
if (!isNaN(d)) return d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
} catch (e) {}
}
if (kind === 'number' && /^-?\d+(\.\d+)?$/.test(v)) {
var num = Number(v);
if (isFinite(num) && Math.abs(num) < 1e15) return num.toLocaleString();
}
return v;
}

// Only ever a web address: a shared value must not become a javascript: link.
function webHref(v) {
var href = /^https?:\/\//i.test(v) ? v : 'https://' + v;
try {
var u = new URL(href);
return (u.protocol === 'https:' || u.protocol === 'http:') ? u.href : null;
} catch (e) { return null; }
}

function iconButton(icon, label) {
var b = el('button', 'ib');
b.type = 'button';
b.setAttribute('aria-label', label);
b.title = label;
b.appendChild(svg(icon));
return b;
}

function iconLink(icon, label, href, newTab) {
var a = el('a', 'ib');
a.href = href;
a.setAttribute('aria-label', label);
a.title = label;
if (newTab) { a.target = '_blank'; a.rel = 'noopener noreferrer'; }
a.appendChild(svg(icon));
return a;
}

function copyButton(value, label) {
var b = iconButton('copy', 'Copy ' + label);
var timer = null;
b.addEventListener('click', function() {
copyText(value).then(function() {
b.classList.add('done');
b.textContent = '';
b.appendChild(svg('check'));
toast('Copied “' + (value.length > 32 ? value.slice(0, 32) + '…' : value) + '”');
clearTimeout(timer);
timer = setTimeout(function() {
b.classList.remove('done');
b.textContent = '';
b.appendChild(svg('copy'));
}, 1500);
}, function() { toast('Your browser blocked copying. Please select the text and copy it manually.'); });
});
return b;
}

// Set on reveal for a watermarked share: its files come back stamped, and the
// same line is laid over the page so a screenshot of plain values carries it.
var watermarkLine = '';
var stampedTypes = { 'image/png': '.png', 'image/jpeg': '.jpg', 'application/pdf': '.pdf' };

function fileURL(r) {
return '/api/public/links/' + encodeURIComponent(slug) + '/files/' + encodeURIComponent(r.id) + '?dl=' + encodeURIComponent(r.downloadToken || '');
}

function renderRecordItem(r) {
var item = el('div', 'item');
var row = el('div', 'rec');
var kind = kindOf(r);
var meta = KINDS[kind];
var label = r.label || r.key || 'Record';

var tile = el('div', 'tile tone-' + meta.tone);
tile.appendChild(svg(meta.icon, 20));
row.appendChild(tile);

var tx = el('div', 'tx');
tx.appendChild(el('div', 'lb', label));
if (r.key) tx.title = r.key;
var acts = el('div', 'acts');

if (r.type === 'file') {
tx.appendChild(el('div', 'v', (r.filename || 'file') + ' · ' + fmtBytes(r.size || 0)));
if (watermarkLine) acts.appendChild(stampedViewButton(r, item, acts));
else {
var dl = iconButton('download', 'Download ' + label);
dl.addEventListener('click', function() {
dl.disabled = true;
window.location.href = fileURL(r);
toast('Download started');
setTimeout(function() { dl.disabled = false; }, 2000);
});
acts.appendChild(dl);
}
} else {
var raw = r.value == null ? '' : String(r.value);
var value = raw.trim();
tx.appendChild(el('div', 'v', value === '' ? '—' : displayValue(kind, value)));
if (value !== '') {
if (kind === 'phone') {
var call = el('a', 'act ok');
call.href = 'tel:' + value.replace(/[^\d+]/g, '');
call.setAttribute('aria-label', 'Call ' + value);
call.appendChild(svg('phone', 16));
call.appendChild(el('span', 'act-t', 'Call'));
acts.appendChild(call);
} else if (kind === 'email') {
acts.appendChild(iconLink('send', 'Write to ' + value, 'mailto:' + value, false));
} else if (kind === 'url') {
var href = webHref(value);
if (href) acts.appendChild(iconLink('external', 'Open ' + value, href, true));
}
acts.appendChild(copyButton(raw, label));
}
}
row.appendChild(tx);
row.appendChild(acts);
item.appendChild(row);
return item;
}

// A stamped file is fetched once: the one download token serves both the
// preview and the save, and the preview is shown from memory rather than by
// loading the file URL inline, so nothing uploaded ever renders from this origin.
function stampedViewButton(r, item, acts) {
var b = iconButton('eye', 'View ' + (r.label || r.filename || 'file'));
b.addEventListener('click', function() {
b.disabled = true;
b.textContent = '';
b.appendChild(el('span', 'spin'));
b.lastChild.style.display = 'block';
fetch(fileURL(r)).then(function(res) {
if (!res.ok) {
return res.json().then(function(j) { throw new Error((j && j.message) || 'This file couldn\'t be loaded.'); },
function() { throw new Error('This file couldn\'t be loaded.'); });
}
return res.blob();
}).then(function(blob) {
var ext = stampedTypes[blob.type];
if (!ext) throw new Error('This file couldn\'t be loaded.');
var url = URL.createObjectURL(blob);
var preview = el('div', 'preview');
if (blob.type === 'application/pdf') {
var frame = document.createElement('iframe');
frame.src = url;
frame.title = r.filename || 'file';
preview.appendChild(frame);
} else {
var img = document.createElement('img');
img.src = url;
img.alt = r.filename || 'file';
preview.appendChild(img);
}
item.appendChild(preview);
var save = iconLink('download', 'Save ' + (r.filename || 'file'), url, false);
save.download = String(r.filename || 'file').replace(/\.[^.]+$/, '') + ext;
acts.replaceChild(save, b);
}).catch(function(err) {
b.remove();
item.appendChild(el('div', 'err', err.message));
});
});
return b;
}

function watermarkOverlay(line) {
var overlay = el('div', 'wm-overlay');
var inner = el('div', 'wm-overlay-inner');
var phrase = (line + '        ').repeat(6);
for (var i = 0; i < 40; i++) {
inner.appendChild(el('div', '', i % 2 ? '    ' + phrase : phrase));
}
overlay.appendChild(inner);
return overlay;
}

var applicantKeys = ['full_name', 'email', 'phone', 'current_address', 'employer', 'occupation', 'net_income', 'move_in_date', 'household_size', 'pets'];

// A titled block of rows: the name above, the rows in one card below.
function makeSection(name, count, noun, action) {
var sec = el('section', 'sec');
var sh = el('div', 'sh');
sh.appendChild(el('span', 'sh-t', name));
var right = el('div', 'sh-r');
right.appendChild(el('span', '', count + ' ' + (count === 1 ? noun : noun + 's')));
if (action) right.appendChild(action);
sh.appendChild(right);
sec.appendChild(sh);
var card = el('div', 'card');
sec.appendChild(card);
sec.card = card;
return sec;
}

function archiveName(res, fallback) {
var cd = res.headers.get('content-disposition') || '';
var ext = /filename\*=UTF-8''([^;]+)/i.exec(cd);
if (ext) { try { return decodeURIComponent(ext[1]); } catch (e) {} }
var m = /filename="([^"]+)"/.exec(cd);
return m ? m[1] : fallback;
}

// The archive token is single-use like a file token, so a spent one is never
// retried: the viewer reloads for a fresh one.
function archiveButton(data, report) {
var label = 'Download all';
var b = el('button', 'act primary');
b.type = 'button';
b.id = 'download-all';
function show(text, icon) {
b.textContent = '';
if (icon) b.appendChild(svg(icon, 16));
b.appendChild(el('span', '', text));
}
show(label, 'download');
b.addEventListener('click', function() {
b.disabled = true;
show('Preparing…');
report('');
var u = '/api/public/links/' + encodeURIComponent(slug) + '/archive?dl=' + encodeURIComponent(data.archiveToken);
fetch(u).then(function(res) {
if (!res.ok) {
return res.json().then(function(j) { return j; }, function() { return {}; }).then(function(j) {
var msg = (j && j.message) || 'The archive couldn\'t be downloaded. Please try again.';
if (res.status === 401) msg = 'This download link has expired or has already been used. Reload the page to get a new one.';
show(label, 'download');
report(msg);
});
}
return res.blob().then(function(blob) {
var url = URL.createObjectURL(blob);
var a = document.createElement('a');
a.href = url;
a.download = archiveName(res, (data.label || data.slug || 'files') + '.zip');
document.body.appendChild(a);
a.click();
a.remove();
setTimeout(function() { URL.revokeObjectURL(url); }, 60000);
show('Downloaded', 'check');
toast('Archive downloaded');
});
}).catch(function() {
b.disabled = false;
show(label, 'download');
report('The server couldn\'t be reached. Please check your connection and try again.');
});
});
return b;
}

// reporter shows a message in a row of its own at the top of a card.
function reporter(card) {
var row = null;
return function(msg) {
if (!msg) { if (row) row.remove(); row = null; return; }
if (!row) {
row = el('div', 'err');
card.insertBefore(row, card.firstChild);
}
row.textContent = msg;
};
}

// Everything the application cards did not claim still renders here, so a
// record the layout does not know is never hidden from the landlord.
function renderApplication(out, records, data) {
var byKey = {};
records.forEach(function(r) {
if (r.key && r.type !== 'file' && !byKey[r.key]) byKey[r.key] = r;
});
var applicant = applicantKeys.map(function(k) { return byKey[k]; }).filter(Boolean);
// The applicant's own profile fields follow the ones every application has.
applicant = applicant.concat(records.filter(function(r) {
return r.type !== 'file' && r.key && r.key.indexOf('profile_') === 0;
}));
var documents = records.filter(function(r) { return r.type === 'file'; });
var taken = {};
applicant.concat(documents).forEach(function(r) { taken[r.id] = true; });

if (applicant.length) {
var who = makeSection('Applicant', applicant.length, 'item');
applicant.forEach(function(r) { who.card.appendChild(renderRecordItem(r)); });
out.appendChild(who);
}
if (documents.length) {
var report = null;
var action = data.archiveToken ? archiveButton(data, function(msg) { report(msg); }) : null;
var docs = makeSection('Documents', documents.length, 'file', action);
report = reporter(docs.card);
documents.forEach(function(r) { docs.card.appendChild(renderRecordItem(r)); });
out.appendChild(docs);
}
return records.filter(function(r) { return !taken[r.id]; });
}

function render(data) {
var out = document.getElementById('out');
out.textContent = '';
watermarkLine = data.watermark || '';

var rootRecords = data.records || [];
var sections = data.sections || [];
var isApplication = data.purpose === 'application';
var hasRootFile = rootRecords.some(function(r) { return r.type === 'file'; });
if (data.archiveToken && !(isApplication && hasRootFile)) {
var files = rootRecords.filter(function(r) { return r.type === 'file'; }).length;
var archive = el('div', 'card sec');
var bar = el('div', 'bar');
var tile = el('div', 'tile tone-neutral');
tile.appendChild(svg('archive', 20));
bar.appendChild(tile);
var tx = el('div', 'tx', files > 1 ? 'All ' + files + ' files, bundled as a ZIP archive' : 'All files, bundled as a ZIP archive');
bar.appendChild(tx);
bar.appendChild(archiveButton(data, reporter(archive)));
archive.appendChild(bar);
out.appendChild(archive);
}
var remaining = isApplication ? renderApplication(out, rootRecords, data) : rootRecords;

// A section arrives as the ids of its records; the records themselves come
// once, at the top level, and only those the share still grants.
var byId = {};
remaining.forEach(function(r) { if (r && r.id) byId[r.id] = r; });
var inSections = {};
sections.forEach(function(s) {
(s.records || []).forEach(function(id) { inSections[id] = true; });
});
var looseRecords = remaining.filter(function(r) { return !inSections[r.id]; });

sections.forEach(function(s) {
var secRecords = (s.records || []).map(function(id) { return byId[id]; }).filter(Boolean);
if (isApplication && !secRecords.length) return;
var sec = makeSection(s.name || 'Section', secRecords.length, 'item');
if (!secRecords.length) {
sec.card.appendChild(el('div', 'empty', 'This section is empty.'));
} else {
secRecords.forEach(function(r) { sec.card.appendChild(renderRecordItem(r)); });
}
out.appendChild(sec);
});

if (looseRecords.length > 0) {
var loose = makeSection(isApplication ? 'Further details' : (sections.length ? 'Other information' : 'Shared with you'), looseRecords.length, 'item');
looseRecords.forEach(function(r) { loose.card.appendChild(renderRecordItem(r)); });
out.appendChild(loose);
}

if (!rootRecords.length && !sections.length) {
var emptyCard = el('div', 'card sec');
emptyCard.appendChild(el('div', 'empty', 'This link doesn\'t contain any information yet.'));
out.appendChild(emptyCard);
}

// One after another, so the page reads top to bottom as it appears.
Array.prototype.forEach.call(out.children, function(c, i) {
c.style.animationDelay = Math.min(i * 70, 420) + 'ms';
});

if (watermarkLine) {
out.classList.add('wm-host');
out.appendChild(watermarkOverlay(watermarkLine));
}
}

function foldGate(gate) {
gate.style.maxHeight = gate.scrollHeight + 'px';
// Two frames: the height must be set before it can animate to zero.
requestAnimationFrame(function() {
requestAnimationFrame(function() { gate.classList.add('gone'); });
});
setTimeout(function() { gate.remove(); }, 600);
}

var btn = document.getElementById('reveal');
if (btn) {
btn.addEventListener('click', function() {
btn.disabled = true;
btn.classList.add('loading');
document.getElementById('reveal-t').textContent = 'Opening…';
fetch('/api/public/links/' + encodeURIComponent(slug), {
method: 'POST',
headers: { 'content-type': 'application/json' },
body: '{}'
})
.then(function(r) { return r.json().then(function(j) { return { ok: r.ok, body: j }; }); })
.then(function(res) {
var gate = document.getElementById('gate');
if (!res.ok) {
gate.textContent = '';
var c = el('div', 'callout bad');
c.appendChild(svg('alert', 22));
c.appendChild(el('div', '', (res.body && res.body.message) || 'This link is no longer available. The sender may have revoked it, or it may have expired.'));
gate.appendChild(c);
return;
}
foldGate(gate);
if (maxViews > 0) {
var vt = document.getElementById('views-text');
if (vt) vt.textContent = Math.min(viewCount + 1, maxViews) + ' of ' + maxViews + ' views used';
}
document.getElementById('strip').hidden = false;
render(res.body);
})
.catch(function() {
btn.disabled = false;
btn.classList.remove('loading');
document.getElementById('reveal-t').textContent = 'Try again';
var n = document.getElementById('capnote');
n.style.color = 'var(--bad)';
n.textContent = 'The server couldn\'t be reached. Please check your connection and try again.';
});
});
}

checkDNS();
})();
</script>
</body>
</html>`))

func linkStatusPage(re *core.RequestEvent, title, detail string, status int) error {
	var buf bytes.Buffer
	_ = statusTemplate.Execute(&buf, map[string]string{"Title": title, "Detail": detail})
	re.Response.Header().Set("Content-Type", "text/html; charset=utf-8")
	re.Response.Header().Set("Cache-Control", "no-store")
	re.Response.Header().Set("X-Content-Type-Options", "nosniff")
	re.Response.WriteHeader(status)
	_, _ = re.Response.Write(buf.Bytes())
	return nil
}

var statusTemplate = template.Must(template.New("status").Funcs(brandFuncs).Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<link rel="icon" type="image/svg+xml" href="{{logoLight}}" media="(prefers-color-scheme: light)">
<link rel="icon" type="image/svg+xml" href="{{logoDark}}" media="(prefers-color-scheme: dark)">
<title>{{.Title}} · Revoked</title>
<style>
:root {
--font-sans: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}
:root,
html[data-theme="light"] {
color-scheme: light;
--bg: #f8f9ff;
--surface: #f8f9ff;
--border: #c3c7cf;
--fg: #191c20;
--fg-muted: #42474e;
--primary: #35618e;
}
html[data-theme="dark"] {
color-scheme: dark;
--bg: #101418;
--surface: #101418;
--border: #42474e;
--fg: #e1e2e8;
--fg-muted: #c3c7cf;
--primary: #a0cafd;
}
@media (prefers-color-scheme: dark) {
html:not([data-theme="light"]) {
color-scheme: dark;
--bg: #101418;
--surface: #101418;
--border: #42474e;
--fg: #e1e2e8;
--fg-muted: #c3c7cf;
--primary: #a0cafd;
}
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
margin: 0;
background: var(--bg);
color: var(--fg);
font-family: var(--font-sans);
font-size: 14px;
line-height: 1.6;
}
header {
border-bottom: 1px solid var(--border);
background: var(--surface);
padding: 12px 20px;
}
.nav {
max-width: 600px;
margin: 0 auto;
display: flex;
align-items: center;
justify-content: space-between;
}
.brand {
display: flex;
align-items: center;
gap: 8px;
font-weight: 700;
font-size: 15px;
}
.brand-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--primary); }
.logo { width: 24px; height: 24px; border-radius: 6px; }
.logo-dark { display: none; }
html[data-theme="dark"] .logo-light { display: none; }
html[data-theme="dark"] .logo-dark { display: block; }
@media (prefers-color-scheme: dark) {
html:not([data-theme="light"]) .logo-light { display: none; }
html:not([data-theme="light"]) .logo-dark { display: block; }
}
main {
max-width: 480px;
margin: 12vh auto 0;
padding: 24px;
text-align: center;
background: var(--surface);
border: 1px solid var(--border);
border-radius: 12px;
}
h1 { font-size: 18px; font-weight: 600; margin-bottom: 8px; }
p { color: var(--fg-muted); font-size: 13px; }
a { color: var(--primary); text-decoration: none; }
a:hover { text-decoration: underline; }
</style>
</head>
<body>
<header>
<div class="nav">
<div class="brand">
<img class="logo logo-light" src="{{logoLight}}" alt="">
<img class="logo logo-dark" src="{{logoDark}}" alt="">
<span>Revoked</span>
</div>
</div>
</header>
<main>
<h1>{{.Title}}</h1>
<p>{{.Detail}}</p>
</main>
</body>
</html>`))
