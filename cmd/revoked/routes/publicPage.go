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
	Official         bool
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
		Official:         strings.EqualFold(root.Domain(), util.OfficialDomain),
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

var pageTemplate = template.Must(template.New("page").Funcs(brandFuncs).Parse(`{{define "heading"}}{{if eq .Purpose "application"}}Bewerbung{{if .Label}} · {{.Label}}{{end}}{{else if .Label}}{{.Label}}{{else}}Shared items{{end}}{{end}}<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<link rel="icon" type="image/svg+xml" href="{{logoLight}}" media="(prefers-color-scheme: light)">
<link rel="icon" type="image/svg+xml" href="{{logoDark}}" media="(prefers-color-scheme: dark)">
<title>{{template "heading" .}} · Revoked</title>
<style>` + pageTokens + `
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
background: var(--bg);
color: var(--fg);
font-family: var(--font-sans);
font-size: 16px;
line-height: 1.45;
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
.logo { width: 24px; height: 24px; border-radius: var(--radius-md); }
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

/* The head reads like the app's detail page: what this is, its name, and
   who it is from with how far that holds, in one line. */
.head { display: flex; flex-direction: column; gap: 6px; }
.eyebrow { font-size: 12px; font-weight: 600; letter-spacing: .06em; text-transform: uppercase; color: var(--fg-muted); }
.head h1 { font-size: 28px; font-weight: 650; line-height: 1.15; letter-spacing: -0.04em; overflow-wrap: anywhere; }
.trust { display: flex; flex-wrap: wrap; align-items: center; gap: 6px 8px; font-size: 14px; color: var(--fg-muted); margin-top: 2px; }
.trust b { color: var(--fg); font-weight: 600; }
.more {
margin-left: auto; border: 0; background: none; padding: 4px 0; cursor: pointer;
color: var(--fg-muted); font-size: 13px; text-decoration: underline; text-underline-offset: 3px;
}
.more:hover { color: var(--fg); }
.trust-note {
margin-top: 8px; padding: 10px 12px; font-size: 14px; line-height: 1.45;
border-left: 3px solid var(--warn); background: var(--warn-subtle); color: var(--warn);
}
.trust-note.bad { border-left-color: var(--bad); background: var(--bad-subtle); color: var(--bad); }
.meta { display: flex; flex-wrap: wrap; gap: 6px; }

/* Under the shared items: the share as a whole, kept or passed on. Rarely
   used, so quiet links rather than buttons competing with the values. */
.tools { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 0 16px; margin-top: -8px; }
.tool {
min-height: 36px; padding: 0 2px;
display: inline-flex; align-items: center; gap: 6px;
border: 0; background: none; color: var(--fg-muted);
font-size: 13px; cursor: pointer;
}
.tool span { text-decoration: underline; text-underline-offset: 3px; }
.tool:hover { color: var(--fg); }

footer { border-top: 1px solid var(--border); margin-top: 8px; }
.foot {
max-width: 640px; margin: 0 auto; padding: 14px 16px calc(24px + env(safe-area-inset-bottom));
display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: flex-start; justify-content: space-between;
font-size: 13px; color: var(--fg-muted);
}
.foot details { flex: 1 1 260px; }
.foot summary { cursor: pointer; list-style-position: inside; }
.foot details p { margin-top: 8px; line-height: 1.5; }
.foot a { color: var(--fg-muted); text-decoration: underline; text-underline-offset: 3px; }
.foot a:hover { color: var(--fg); }
.foot-links { display: flex; gap: 16px; }
.foot .trusted { flex: 1 0 100%; padding-top: 10px; border-top: 1px solid var(--border); font-size: 12px; }
.app-gate { display: flex; flex-direction: column; gap: 10px; }
.app-gate p { display: flex; gap: 10px; align-items: flex-start; color: var(--fg-muted); font-size: 14px; line-height: 1.5; }
.quiet {
width: 100%; min-height: 48px; display: flex; align-items: center; justify-content: center; gap: 8px;
border: 1px solid var(--control); color: var(--fg); font-weight: 600; font-size: 15px;
}
.quiet:hover { background: var(--surface-subtle); text-decoration: none; }

.card {
background: var(--card);
border: 1px solid var(--border);
border-radius: var(--radius-lg);
box-shadow: var(--shadow);
overflow: hidden;
}

.nav-actions { display: flex; align-items: center; gap: 8px; }
.app-btn {
display: inline-flex; align-items: center; justify-content: center; gap: 6px; height: 38px;
padding: 0 12px; border-radius: var(--radius-md); border: 1px solid var(--control);
background: var(--card); color: var(--fg); font-size: 14px; font-weight: 600; white-space: nowrap;
}
.app-btn:hover { background: var(--surface-subtle); text-decoration: none; }
.lang {
min-width: 38px; height: 38px; padding: 0 10px; border-radius: var(--radius-md); border: 1px solid var(--control);
background: var(--card); color: var(--fg); cursor: pointer;
font-size: 13px; font-weight: 650; letter-spacing: .04em;
}
.big-logo { width: 24px; height: 24px; }
@media (max-width: 420px) {
.app-btn { width: 38px; padding: 0; }
.app-btn-t { display: none; }
}
@media (max-width: 300px) { .brand-t { display: none; } }

/* Sender: one verdict, then each fact marked where it cannot be vouched for.
   Folded behind Details unless the verdict is a real danger. */
.sender { transition: border-color .3s, box-shadow .3s; }
/* While the server is checked only the button says so; the verdict and the
   server's badge arrive together with the answer. */
.sender[data-state="checking"] .verdict,
.sender[data-state="checking"] [data-dns] { display: none; }
.sender[data-state="checking"] .facts { border-top: 0; }
/* The verdict is the note under the title line; Details holds only the
   evidence behind it. */
.sender .verdict { display: none; }
.sender .facts { border-top: 0; }
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
padding: 3px 10px; border-radius: var(--radius-md);
font-size: 12px; font-weight: 500; white-space: nowrap;
background: var(--surface-subtle); color: var(--fg-muted);
}
.pill.ok { background: var(--ok-subtle); color: var(--ok); }
.pill.bad { background: var(--bad-subtle); color: var(--bad); }
.pill[hidden] { display: none; }
.strip { display: flex; flex-wrap: wrap; gap: 6px; }

/* The trust gate: the one decision on the page before anything loads. */
.gate {
padding: 0;
transition: opacity .3s var(--ease), transform .35s var(--ease), max-height .45s var(--ease),
padding .45s var(--ease), margin .45s var(--ease), border-width .45s;
}
.gate.gone { opacity: 0; transform: translateY(-6px) scale(.98); max-height: 0 !important; padding-top: 0; padding-bottom: 0; margin-bottom: -16px; border-width: 0; }
.callout {
display: flex; gap: 12px; align-items: flex-start;
padding: 14px; border-radius: var(--radius-md);
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
width: 100%; min-height: 54px; margin-top: 0;
border: 0; border-radius: var(--radius-md);
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

/* A button, not an input: the page collects nothing. */
.remember {
display: flex; align-items: flex-start; gap: 10px; width: 100%;
margin-top: 14px; padding: 2px 0; border: 0; background: none;
color: var(--fg); font: inherit; text-align: left; cursor: pointer;
}
.remember .box {
width: 18px; height: 18px; flex: none; margin-top: 1px;
border: 1.5px solid var(--control); border-radius: var(--radius-xs);
display: flex; align-items: center; justify-content: center; color: var(--primary-fg);
}
.remember[aria-checked="true"] .box { background: var(--primary); border-color: var(--primary); }
.remember .box svg { visibility: hidden; }
.remember[aria-checked="true"] .box svg { visibility: visible; }
.remember-t { font-size: 14px; font-weight: 500; line-height: 1.35; overflow-wrap: anywhere; }
.remember-d { display: block; font-size: 12px; font-weight: 400; color: var(--fg-muted); margin-top: 2px; }
.trusted {
display: flex; flex-wrap: wrap; align-items: center; gap: 4px 10px;
font-size: 13px; color: var(--fg-muted);
}
.trusted span { overflow-wrap: anywhere; }
.trusted .more { margin-left: 0; }


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
.rec { border-radius: var(--radius-md); display: flex; align-items: center; gap: 12px; padding: 12px 12px 12px 14px; min-height: 66px; }
.tile { width: 40px; height: 40px; border-radius: var(--radius-md); flex: none; display: flex; align-items: center; justify-content: center; }
.tone-neutral { background: var(--surface-subtle); color: var(--fg-muted); }
.tone-ok { background: var(--ok-subtle); color: var(--ok); }
.tone-primary { background: var(--primary-subtle); color: var(--primary); }
.tone-violet { background: var(--violet-subtle); color: var(--violet); }
.tone-warn { background: var(--warn-subtle); color: var(--warn); }
.tone-bad { background: var(--bad-subtle); color: var(--bad); }
.tx { flex: 1; min-width: 0; }
.lb { font-size: 12px; color: var(--fg-muted); line-height: 1.3; }
.v { font-size: 15px; line-height: 1.4; overflow-wrap: anywhere; white-space: pre-wrap; margin-top: 1px; }
.stamp { font-size: 12px; color: var(--fg-muted); line-height: 1.3; margin-top: 3px; }
.acts { display: flex; gap: 6px; flex: none; }
.ib {
width: 40px; height: 40px; border-radius: var(--radius-md);
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
height: 40px; padding: 0 14px; border-radius: var(--radius-md); border: 0;
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
margin: 0 12px 12px; border-radius: var(--radius-md); overflow: hidden;
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
.seal-note {
padding: 10px 12px; font-size: 14px; line-height: 1.45;
border-left: 3px solid var(--control); background: var(--surface-subtle); color: var(--fg-muted);
}
[hidden] { display: none !important; }

.toast {
position: fixed; left: 50%; bottom: calc(18px + env(safe-area-inset-bottom));
transform: translate(-50%, 16px); opacity: 0; pointer-events: none;
max-width: calc(100vw - 32px); z-index: 50;
display: flex; align-items: center; gap: 8px;
padding: 11px 16px; border-radius: var(--radius-md);
background: var(--fg); color: var(--bg);
font-size: 14px; font-weight: 500;
box-shadow: 0 8px 24px rgba(0, 0, 0, .18);
transition: opacity .25s var(--ease), transform .3s var(--ease);
}
.toast span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.toast.on { opacity: 1; transform: translate(-50%, 0); }

main { padding-bottom: calc(40px + env(safe-area-inset-bottom)); }
.theme {
width: 38px; height: 38px; border-radius: var(--radius-md); border: 1px solid var(--control);
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
<a class="brand" href="https://revoked.link" target="_blank" rel="noopener noreferrer" title="Learn more about Revoked at revoked.link" data-t-title="brand.title">
<img class="logo logo-light" src="{{logoLight}}" alt="">
<img class="logo logo-dark" src="{{logoDark}}" alt="">
<span class="brand-t">Revoked</span>
</a>
<div class="nav-actions">
{{if not (or .Gated .RequireHandshake)}}<a class="app-btn" href="{{.AppLink}}" title="Open in app" aria-label="Open in app" data-t-title="openInApp" data-t-aria="openInApp"><i data-i="external" data-s="16"></i><span class="app-btn-t" data-t="openInApp">Open in app</span></a>{{end}}
<button class="lang" type="button" id="lang-toggle">DE</button>
<button class="theme" type="button" id="theme-toggle" aria-label="Toggle visual theme"></button>
</div>
</div>
</header>

<main{{if eq .Purpose "application"}} data-purpose="application"{{end}}>

{{/* Who this is from and how far that holds, said once, in one line. The
     facts behind it fold out under Details, and fold out by themselves when
     they are a real danger. */}}
<div class="head">
<div class="eyebrow" data-t="{{if eq .Purpose "application"}}eyebrow.application{{else}}eyebrow.shared{{end}}">{{if eq .Purpose "application"}}Application{{else}}Shared with you{{end}}</div>
<h1 id="title">{{if eq .Purpose "application"}}<span data-t="heading.application">Bewerbung</span>{{if .Label}} · {{.Label}}{{end}}{{else if .Label}}{{.Label}}{{else}}<span data-t="heading.shared">Shared items</span>{{end}}</h1>
<div class="trust" id="trust">
{{if .SharerName}}<span><span data-t="from">From</span> <b>{{.SharerName}}</b></span>{{if .SharerRevoked}}<span class="pill bad"><i data-i="alert" data-s="13"></i><span data-t="pill.identityWithdrawn">Identity withdrawn</span></span>{{end}}
{{else}}<span class="pill warn"><i data-i="alert" data-s="13"></i><span data-t="pill.senderNotNamed">Sender not named</span></span>{{end}}
<span class="pill" id="server-pill"><span class="spin" style="display:block;width:11px;height:11px"></span><span data-t="checking">Checking {{.Domain}}</span></span>
{{if .Official}}<span class="pill ok" data-t="official" data-official hidden>Official</span>{{end}}
<button class="more" type="button" id="trust-more" aria-expanded="false" aria-controls="sender">Details</button>
</div>
<div class="trust-note" id="trust-note" role="status" hidden></div>
</div>

<section class="card sender" id="sender" data-state="checking" hidden>
<div class="verdict">
<div class="tile" id="verdict-tile"></div>
<div style="min-width: 0;">
<div class="verdict-t" id="verdict-t"></div>
<div class="verdict-d" id="verdict-d"></div>
</div>
</div>
<div class="facts">
<div class="fact" id="fact-server">
<span class="fact-k"><i data-i="server"></i><span data-t="fact.server">Server</span></span>
<span class="fact-v"><span class="fact-name">{{.Domain}}</span><span class="pill" data-dns><span data-t="fact.checking">Checking…</span></span></span>
</div>
<div class="fact{{if .SharerRevoked}} is-bad{{else if not .SharerName}} is-warn{{end}}" id="fact-sender">
<span class="fact-k"><i data-i="user"></i><span data-t="fact.sender">Sender</span></span>
<span class="fact-v">
{{if .SharerName}}<span class="fact-name">{{if .SharerRevoked}}<i data-i="alert" data-s="15"></i>{{end}}{{.SharerName}}</span>
{{if .SharerRevoked}}<span class="pill bad" data-t="fact.withdrawn">Withdrawn</span>{{else}}<span class="pill" id="sender-pill" data-t="fact.reported" data-t-title="fact.reported.title" title="This name is provided by the server. The Revoked app can verify the signature behind it.">Reported by server</span>{{end}}
{{else}}<span class="fact-name"><i data-i="alert" data-s="15"></i><span data-t="fact.notSpecified">Not specified</span></span><span class="pill warn" data-t="fact.unsigned">Unsigned</span>{{end}}
</span>
</div>
{{if .SharerPrint}}<div class="fact-note mono"><span data-t="fact.fingerprint">Key fingerprint</span> {{.SharerPrint}}</div>{{end}}
{{if .SharerRevoked}}<div class="fact-note bad-t" data-t="note.withdrawn">{{.Domain}} has withdrawn this sender's identity. The link was signed while the identity was valid; the domain no longer vouches for it.</div>
{{else if not .SharerName}}<div class="fact-note warn-t" data-t="note.unsigned">This link is not signed by a named person. Anyone with access to {{.Domain}} could have created it.</div>
{{else}}<div class="fact-note" data-t="note.reported">This name is reported by the server and cannot be confirmed by a browser. The Revoked app verifies the sender's signature.</div>{{end}}
</div>
</section>

{{if or .Gated .RequireHandshake}}
<div class="app-gate">
<p><i data-i="lock" data-s="18"></i>{{if .RequireHandshake}}<span data-t="gate.handshake">Protected by a verified identity. It is confirmed only in the Revoked app, which checks the server first.</span>{{else}}<span data-t="gate.password">Protected by a password. The password is entered only in the Revoked app, which checks the server first.</span>{{end}}</p>
<a href="{{.AppLink}}" class="big"><img class="logo logo-light big-logo" src="{{logoLight}}" alt=""><img class="logo logo-dark big-logo" src="{{logoDark}}" alt=""><span data-t="gate.open">Open in the Revoked app</span></a>
<a href="/app" class="quiet"><i data-i="download" data-s="16"></i><span data-t="gate.get">Get the app</span></a>
</div>
{{else}}
<div class="meta" id="strip" hidden>
{{if gt .MaxViews 0}}<span class="pill"><i data-i="eye" data-s="13"></i><span id="views-text">{{.ViewCount}} of {{.MaxViews}} views used</span></span>{{end}}
{{if .Watermarked}}<span class="pill"><i data-i="droplet" data-s="13"></i><span data-t="watermarked">Watermarked files</span></span>{{end}}
</div>

<div class="gate" id="gate">
{{/* Held until the sender check has an answer, so nobody opens the data before
     the page could say whether to trust it. */}}
<button class="big loading" id="reveal" disabled><span class="spin"></span><i class="big-ic" data-i="lock-open"></i><span id="reveal-t">Checking the server…</span></button>
<div class="fine" id="capnote">{{if gt .MaxViews 0}}Opening uses one of {{.MaxViews}} views ({{.ViewCount}} used so far).{{end}}{{if .Watermarked}} Downloaded files carry a watermark that traces them back to this link.{{end}}</div>
<button class="remember" type="button" role="checkbox" aria-checked="false" id="remember" hidden><span class="box"><i data-i="check" data-s="13"></i></span><span class="remember-t"><span data-t="remember.t">Trust {{.Domain}}</span><span class="remember-d" data-t="remember.d">Links from this domain open directly in this browser</span></span></button>
</div>

<div id="out"></div>
{{end}}

</main>

<footer>
<div class="foot">
<details>
<summary data-t="how">How this page works</summary>
<p data-t="how.1">{{if .SharerName}}{{.SharerName}}{{else}}The sender{{end}} shares this information through Revoked. Values are read from the sender's vault each time the page is opened, not copied when the link was sent.</p>
<p data-t="how.2">The sender can pause or revoke the link, after which it stops working. Copied or downloaded content remains with whoever saved it.</p>
</details>
<div class="foot-links">
<a href="https://revoked.link" target="_blank" rel="noopener noreferrer">revoked.link</a>
</div>
{{if not (or .Gated .RequireHandshake)}}<div class="trusted" id="trusted" hidden><span data-t="trusted">{{.Domain}} is trusted in this browser.</span><button class="more" type="button" id="untrust" data-t="untrust">Stop trusting</button></div>{{end}}
</div>
</footer>

<div class="toast" id="toast" role="status" aria-live="polite"><i data-i="check" data-s="16"></i><span id="toast-t"></span></div>

<script nonce="{{.Nonce}}">
(function(){
var slug={{.Slug}}, domain={{.Domain}}, pin={{.RootFingerprint}}, maxViews={{.MaxViews}}, viewCount={{.ViewCount}};
var sharerName={{.SharerName}}, watermarked={{.Watermarked}};

// ---- Language: English and German, as on the passkey page -----------------
// Both catalogues are here: the page loads nothing but its own origin. The
// server renders English; anything marked data-t is said again in the chosen
// language.
var STRINGS = {
en: {
'lang.label': 'DE', 'lang.switch': 'Auf Deutsch wechseln',
'theme.light': 'Switch to light theme', 'theme.dark': 'Switch to dark theme',
'brand.title': 'Revoked at revoked.link', 'openInApp': 'Open in app',
'eyebrow.shared': 'Shared with you', 'eyebrow.application': 'Application',
'heading.shared': 'Shared items', 'heading.application': 'Bewerbung',
'from': 'From', 'official': 'Official',
'pill.identityWithdrawn': 'Identity withdrawn', 'pill.senderNotNamed': 'Sender not named',
'checking': function() { return 'Checking ' + domain; },
'details': 'Details', 'details.hide': 'Hide details',
'fact.server': 'Server', 'fact.sender': 'Sender', 'fact.checking': 'Checking…',
'fact.withdrawn': 'Withdrawn', 'fact.reported': 'Reported by server',
'fact.reported.title': 'This name is provided by the server. The Revoked app can verify the signature behind it.',
'fact.notSpecified': 'Not specified', 'fact.unsigned': 'Unsigned', 'fact.fingerprint': 'Key fingerprint',
'note.withdrawn': function() { return domain + ' has withdrawn this sender\'s identity. The link was signed while the identity was valid; the domain no longer vouches for it.'; },
'note.unsigned': function() { return 'This link is not signed by a named person. Anyone with access to ' + domain + ' could have created it.'; },
'note.reported': 'This name is reported by the server and cannot be confirmed by a browser. The Revoked app verifies the sender\'s signature.',
'unconfirmed': 'Unconfirmed', 'unconfirmed.title': 'This name comes from a server that failed verification and cannot be relied on.',
'gate.handshake': 'Protected by a verified identity. It is confirmed only in the Revoked app, which checks the server first.',
'gate.password': 'Protected by a password. The password is entered only in the Revoked app, which checks the server first.',
'gate.open': 'Open in the Revoked app', 'gate.get': 'Get the app',
'views': function(used) { return used + ' of ' + maxViews + ' views used'; },
'watermarked': 'Watermarked files',
'reveal.checking': 'Checking the server…', 'reveal.open': 'Open shared information', 'reveal.anyway': 'Open anyway',
'reveal.opening': 'Opening…', 'reveal.retry': 'Retry',
'cap.views': function() { return 'Opening uses one of ' + maxViews + ' views (' + viewCount + ' used so far).'; },
'cap.watermark': 'Downloaded files carry a watermark that traces them back to this link.',
'cap.capped': 'Links with a view limit open only on request.',
'unreachable': 'The server could not be reached.',
'remember.t': function() { return 'Trust ' + domain; }, 'remember.d': 'Links from this domain open directly in this browser',
'trusted': function() { return domain + ' is trusted in this browser.'; }, 'untrust': 'Stop trusting',
'untrusted': function() { return domain + ' is no longer trusted'; },
'how': 'How this page works',
'how.1': function() { return (sharerName || 'The sender') + ' shares this information through Revoked. Values are read from the sender\'s vault each time the page is opened, not copied when the link was sent.'; },
'how.2': 'The sender can pause or revoke the link, after which it stops working. Copied or downloaded content remains with whoever saved it.',
'pill.ok': 'Verified', 'pill.spoofed': 'Spoofed', 'pill.unverified': 'Unverified', 'pill.local': 'Local',
'line.ok': function() { return domain + ' verified'; }, 'line.spoofed': function() { return domain + ': key mismatch'; },
'line.unverified': function() { return domain + ' not verified'; }, 'line.local': 'Local server',
'v.spoofed.t': 'Possible impersonation',
'v.spoofed.d': function() { return 'The key used by this server does not match the one published for ' + domain + '. The server may be impersonated; nothing on this page should be relied on.'; },
'v.unverified.t': 'Server not verified',
'v.unverified.d': function() { return domain + ' publishes no DNS record confirming its identity. Open this only if you expected it.'; },
'v.withdrawn.t': 'Sender no longer trusted',
'v.withdrawn.d': function() { return domain + ' has withdrawn the identity that signed this link.'; },
'v.local.t': 'Local server',
'v.local.d': 'This page is served from a local or private address and cannot be checked against public DNS records.',
'v.local.unsigned': ' The link is also not signed by a named person.',
'v.unknown.t': 'Server verified, sender unknown',
'v.unknown.d': function() { return 'No named person signed this link. Anyone with access to ' + domain + ' could have made it. Open it only if you expected it.'; },
'v.ok.t': 'Server verified',
'v.ok.d': function() { return 'The key used by ' + domain + ' matches the one published in its DNS records. The connection is to the genuine server.'; },
'dns.local': 'DNS verification is not available for local or private addresses.',
'dns.spoofed': 'This server\'s key does not match the one published in its DNS records.',
'dns.none': 'No DNS record confirms this server\'s key.',
'locked.incomplete': 'This link is incomplete',
'locked.incomplete.d': 'Some entries on this link are end-to-end encrypted. The key that opens them is the end of the link\'s address, after “#k=”, and it is missing here, for example because only part of the address was copied. The complete link opens them.',
'locked.replaced': 'The key of this link was replaced',
'locked.replaced.d': 'Some entries on this link are end-to-end encrypted, and the key in this address does not open them. It was replaced, or the address was changed on the way. The current link comes from the sender.',
'locked.unavailable': 'Encrypted · not available on this link right now',
'locked.unavailable.d': 'An encrypted entry was changed and has not been renewed for this link yet. Until then it is not shown, rather than an older version of it.',
'locked.insecure': 'Encrypted · opens over HTTPS or in the app',
'locked.insecure.d': 'Some entries on this link are end-to-end encrypted. A browser decrypts them only on a secure (HTTPS) connection; the Revoked app opens them as well.',
'locked.damaged': 'This entry could not be decrypted',
'locked.damaged.d': 'An encrypted entry on this link could not be decrypted: what the server sent does not match the key in this address.',
'yes': 'Yes', 'no': 'No', 'file': 'file', 'record': 'Record', 'contact': 'Contact',
'stamp.created': function(d) { return 'Created ' + d; }, 'stamp.updated': function(d) { return 'Updated ' + d; },
'download': function(l) { return 'Download ' + l; }, 'downloadStarted': 'Download started',
'call': 'Call', 'call.label': function(v) { return 'Call ' + v; },
'write': function(v) { return 'Write to ' + v; }, 'open.url': function(v) { return 'Open ' + v; },
'copy': function(l) { return 'Copy ' + l; },
'copied': function(v) { return 'Copied “' + v + '”'; },
'copyBlocked': 'Copying was blocked by the browser. The text can be selected and copied manually.',
'view': function(n) { return 'View ' + n; }, 'save': function(n) { return 'Save ' + n; },
'fileFailed': 'This file could not be loaded.',
'count.item': function(n) { return n + (n === 1 ? ' item' : ' items'); },
'count.file': function(n) { return n + (n === 1 ? ' file' : ' files'); },
'downloadAll': 'Download all', 'preparing': 'Preparing…', 'downloaded': 'Downloaded',
'archive.failed': 'The archive could not be downloaded.',
'archive.expired': 'This download link has expired or was already used. Reloading the page issues a new one.',
'archive.done': 'Archive downloaded',
'archive.all': function(n) { return n > 1 ? 'All ' + n + ' files, bundled as a ZIP archive' : 'All files, bundled as a ZIP archive'; },
'applicant': 'Applicant', 'documents': 'Documents',
'saveContact': 'Save as contact', 'contactSaved': 'Contact saved', 'downloadText': 'Download as text',
'section': 'Section', 'sectionEmpty': 'This section is empty.',
'furtherDetails': 'Further details', 'otherInformation': 'Other information', 'sharedInformation': 'Shared information',
'linkEmpty': 'This link contains no information yet.',
'linkGone': 'This link is no longer available. It may have been revoked or expired.'
},
de: {
'lang.label': 'EN', 'lang.switch': 'Switch to English',
'theme.light': 'Zum hellen Design wechseln', 'theme.dark': 'Zum dunklen Design wechseln',
'brand.title': 'Revoked auf revoked.link', 'openInApp': 'In App öffnen',
'eyebrow.shared': 'Mit Ihnen geteilt', 'eyebrow.application': 'Bewerbung',
'heading.shared': 'Geteilte Einträge', 'heading.application': 'Bewerbung',
'from': 'Von', 'official': 'Offiziell',
'pill.identityWithdrawn': 'Identität zurückgezogen', 'pill.senderNotNamed': 'Absender nicht genannt',
'checking': function() { return domain + ' wird geprüft'; },
'details': 'Details', 'details.hide': 'Details ausblenden',
'fact.server': 'Server', 'fact.sender': 'Absender', 'fact.checking': 'Wird geprüft…',
'fact.withdrawn': 'Zurückgezogen', 'fact.reported': 'Vom Server angegeben',
'fact.reported.title': 'Dieser Name wird vom Server angegeben. Die Revoked-App kann die zugehörige Signatur prüfen.',
'fact.notSpecified': 'Nicht angegeben', 'fact.unsigned': 'Nicht signiert', 'fact.fingerprint': 'Schlüssel-Fingerabdruck',
'note.withdrawn': function() { return domain + ' hat die Identität dieses Absenders zurückgezogen. Der Link wurde signiert, als die Identität noch gültig war; die Domain bürgt nicht mehr dafür.'; },
'note.unsigned': function() { return 'Dieser Link ist nicht von einer namentlich genannten Person signiert. Jede Person mit Zugang zu ' + domain + ' könnte ihn erstellt haben.'; },
'note.reported': 'Dieser Name wird vom Server angegeben und kann von einem Browser nicht bestätigt werden. Die Revoked-App prüft die Signatur des Absenders.',
'unconfirmed': 'Unbestätigt', 'unconfirmed.title': 'Dieser Name stammt von einem Server, der die Prüfung nicht bestanden hat, und ist nicht verlässlich.',
'gate.handshake': 'Durch eine verifizierte Identität geschützt. Sie wird nur in der Revoked-App bestätigt, die zuvor den Server prüft.',
'gate.password': 'Durch ein Passwort geschützt. Das Passwort wird nur in der Revoked-App eingegeben, die zuvor den Server prüft.',
'gate.open': 'In der Revoked-App öffnen', 'gate.get': 'App laden',
'views': function(used) { return used + ' von ' + maxViews + ' Aufrufen verbraucht'; },
'watermarked': 'Dateien mit Wasserzeichen',
'reveal.checking': 'Server wird geprüft…', 'reveal.open': 'Geteilte Informationen öffnen', 'reveal.anyway': 'Trotzdem öffnen',
'reveal.opening': 'Wird geöffnet…', 'reveal.retry': 'Erneut versuchen',
'cap.views': function() { return 'Das Öffnen verbraucht einen von ' + maxViews + ' Aufrufen (bisher ' + viewCount + ' verbraucht).'; },
'cap.watermark': 'Heruntergeladene Dateien tragen ein Wasserzeichen, das sie diesem Link zuordnet.',
'cap.capped': 'Links mit Aufrufbegrenzung öffnen nur auf Anforderung.',
'unreachable': 'Der Server ist nicht erreichbar.',
'remember.t': function() { return domain + ' vertrauen'; }, 'remember.d': 'Links dieser Domain öffnen in diesem Browser direkt',
'trusted': function() { return domain + ' ist in diesem Browser als vertrauenswürdig gespeichert.'; }, 'untrust': 'Nicht mehr vertrauen',
'untrusted': function() { return domain + ' ist nicht mehr vertrauenswürdig'; },
'how': 'Funktionsweise dieser Seite',
'how.1': function() { return (sharerName || 'Der Absender') + ' teilt diese Informationen über Revoked. Die Werte werden bei jedem Öffnen der Seite aus dem Tresor des Absenders gelesen, nicht beim Versenden des Links kopiert.'; },
'how.2': 'Der Absender kann den Link pausieren oder widerrufen; danach funktioniert er nicht mehr. Kopierte oder heruntergeladene Inhalte verbleiben bei der Person, die sie gespeichert hat.',
'pill.ok': 'Verifiziert', 'pill.spoofed': 'Gefälscht', 'pill.unverified': 'Nicht verifiziert', 'pill.local': 'Lokal',
'line.ok': function() { return domain + ' verifiziert'; }, 'line.spoofed': function() { return domain + ': Schlüssel stimmt nicht überein'; },
'line.unverified': function() { return domain + ' nicht verifiziert'; }, 'line.local': 'Lokaler Server',
'v.spoofed.t': 'Mögliche Fälschung',
'v.spoofed.d': function() { return 'Der Schlüssel dieses Servers stimmt nicht mit dem für ' + domain + ' veröffentlichten überein. Der Server wird möglicherweise imitiert; auf den Inhalt dieser Seite ist kein Verlass.'; },
'v.unverified.t': 'Server nicht verifiziert',
'v.unverified.d': function() { return domain + ' veröffentlicht keinen DNS-Eintrag, der seine Identität bestätigt. Nur öffnen, wenn dieser Link erwartet wurde.'; },
'v.withdrawn.t': 'Absender nicht mehr vertrauenswürdig',
'v.withdrawn.d': function() { return domain + ' hat die Identität zurückgezogen, mit der dieser Link signiert wurde.'; },
'v.local.t': 'Lokaler Server',
'v.local.d': 'Diese Seite wird von einer lokalen oder privaten Adresse ausgeliefert und kann nicht mit öffentlichen DNS-Einträgen abgeglichen werden.',
'v.local.unsigned': ' Der Link ist außerdem nicht von einer namentlich genannten Person signiert.',
'v.unknown.t': 'Server verifiziert, Absender unbekannt',
'v.unknown.d': function() { return 'Keine namentlich genannte Person hat diesen Link signiert. Jede Person mit Zugang zu ' + domain + ' könnte ihn erstellt haben. Nur öffnen, wenn dieser Link erwartet wurde.'; },
'v.ok.t': 'Server verifiziert',
'v.ok.d': function() { return 'Der Schlüssel von ' + domain + ' stimmt mit dem in seinen DNS-Einträgen veröffentlichten überein. Die Verbindung besteht zum echten Server.'; },
'dns.local': 'Für lokale oder private Adressen ist keine DNS-Prüfung möglich.',
'dns.spoofed': 'Der Schlüssel dieses Servers stimmt nicht mit dem in seinen DNS-Einträgen veröffentlichten überein.',
'dns.none': 'Kein DNS-Eintrag bestätigt den Schlüssel dieses Servers.',
'locked.incomplete': 'Dieser Link ist unvollständig',
'locked.incomplete.d': 'Einige Einträge dieses Links sind Ende-zu-Ende-verschlüsselt. Der Schlüssel dazu ist das Ende der Linkadresse nach „#k=“ und fehlt hier, etwa weil nur ein Teil der Adresse kopiert wurde. Der vollständige Link öffnet sie.',
'locked.replaced': 'Der Schlüssel dieses Links wurde ersetzt',
'locked.replaced.d': 'Einige Einträge dieses Links sind Ende-zu-Ende-verschlüsselt, und der Schlüssel in dieser Adresse öffnet sie nicht. Er wurde ersetzt, oder die Adresse wurde unterwegs verändert. Der aktuelle Link kommt vom Absender.',
'locked.unavailable': 'Verschlüsselt · auf diesem Link derzeit nicht verfügbar',
'locked.unavailable.d': 'Ein verschlüsselter Eintrag wurde geändert und für diesen Link noch nicht erneuert. Bis dahin wird er nicht angezeigt, statt einer älteren Fassung.',
'locked.insecure': 'Verschlüsselt · öffnet über HTTPS oder in der App',
'locked.insecure.d': 'Einige Einträge dieses Links sind Ende-zu-Ende-verschlüsselt. Ein Browser entschlüsselt sie nur über eine sichere (HTTPS-)Verbindung; die Revoked-App öffnet sie ebenfalls.',
'locked.damaged': 'Dieser Eintrag konnte nicht entschlüsselt werden',
'locked.damaged.d': 'Ein verschlüsselter Eintrag dieses Links konnte nicht entschlüsselt werden: Die Antwort des Servers passt nicht zum Schlüssel in dieser Adresse.',
'yes': 'Ja', 'no': 'Nein', 'file': 'Datei', 'record': 'Eintrag', 'contact': 'Kontakt',
'stamp.created': function(d) { return 'Erstellt am ' + d; }, 'stamp.updated': function(d) { return 'Aktualisiert am ' + d; },
'download': function(l) { return l + ' herunterladen'; }, 'downloadStarted': 'Download gestartet',
'call': 'Anrufen', 'call.label': function(v) { return v + ' anrufen'; },
'write': function(v) { return 'E-Mail an ' + v; }, 'open.url': function(v) { return v + ' öffnen'; },
'copy': function(l) { return l + ' kopieren'; },
'copied': function(v) { return '„' + v + '“ kopiert'; },
'copyBlocked': 'Der Browser hat das Kopieren blockiert. Der Text lässt sich markieren und manuell kopieren.',
'view': function(n) { return n + ' anzeigen'; }, 'save': function(n) { return n + ' speichern'; },
'fileFailed': 'Diese Datei konnte nicht geladen werden.',
'count.item': function(n) { return n + (n === 1 ? ' Eintrag' : ' Einträge'); },
'count.file': function(n) { return n + (n === 1 ? ' Datei' : ' Dateien'); },
'downloadAll': 'Alle herunterladen', 'preparing': 'Wird vorbereitet…', 'downloaded': 'Heruntergeladen',
'archive.failed': 'Das Archiv konnte nicht heruntergeladen werden.',
'archive.expired': 'Dieser Download-Link ist abgelaufen oder wurde bereits verwendet. Ein Neuladen der Seite erzeugt einen neuen.',
'archive.done': 'Archiv heruntergeladen',
'archive.all': function(n) { return n > 1 ? 'Alle ' + n + ' Dateien als ZIP-Archiv' : 'Alle Dateien als ZIP-Archiv'; },
'applicant': 'Persönliche Angaben', 'documents': 'Unterlagen',
'saveContact': 'Als Kontakt speichern', 'contactSaved': 'Kontakt gespeichert', 'downloadText': 'Als Text herunterladen',
'section': 'Bereich', 'sectionEmpty': 'Dieser Bereich ist leer.',
'furtherDetails': 'Weitere Angaben', 'otherInformation': 'Weitere Informationen', 'sharedInformation': 'Geteilte Informationen',
'linkEmpty': 'Dieser Link enthält noch keine Informationen.',
'linkGone': 'Dieser Link ist nicht mehr verfügbar. Er wurde möglicherweise widerrufen oder ist abgelaufen.'
}
};
// The key the web tools and the passkey page use, so one choice holds across
// this origin.
var LANG_KEY = 'revoked.web.locale';
var lang = (function() {
try {
var saved = localStorage.getItem(LANG_KEY);
if (saved === 'en' || saved === 'de') return saved;
} catch (e) {}
var langs = navigator.languages || [navigator.language || ''];
for (var i = 0; i < langs.length; i++) if (/^de\b/i.test(langs[i])) return 'de';
return 'en';
})();
function t(key) {
var v = STRINGS[lang][key];
if (v === undefined) v = STRINGS.en[key];
if (typeof v === 'function') return v.apply(null, Array.prototype.slice.call(arguments, 1));
return v === undefined ? key : v;
}
// English readers keep their own regional format; German is German.
function locale() {
if (lang === 'de') return 'de-DE';
var nav = navigator.language || 'en';
return /^en\b/i.test(nav) ? nav : 'en';
}

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
themeToggle.setAttribute('aria-label', isDark() ? t('theme.light') : t('theme.dark'));
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

var SERVER_PILLS = { ok: 'ok', spoofed: 'bad', unverified: 'bad', local: '' };

function verdictFor(server) {
if (server === 'spoofed') return ['bad', t('v.spoofed.t'), t('v.spoofed.d')];
// No record proves nothing either way, so it is a caution, not an alarm;
// a record that does not match is.
if (server === 'unverified') return ['warn', t('v.unverified.t'), t('v.unverified.d')];
if (signer === 'withdrawn') return ['bad', t('v.withdrawn.t'), t('v.withdrawn.d')];
if (server === 'local') return [signer === 'none' ? 'warn' : 'neutral', t('v.local.t'),
t('v.local.d') + (signer === 'none' ? t('v.local.unsigned') : '')];
if (signer === 'none') return ['warn', t('v.unknown.t'), t('v.unknown.d')];
return ['ok', t('v.ok.t'), t('v.ok.d')];
}

var serverState = null, serverTitle = '';
function setServer(server, titleKey) {
serverState = server;
serverTitle = titleKey || '';
paintServer();
var v = verdictFor(server);
// A real danger shows its evidence without being asked.
if (v[0] === 'bad') setDetails(true);

// The check has an answer, so the reader can now decide.
var reveal = document.getElementById('reveal');
if (reveal) {
reveal.disabled = false;
reveal.classList.remove('loading');
setReveal(v[0] === 'warn' || v[0] === 'bad' ? 'reveal.anyway' : 'reveal.open');
// Trust is in the domain, so an unnamed sender does not void it; a server
// that fails its check or a withdrawn sender does.
offerTrust((server === 'ok' || server === 'local') && signer !== 'withdrawn');
}
}

function paintServer() {
var server = serverState;
if (!server) return;
var title = serverTitle ? t(serverTitle) : '';
var pill = SERVER_PILLS[server];
Array.prototype.forEach.call(document.querySelectorAll('[data-dns]'), function(n) {
n.className = 'pill' + (pill ? ' ' + pill : '');
n.textContent = '';
if (server === 'ok') n.appendChild(svg('check', 13));
n.appendChild(document.createTextNode(t('pill.' + server)));
if (title) n.title = title;
});
// Only once DNS confirms the key: a dev server configured with the official
// domain is not the official server.
var official = document.querySelector('[data-official]');
if (official) official.hidden = server !== 'ok';

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
senderPill.setAttribute('data-t', 'unconfirmed');
senderPill.setAttribute('data-t-title', 'unconfirmed.title');
senderPill.textContent = t('unconfirmed');
senderPill.title = t('unconfirmed.title');
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

// The one-line summary under the title.
var SERVER_LINE = {
ok: ['ok', 'check'],
spoofed: ['bad', 'alert'],
unverified: ['warn', 'alert'],
local: ['', 'server']
};
var line = SERVER_LINE[server];
var sp = document.getElementById('server-pill');
sp.className = 'pill' + (line[0] ? ' ' + line[0] : '');
sp.textContent = '';
sp.appendChild(svg(line[1], 13));
sp.appendChild(document.createTextNode(t('line.' + server)));
if (title) sp.title = title;

// Said under the line only when there is something to weigh before opening.
var note = document.getElementById('trust-note');
note.hidden = !(v[0] === 'warn' || v[0] === 'bad');
note.classList.toggle('bad', v[0] === 'bad');
note.textContent = v[2];
}

var revealKey = 'reveal.checking';
function setReveal(key) {
revealKey = key;
var n = document.getElementById('reveal-t');
if (n) n.textContent = t(key);
}

// ---- Trusted domain ----------------------------------------------------------
// Kept in this origin's storage, so a look-alike domain never inherits it. It
// names the server key it was given for: trust never outvotes a failed check
// or a rotated key.
var TRUST_KEY = 'revoked_trusted_domains';
function trustMap() {
try { var m = JSON.parse(localStorage.getItem(TRUST_KEY) || '{}'); return m && typeof m === 'object' ? m : {}; }
catch (e) { return {}; }
}
function isTrusted() { return trustMap()[domain] === String(pin); }
function setTrusted(on) {
var m = trustMap();
if (on) m[domain] = String(pin); else delete m[domain];
try { localStorage.setItem(TRUST_KEY, JSON.stringify(m)); } catch (e) {}
document.getElementById('trusted').hidden = !on;
remember.hidden = on || !trustable;
remember.setAttribute('aria-checked', 'false');
if (!on) { capState.capped = false; paintCap(); }
}

var capState = { capped: false, unreachable: false };
function paintCap() {
var cap = document.getElementById('capnote');
if (!cap) return;
if (capState.unreachable) {
cap.style.color = 'var(--bad)';
cap.textContent = t('unreachable');
return;
}
var parts = [];
if (maxViews > 0) parts.push(t('cap.views'));
if (watermarked) parts.push(t('cap.watermark'));
if (capState.capped) parts.push(t('cap.capped'));
cap.textContent = parts.join(' ');
}

var remember = document.getElementById('remember');
var autoOpened = false, trustable = false;
function offerTrust(clean) {
if (!remember) return;
trustable = clean;
var trusted = isTrusted();
remember.hidden = !clean || trusted;
document.getElementById('trusted').hidden = !trusted;
// A capped link spends a view on opening, so that stays the reader's click.
if (clean && trusted && maxViews > 0 && !opening) {
capState.capped = true;
paintCap();
}
if (clean && trusted && maxViews === 0 && !autoOpened && !opening) {
autoOpened = true;
document.getElementById('reveal').click();
}
}
if (remember) {
remember.addEventListener('click', function() {
remember.setAttribute('aria-checked', remember.getAttribute('aria-checked') === 'true' ? 'false' : 'true');
});
document.getElementById('untrust').addEventListener('click', function() {
setTrusted(false);
toast(t('untrusted'));
});
}

function setDetails(open) {
var card = document.getElementById('sender');
var more = document.getElementById('trust-more');
card.hidden = !open;
more.setAttribute('aria-expanded', open ? 'true' : 'false');
more.textContent = open ? t('details.hide') : t('details');
}
document.getElementById('trust-more').addEventListener('click', function() {
setDetails(document.getElementById('sender').hidden);
});

function checkDNS() {
var d = String(domain || '');
// Local/dev hosts have no public DNS record to pin against.
var isLocal = d === '' || d === 'localhost' || d.indexOf('.') === -1 ||
d.indexOf(':') !== -1 || /^\d+\.\d+\.\d+\.\d+$/.test(d) ||
/\.(localhost|local|test|internal)$/i.test(d);
if (isLocal) {
setServer('local', 'dns.local');
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
else setServer('spoofed', 'dns.spoofed');
return;
}
}
}).catch(function(){});
});
setTimeout(function() {
if (done) return;
setServer('unverified', 'dns.none');
}, 5000);
}

` + pageSealingScript + `
var linkKey = sealLinkKeyFrom(location.hash);

// The way into the app is rendered by the server, which never sees the key,
// so it is added here: the app then opens the same entries.
function keyAppLinks() {
Array.prototype.forEach.call(document.querySelectorAll('a[href^="revoked://s/"]'), function(a) {
var base = a.getAttribute('href').split('#')[0];
a.setAttribute('href', linkKey ? base + '#k=' + sealKeyText(linkKey) : base);
});
}
keyAppLinks();

// Said in place of a value that stays closed, and once above the entries.
var LOCKED = { incomplete: true, replaced: true, unavailable: true, insecure: true, damaged: true };

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
if (/^true$/i.test(v)) return t('yes');
if (/^false$/i.test(v)) return t('no');
}
if (kind === 'date') {
var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
try {
if (m) return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3])).toLocaleDateString(locale(), { dateStyle: 'long', timeZone: 'UTC' });
var d = new Date(v);
if (!isNaN(d)) return d.toLocaleString(locale(), { dateStyle: 'medium', timeStyle: 'short' });
} catch (e) {}
}
if (kind === 'number' && /^-?\d+(\.\d+)?$/.test(v)) {
var num = Number(v);
if (isFinite(num) && Math.abs(num) < 1e15) return num.toLocaleString(locale());
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
var b = iconButton('copy', t('copy', label));
var timer = null;
b.addEventListener('click', function() {
copyText(value).then(function() {
b.classList.add('done');
b.textContent = '';
b.appendChild(svg('check'));
toast(t('copied', value.length > 32 ? value.slice(0, 32) + '…' : value));
clearTimeout(timer);
timer = setTimeout(function() {
b.classList.remove('done');
b.textContent = '';
b.appendChild(svg('copy'));
}, 1500);
}, function() { toast(t('copyBlocked')); });
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
var meta = r.locked ? { icon: 'lock', tone: 'neutral' } : KINDS[kind];
var label = r.label || r.key || t('record');

var tile = el('div', 'tile tone-' + meta.tone);
tile.appendChild(svg(meta.icon, 20));
row.appendChild(tile);

var tx = el('div', 'tx');
tx.appendChild(el('div', 'lb', label));
if (r.key) tx.title = r.key;
var acts = el('div', 'acts');

if (r.type === 'file') {
tx.appendChild(el('div', 'v', (r.filename || t('file')) + ' · ' + fmtBytes(r.size || 0)));
if (watermarkLine) acts.appendChild(stampedViewButton(r, item, acts));
else {
var dl = iconButton('download', t('download', label));
dl.addEventListener('click', function() {
dl.disabled = true;
window.location.href = fileURL(r);
toast(t('downloadStarted'));
setTimeout(function() { dl.disabled = false; }, 2000);
});
acts.appendChild(dl);
}
} else if (r.locked) {
// Encrypted and not opened here: the row says why in place of a value, and
// never shows an older one.
tx.appendChild(el('div', 'v muted', t('locked.' + (LOCKED[r.locked] ? r.locked : 'damaged'))));
} else {
var raw = r.value == null ? '' : String(r.value);
var value = raw.trim();
tx.appendChild(el('div', 'v', value === '' ? '—' : displayValue(kind, value)));
if (value !== '') {
if (kind === 'phone') {
var call = el('a', 'act ok');
call.href = 'tel:' + value.replace(/[^\d+]/g, '');
call.setAttribute('aria-label', t('call.label', value));
call.appendChild(svg('phone', 16));
call.appendChild(el('span', 'act-t', t('call')));
acts.appendChild(call);
} else if (kind === 'email') {
acts.appendChild(iconLink('send', t('write', value), 'mailto:' + value, false));
} else if (kind === 'url') {
var href = webHref(value);
if (href) acts.appendChild(iconLink('external', t('open.url', value), href, true));
}
acts.appendChild(copyButton(raw, label));
}
}
var stamp = stampFor(r);
if (stamp) tx.appendChild(el('div', 'stamp', stamp));
row.appendChild(tx);
row.appendChild(acts);
item.appendChild(row);
return item;
}

function parseStamp(v) {
if (!v) return null;
var d = new Date(String(v).replace(' ', 'T'));
return isNaN(d) ? null : d;
}

// Created and updated are written together on creation, a few milliseconds
// apart at most, so anything closer than a second was never changed.
function stampFor(r) {
var created = parseStamp(r.created), updated = parseStamp(r.updated);
var changed = updated && (!created || updated - created > 1000);
var at = changed ? updated : created;
if (!at) return '';
var text = at.toLocaleString(locale(), { dateStyle: 'medium', timeStyle: 'short' });
return t(changed ? 'stamp.updated' : 'stamp.created', text);
}

// A stamped file is fetched once: the one download token serves both the
// preview and the save, and the preview is shown from memory rather than by
// loading the file URL inline, so nothing uploaded ever renders from this origin.
function stampedViewButton(r, item, acts) {
var b = iconButton('eye', t('view', r.label || r.filename || t('file')));
b.addEventListener('click', function() {
b.disabled = true;
b.textContent = '';
b.appendChild(el('span', 'spin'));
b.lastChild.style.display = 'block';
fetch(fileURL(r)).then(function(res) {
if (!res.ok) {
return res.json().then(function(j) { throw new Error((j && j.message) || t('fileFailed')); },
function() { throw new Error(t('fileFailed')); });
}
return res.blob();
}).then(function(blob) {
var ext = stampedTypes[blob.type];
if (!ext) throw new Error(t('fileFailed'));
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
var save = iconLink('download', t('save', r.filename || t('file')), url, false);
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
right.appendChild(el('span', '', t('count.' + noun, count)));
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
var label = t('downloadAll');
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
show(t('preparing'));
report('');
var u = '/api/public/links/' + encodeURIComponent(slug) + '/archive?dl=' + encodeURIComponent(data.archiveToken);
fetch(u).then(function(res) {
if (!res.ok) {
return res.json().then(function(j) { return j; }, function() { return {}; }).then(function(j) {
var msg = (j && j.message) || t('archive.failed');
if (res.status === 401) msg = t('archive.expired');
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
show(t('downloaded'), 'check');
toast(t('archive.done'));
});
}).catch(function() {
b.disabled = false;
show(label, 'download');
report(t('unreachable'));
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
var who = makeSection(t('applicant'), applicant.length, 'item');
applicant.forEach(function(r) { who.card.appendChild(renderRecordItem(r)); });
out.appendChild(who);
}
if (documents.length) {
var report = null;
var action = data.archiveToken ? archiveButton(data, function(msg) { report(msg); }) : null;
var docs = makeSection(t('documents'), documents.length, 'file', action);
report = reporter(docs.card);
documents.forEach(function(r) { docs.card.appendChild(renderRecordItem(r)); });
out.appendChild(docs);
}
return records.filter(function(r) { return !taken[r.id]; });
}

// ---- The share as a whole -------------------------------------------------
// Built here from what was already opened: fetching the share again in another
// format would spend another view.
function vcEscape(v) {
return String(v).replace(/\\/g, '\\\\').replace(/\n/g, '\\n').replace(/([,;])/g, '\\$1');
}
function vcard(data, records) {
var lines = ['BEGIN:VCARD', 'VERSION:3.0'];
var name = '', notes = [], any = false;
records.forEach(function(r) {
if (r.type === 'file' || r.value == null) return;
var v = String(r.value).trim();
if (!v) return;
var kind = kindOf(r), label = r.label || r.key || '';
if (kind === 'person' && !name) { name = v; return; }
if (kind === 'phone') { lines.push('TEL:' + vcEscape(v)); any = true; return; }
if (kind === 'email') { lines.push('EMAIL:' + vcEscape(v)); any = true; return; }
if (kind === 'url') { lines.push('URL:' + vcEscape(v)); any = true; return; }
if (kind === 'place') { lines.push('ADR:;;' + vcEscape(v) + ';;;;'); any = true; return; }
if (kind === 'work') { lines.push('ORG:' + vcEscape(v)); any = true; return; }
notes.push(label + ': ' + displayValue(kind, v));
});
if (!name && !any) return null;
// N is required by the format; the name is given whole, as it was shared.
lines.splice(2, 0, 'N:' + vcEscape(name || data.label || t('contact')) + ';;;;', 'FN:' + vcEscape(name || data.label || t('contact')));
if (notes.length) lines.push('NOTE:' + vcEscape(notes.join('\n')));
lines.push('END:VCARD');
return lines.join('\r\n') + '\r\n';
}
function plainText(data, records) {
var out = [(data.label || t('sharedInformation')), ''];
records.forEach(function(r) {
if (r.type === 'file' || r.value == null) return;
var kind = kindOf(r);
out.push((r.label || r.key || t('record')) + ': ' + displayValue(kind, String(r.value).trim()));
});
return out.join('\n') + '\n';
}
function saveBlob(text, type, filename) {
var url = URL.createObjectURL(new Blob([text], { type: type }));
var a = document.createElement('a');
a.href = url;
a.download = filename;
document.body.appendChild(a);
a.click();
a.remove();
setTimeout(function() { URL.revokeObjectURL(url); }, 60000);
}
function fileBase(data) {
return String(data.label || data.slug || 'shared').replace(/[\\\/:*?"<>|]+/g, ' ').trim() || 'shared';
}
function toolsFor(data, records) {
var values = records.filter(function(r) { return r.type !== 'file' && r.value != null && String(r.value).trim(); });
if (!values.length) return null;
var row = el('div', 'tools sec');
var card = vcard(data, records);
if (card) {
var c = el('button', 'tool');
c.type = 'button';
c.appendChild(svg('user', 16));
c.appendChild(el('span', '', t('saveContact')));
c.addEventListener('click', function() {
saveBlob(card, 'text/vcard', fileBase(data) + '.vcf');
toast(t('contactSaved'));
});
row.appendChild(c);
}
var d = el('button', 'tool');
d.type = 'button';
d.appendChild(svg('download', 16));
d.appendChild(el('span', '', t('downloadText')));
d.addEventListener('click', function() {
saveBlob(plainText(data, records), 'text/plain;charset=utf-8', fileBase(data) + '.txt');
toast(t('downloaded'));
});
row.appendChild(d);
return row;
}

function render(data) {
var out = document.getElementById('out');
out.textContent = '';
watermarkLine = data.watermark || '';

var rootRecords = data.records || [];
var sections = data.sections || [];
var isApplication = data.purpose === 'application';

// Why encrypted entries stay closed, once, ahead of the rows that say it.
var closed = {};
rootRecords.forEach(function(r) { if (r && r.locked) closed[LOCKED[r.locked] ? r.locked : 'damaged'] = true; });
Object.keys(LOCKED).forEach(function(why) {
if (closed[why]) out.appendChild(el('div', 'seal-note sec', t('locked.' + why + '.d')));
});
var hasRootFile = rootRecords.some(function(r) { return r.type === 'file'; });
if (data.archiveToken && !(isApplication && hasRootFile)) {
var files = rootRecords.filter(function(r) { return r.type === 'file'; }).length;
var archive = el('div', 'card sec');
var bar = el('div', 'bar');
var tile = el('div', 'tile tone-neutral');
tile.appendChild(svg('archive', 20));
bar.appendChild(tile);
var tx = el('div', 'tx', t('archive.all', files));
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
var sec = makeSection(s.name || t('section'), secRecords.length, 'item');
if (!secRecords.length) {
sec.card.appendChild(el('div', 'empty', t('sectionEmpty')));
} else {
secRecords.forEach(function(r) { sec.card.appendChild(renderRecordItem(r)); });
}
out.appendChild(sec);
});

if (looseRecords.length > 0) {
var loose = makeSection(isApplication ? t('furtherDetails') : (sections.length ? t('otherInformation') : t('sharedInformation')), looseRecords.length, 'item');
looseRecords.forEach(function(r) { loose.card.appendChild(renderRecordItem(r)); });
out.appendChild(loose);
}

if (!rootRecords.length && !sections.length) {
var emptyCard = el('div', 'card sec');
emptyCard.appendChild(el('div', 'empty', t('linkEmpty')));
out.appendChild(emptyCard);
} else {
var tools = toolsFor(data, rootRecords);
if (tools) out.appendChild(tools);
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

// What the server returned, kept as it came: a corrected address opens the
// same answer again without spending another view.
var resolved = null;
function showShare() {
var data = resolved;
return sealOpenShare(data, linkKey).then(function(opened) {
if (data === resolved) render(opened);
});
}
window.addEventListener('hashchange', function() {
linkKey = sealLinkKeyFrom(location.hash);
keyAppLinks();
if (resolved) showShare();
});

var btn = document.getElementById('reveal');
var opening = false;
if (btn) {
btn.addEventListener('click', function() {
if (opening) return;
opening = true;
if (remember && !remember.hidden && remember.getAttribute('aria-checked') === 'true') setTrusted(true);
btn.disabled = true;
btn.classList.add('loading');
setReveal('reveal.opening');
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
gate.appendChild(el('div', 'trust-note bad', (res.body && res.body.message) || t('linkGone')));
return;
}
foldGate(gate);
viewsUsed = Math.min(viewCount + 1, maxViews);
paintViews();
document.getElementById('strip').hidden = false;
resolved = res.body;
return showShare();
})
.catch(function() {
opening = false;
btn.disabled = false;
btn.classList.remove('loading');
setReveal('reveal.retry');
capState.unreachable = true;
paintCap();
});
});
}

var viewsUsed = viewCount;
function paintViews() {
var vt = document.getElementById('views-text');
if (vt) vt.textContent = t('views', viewsUsed);
}

// Everything on screen is said again in the new language. An opened share is
// drawn again from what was already received, so switching spends no view.
function applyLang() {
document.documentElement.lang = lang;
Array.prototype.forEach.call(document.querySelectorAll('[data-t]'), function(n) {
n.textContent = t(n.getAttribute('data-t'));
});
Array.prototype.forEach.call(document.querySelectorAll('[data-t-title]'), function(n) {
n.title = t(n.getAttribute('data-t-title'));
});
Array.prototype.forEach.call(document.querySelectorAll('[data-t-aria]'), function(n) {
n.setAttribute('aria-label', t(n.getAttribute('data-t-aria')));
});
var toggle = document.getElementById('lang-toggle');
toggle.textContent = t('lang.label');
toggle.setAttribute('aria-label', t('lang.switch'));
toggle.title = t('lang.switch');
document.title = document.getElementById('title').textContent + ' · Revoked';
updateToggle();
setDetails(!document.getElementById('sender').hidden);
paintViews();
paintCap();
setReveal(revealKey);
paintServer();
if (resolved) showShare();
}
document.getElementById('lang-toggle').addEventListener('click', function() {
lang = lang === 'de' ? 'en' : 'de';
try { localStorage.setItem(LANG_KEY, lang); } catch (e) {}
applyLang();
});
applyLang();

checkDNS();
})();
</script>
</body>
</html>`))

// statusNext is what a reader of a dead link can still do, by why it is dead.
func statusNext(detail string, status int) (icon, tone, next string) {
	lower := strings.ToLower(detail)
	switch {
	case strings.Contains(lower, "paused"):
		return "pause", "warn", "The sender can turn it back on. Try again later, or ask the sender."
	case status == 404:
		return "search", "neutral", "Check that the whole link was copied. Only the sender can say whether it is still meant to work."
	case strings.Contains(lower, "views"):
		return "eye", "warn", "Every view this link allowed has been used. A new link has to come from the sender."
	default:
		return "link-off", "bad", "Anything opened earlier stays with whoever saved it. A new link has to come from the sender."
	}
}

func linkStatusPage(re *core.RequestEvent, title, detail string, status int) error {
	var buf bytes.Buffer
	icon, tone, next := statusNext(detail, status)
	_ = statusTemplate.Execute(&buf, map[string]string{
		"Title": title, "Detail": detail, "Next": next, "Icon": icon, "Tone": tone,
	})
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
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<link rel="icon" type="image/svg+xml" href="{{logoLight}}" media="(prefers-color-scheme: light)">
<link rel="icon" type="image/svg+xml" href="{{logoDark}}" media="(prefers-color-scheme: dark)">
<title>{{.Title}} · Revoked</title>
<style>` + pageTokens + `
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
background: var(--bg); color: var(--fg); font-family: var(--font-sans);
font-size: 16px; line-height: 1.45; min-height: 100vh; -webkit-font-smoothing: antialiased;
}
header { border-bottom: 1px solid var(--border); }
.nav { max-width: 640px; margin: 0 auto; padding: 10px 16px; display: flex; align-items: center; min-height: 59px; }
.brand { display: flex; align-items: center; gap: 8px; font-weight: 700; font-size: 16px; letter-spacing: -0.02em; color: var(--fg); text-decoration: none; }
.logo { width: 24px; height: 24px; }
.logo-dark { display: none; }
@media (prefers-color-scheme: dark) {
.logo-light { display: none; }
.logo-dark { display: block; }
}
main {
max-width: 440px; margin: 0 auto; padding: 14vh 16px 40px;
display: flex; flex-direction: column; align-items: center; text-align: center; gap: 10px;
}
.tile { width: 56px; height: 56px; display: flex; align-items: center; justify-content: center; margin-bottom: 8px; }
.tone-bad { background: var(--bad-subtle); color: var(--bad); }
.tone-warn { background: var(--warn-subtle); color: var(--warn); }
.tone-neutral { background: var(--surface-subtle); color: var(--fg-muted); }
h1 { font-size: 24px; font-weight: 650; line-height: 1.2; letter-spacing: -0.03em; }
.detail { color: var(--fg); font-size: 16px; }
.next { color: var(--fg-muted); font-size: 14px; line-height: 1.5; }
.more {
margin-top: 14px; width: 100%; min-height: 48px; display: flex; align-items: center; justify-content: center;
border: 1px solid var(--control); color: var(--fg); font-weight: 600; font-size: 15px; text-decoration: none;
}
.more:hover { background: var(--surface-subtle); }
svg { display: block; }
</style>
</head>
<body>
<header>
<div class="nav">
<a class="brand" href="https://revoked.link" target="_blank" rel="noopener noreferrer">
<img class="logo logo-light" src="{{logoLight}}" alt="">
<img class="logo logo-dark" src="{{logoDark}}" alt="">
<span>Revoked</span>
</a>
</div>
</header>
<main>
<div class="tile tone-{{.Tone}}" aria-hidden="true">
<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
{{if eq .Icon "pause"}}<rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/>
{{else if eq .Icon "search"}}<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>
{{else if eq .Icon "eye"}}<path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/>
{{else}}<path d="M9 17H7A5 5 0 0 1 7 7M15 7h2a5 5 0 0 1 4 8M8 12h3M2 2l20 20"/>{{end}}
</svg>
</div>
<h1>{{.Title}}</h1>
<p class="detail">{{.Detail}}</p>
<p class="next">{{.Next}}</p>
<a class="more" href="https://revoked.link" target="_blank" rel="noopener noreferrer">What is Revoked?</a>
</main>
</body>
</html>`))
