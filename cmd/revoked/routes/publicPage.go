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
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<link rel="icon" type="image/svg+xml" href="{{logoLight}}" media="(prefers-color-scheme: light)">
<link rel="icon" type="image/svg+xml" href="{{logoDark}}" media="(prefers-color-scheme: dark)">
<title>{{template "heading" .}} · Revoked</title>
<style>
:root {
--font-sans: system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
--font-mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
}

:root,
html[data-theme="light"] {
color-scheme: light;
--bg: #f8f9ff;
--surface: #f8f9ff;
--surface-subtle: #e1e2e8;
--surface-hover: #d8dae0;
--border: #c3c7cf;
--border-strong: #73777f;
--fg: #191c20;
--fg-muted: #42474e;
--primary: #35618e;
--primary-subtle: #d1e4ff;
--primary-fg: #ffffff;
--ok: #216a4d;
--ok-subtle: #dcfce7;
--bad: #ba1a1a;
--bad-subtle: #ffdad6;
--badge-bg: #d6e3f7;
--badge-fg: #3b4858;
}

html[data-theme="dark"] {
color-scheme: dark;
--bg: #101418;
--surface: #101418;
--surface-subtle: #32353a;
--surface-hover: #36393e;
--border: #42474e;
--border-strong: #8d9199;
--fg: #e1e2e8;
--fg-muted: #c3c7cf;
--primary: #a0cafd;
--primary-subtle: #184975;
--primary-fg: #003258;
--ok: #8ed5b1;
--ok-subtle: #003825;
--bad: #ffb4ab;
--bad-subtle: #93000a;
--badge-bg: #3b4858;
--badge-fg: #d6e3f7;
}

@media (prefers-color-scheme: dark) {
html:not([data-theme="light"]) {
color-scheme: dark;
--bg: #101418;
--surface: #101418;
--surface-subtle: #32353a;
--surface-hover: #36393e;
--border: #42474e;
--border-strong: #8d9199;
--fg: #e1e2e8;
--fg-muted: #c3c7cf;
--primary: #a0cafd;
--primary-subtle: #184975;
--primary-fg: #003258;
--ok: #8ed5b1;
--ok-subtle: #003825;
--bad: #ffb4ab;
--bad-subtle: #93000a;
--badge-bg: #3b4858;
--badge-fg: #d6e3f7;
}
}

* { box-sizing: border-box; margin: 0; padding: 0; }
body {
background: var(--bg);
color: var(--fg);
font-family: var(--font-sans);
font-size: 14px;
line-height: 1.5;
min-height: 100vh;
}

header {
border-bottom: 1px solid var(--border);
background: var(--surface);
position: sticky;
top: 0;
z-index: 10;
}

.nav {
max-width: 900px;
margin: 0 auto;
padding: 12px 20px;
display: flex;
align-items: center;
justify-content: space-between;
}

.brand {
display: flex;
align-items: center;
gap: 8px;
font-weight: 700;
font-size: 16px;
letter-spacing: -0.02em;
color: var(--fg);
}

.brand-dot {
width: 9px;
height: 9px;
border-radius: 50%;
background: var(--primary);
}

.logo { width: 24px; height: 24px; border-radius: 6px; }
.logo-dark { display: none; }
html[data-theme="dark"] .logo-light { display: none; }
html[data-theme="dark"] .logo-dark { display: block; }
@media (prefers-color-scheme: dark) {
html:not([data-theme="light"]) .logo-light { display: none; }
html:not([data-theme="light"]) .logo-dark { display: block; }
}

.nav-actions {
display: flex;
align-items: center;
gap: 10px;
}

main {
max-width: 900px;
margin: 24px auto 32px;
padding: 0 20px;
display: flex;
flex-direction: column;
gap: 16px;
}

.card {
background: var(--surface);
border: 1px solid var(--border);
border-radius: 12px;
overflow: hidden;
}

.card-pad { padding: 18px 20px; }

.header-title {
font-size: 18px;
font-weight: 600;
letter-spacing: -0.01em;
margin-bottom: 4px;
}

.header-sub {
color: var(--fg-muted);
font-size: 13px;
}

.card-header {
background: var(--surface-subtle);
padding: 12px 20px;
display: flex;
align-items: center;
justify-content: space-between;
gap: 12px;
border-bottom: 1px solid var(--border);
}

.card-header-title {
font-size: 14px;
font-weight: 600;
display: flex;
align-items: center;
gap: 8px;
min-width: 0;
}

.card-header-title > span:first-child,
.card-header-title > .key-tag {
min-width: 0;
overflow: hidden;
text-overflow: ellipsis;
white-space: nowrap;
}

.card-header > .badge,
.card-header-actions {
flex-shrink: 0;
}

.card-header-actions {
display: flex;
align-items: center;
gap: 8px;
}

.badge {
display: inline-flex;
align-items: center;
padding: 2px 8px;
border-radius: 6px;
font-size: 11px;
font-weight: 600;
letter-spacing: 0.03em;
text-transform: uppercase;
background: var(--badge-bg);
color: var(--badge-fg);
border: 1px solid var(--border);
}

.badge.primary { background: var(--primary-subtle); color: var(--primary); border-color: transparent; }
.badge.ok { background: var(--ok-subtle); color: var(--ok); border-color: transparent; }
.badge.bad { background: var(--bad-subtle); color: var(--bad); border-color: transparent; }

.grid {
display: grid;
grid-template-columns: 1fr;
gap: 16px;
}

@media(min-width: 768px) {
.grid {
grid-template-columns: 2fr 1fr;
align-items: start;
}
}

.record-row {
padding: 16px 20px;
border-bottom: 1px solid var(--border);
}

.record-row:last-child { border-bottom: none; }

.kv-row {
display: flex;
align-items: baseline;
justify-content: space-between;
gap: 16px;
}
.kv-row > .muted { flex: 0 0 40%; }
.kv-row > .val-text { text-align: right; }

.record-top {
display: flex;
align-items: center;
justify-content: space-between;
margin-bottom: 8px;
}

.record-info {
display: flex;
align-items: center;
gap: 8px;
flex-wrap: wrap;
}

.record-label {
font-weight: 600;
font-size: 14px;
}

.key-tag {
font-family: var(--font-mono);
font-size: 11px;
color: var(--fg-muted);
background: var(--surface-subtle);
padding: 2px 6px;
border-radius: 4px;
border: 1px solid var(--border);
}

.wm-host { position: relative; }
.wm-overlay {
position: absolute;
inset: 0;
overflow: hidden;
pointer-events: none;
z-index: 5;
}
.wm-overlay-inner {
position: absolute;
top: -50%;
left: -50%;
width: 200%;
height: 200%;
transform: rotate(-30deg);
display: flex;
flex-direction: column;
justify-content: space-around;
color: var(--fg);
opacity: 0.12;
font-size: 13px;
font-weight: 600;
white-space: nowrap;
}
.preview {
margin-top: 8px;
border: 1px solid var(--border);
border-radius: 8px;
overflow: hidden;
background: var(--surface-subtle);
}
.preview img { display: block; max-width: 100%; height: auto; margin: 0 auto; }
.preview iframe { display: block; width: 100%; height: 70vh; border: 0; }

.val-box {
background: var(--surface-subtle);
border: 1px solid var(--border);
border-radius: 8px;
padding: 8px 12px;
display: flex;
align-items: center;
justify-content: space-between;
gap: 12px;
}

.val-text {
font-family: var(--font-mono);
font-size: 13px;
word-break: break-all;
user-select: all;
flex: 1;
}

.btn {
font-family: var(--font-sans);
font-size: 12px;
font-weight: 500;
padding: 6px 12px;
border-radius: 6px;
border: 1px solid var(--border);
background: var(--surface-subtle);
color: var(--fg);
cursor: pointer;
display: inline-flex;
align-items: center;
gap: 6px;
transition: all 0.15s ease;
white-space: nowrap;
}

.btn:hover { background: var(--surface-hover); }
.btn:active { transform: scale(0.98); }
.btn.primary {
background: var(--primary);
border-color: var(--primary);
color: var(--primary-fg);
font-weight: 600;
}
.btn.primary:hover { opacity: 0.9; }
.btn:disabled { opacity: 0.5; cursor: not-allowed; }

.btn svg { display: block; }

.status-row {
display: flex;
align-items: center;
justify-content: space-between;
padding: 8px 0;
font-size: 13px;
border-bottom: 1px solid var(--border);
}
.status-row:last-child { border-bottom: none; }

footer {
max-width: 900px;
margin: 32px auto 48px;
padding: 20px;
border-top: 1px solid var(--border);
text-align: center;
}

.mono { font-family: var(--font-mono); word-break: break-all; }
.sm { font-size: 12px; }
.muted { color: var(--fg-muted); }
.bad { color: var(--bad); }
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
<div class="nav-actions">
<button class="badge" id="theme-toggle" aria-label="Toggle visual theme">Theme</button>
</div>
</div>
</header>

<main{{if eq .Purpose "application"}} data-purpose="application"{{end}}>
<div class="grid">
<div style="display: flex; flex-direction: column; gap: 16px;">

<div class="card card-pad">
<h1 class="header-title">{{template "heading" .}}</h1>
</div>

{{if or .Gated .RequireHandshake}}
<div class="card card-pad">
<div style="display: flex; align-items: flex-start; gap: 12px;">
<div style="flex: 1;">
<div style="font-weight: 600; margin-bottom: 4px;">APP REQUIRED</div>
<p class="muted sm">This share requires {{if .RequireHandshake}}a verified identity{{else}}a password{{end}}. For cryptographic safety, unlock it in the native application where server identities are validated before keys are submitted. Never trust this web-version of Revoked, since it lives on the sender's server and can be tampered with.</p>
</div>
</div>
<div style="margin-top: 16px;">
<a href="{{.AppLink}}" class="btn primary" style="display: inline-block;">Open in Revoked App</a>
</div>
</div>
{{else}}
<div class="card card-pad" id="gate">
<div style="display: flex; justify-content: space-between; align-items: center; gap: 16px; flex-wrap: wrap;">
<div>
<div style="font-weight: 600; margin-bottom: 2px;">Only continue, if you trust this source.</div>
<div class="muted sm" id="capnote">
{{if gt .MaxViews 0}}Limited view: {{.ViewCount}} of {{.MaxViews}} views used. Revealing spends 1 view.{{else}}Nothing is loaded, until you press "Load & Show".{{end}}
</div>
{{if .Watermarked}}<div class="muted sm">Files in this share are stamped with who they were sent to.</div>{{end}}
</div>
<button class="btn primary" id="reveal">Load & Show</button>
</div>
</div>
<div id="out" style="display: flex; flex-direction: column; gap: 16px;"></div>
{{end}}

</div>

<div style="display: flex; flex-direction: column; gap: 16px;">
<div class="card">
<div class="card-header">
<div class="card-header-title">Share Provenance</div>
</div>
<div style="padding: 12px 20px;">
<div class="status-row">
<span class="muted">Server DNS</span>
<span class="badge" id="dns">Checking…</span>
</div>
<div class="status-row">
<span class="muted">Host Domain</span>
<span class="mono sm">{{.Domain}}</span>
</div>
{{if .SharerName}}
<div class="status-row">
<span class="muted">Shared by</span>
<span style="font-weight: 500;">{{.SharerName}}{{if .SharerRevoked}} <span class="badge bad">Revoked</span>{{end}}</span>
</div>
<div style="margin-top: 8px;">
<div class="muted sm" style="margin-bottom: 2px;">Claimed Key Fingerprint</div>
<div class="mono sm muted">{{.SharerPrint}}</div>
</div>
{{if .SharerRevoked}}
<p class="muted sm" style="margin-top: 8px;">
{{.Domain}} has withdrawn this identity. The signature still verifies — it was
valid when it was made — but the domain no longer vouches for whoever holds it.
</p>
{{end}}
{{end}}
</div>
</div>

<div class="card card-pad">
<p class="muted sm">
Values are resolved live and can be Revoked by the owner at any time.
<a href="{{.AppLink}}">Open in app</a> for end-to-end cryptographic verification.
</p>
</div>
</div>
</div>
</main>

<footer>
<p class="muted sm">
For more information visit <a href="https://revoked.link" target="_blank" rel="noopener noreferrer" style="display: inline-flex; align-items: center; gap: 6px;">
revoked.link
</p>

<p class="sm" style="margin-top: 8px;">

</p>
</footer>

<script nonce="{{.Nonce}}">
(function(){
var slug={{.Slug}}, domain={{.Domain}}, pin={{.RootFingerprint}};

var themeToggle = document.getElementById('theme-toggle');

var sunIcon = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/></svg>';
var moonIcon = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>';

function isDark() {
var current = document.documentElement.getAttribute('data-theme');
if (current === 'dark') return true;
if (current === 'light') return false;
return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
}

function updateToggleLabel() {
if (!themeToggle) return;
if (isDark()) {
themeToggle.innerHTML = sunIcon + '';
themeToggle.setAttribute('aria-label', 'Switch to light theme');
} else {
themeToggle.innerHTML = moonIcon + '';
themeToggle.setAttribute('aria-label', 'Switch to dark theme');
}
}

function applyTheme(theme) {
if (theme === 'light' || theme === 'dark') {
document.documentElement.setAttribute('data-theme', theme);
} else {
document.documentElement.removeAttribute('data-theme');
}
updateToggleLabel();
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
var onSystemChange = function() { updateToggleLabel(); };
if (mq.addEventListener) { mq.addEventListener('change', onSystemChange); }
else if (mq.addListener) { mq.addListener(onSystemChange); }
}

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

function checkDNS() {
var node = document.getElementById('dns');
var d = String(domain || '');

// Local/dev hosts have no public DNS record to pin against.
var isLocal = d === '' || d === 'localhost' || d.indexOf('.') === -1 ||
d.indexOf(':') !== -1 || /^\d+\.\d+\.\d+\.\d+$/.test(d) ||
/\.(localhost|local|test|internal)$/i.test(d);
if (isLocal) {
node.className = 'badge';
node.textContent = 'LOCAL DEV';
node.title = 'DNS pinning is skipped for local or non-public hostnames.';
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
if (m[1].toLowerCase() === String(pin).toLowerCase()) {
node.className = 'badge ok';
node.textContent = 'VERIFIED';
} else {
node.className = 'badge bad';
node.textContent = 'SPOOFED';
}
return;
}
}
}).catch(function(){});
});

setTimeout(function() {
if (done) return;
node.className = 'badge bad';
node.textContent = 'UNVERIFIED';
}, 5000);
}

function renderRecordItem(r) {
var row = el('div', 'record-row');

var top = el('div', 'record-top');
var info = el('div', 'record-info');
info.appendChild(el('span', 'record-label', r.label || 'Record'));
if (r.key) {
info.appendChild(el('span', 'key-tag', 'KEY: ' + r.key));
}
top.appendChild(info);
top.appendChild(el('span', 'badge', (r.type || 'text').toUpperCase()));
row.appendChild(top);

if (r.type === 'file' && watermarkLine) {
row.appendChild(renderStampedFile(r));
} else if (r.type === 'file') {
var box = el('div', 'val-box');
var meta = el('span', 'val-text', (r.filename || 'file') + ' · ' + fmtBytes(r.size || 0));
box.appendChild(meta);

var b = el('button', 'btn primary', 'Download');
b.addEventListener('click', function() {
b.disabled = true;
var u = '/api/public/links/' + encodeURIComponent(slug) + '/files/' + encodeURIComponent(r.id) + '?dl=' + encodeURIComponent(r.downloadToken || '');
window.location.href = u;
setTimeout(function() { b.disabled = false; }, 2000);
});
box.appendChild(b);
row.appendChild(box);
} else {
var box = el('div', 'val-box');
var valText = r.value == null ? '—' : String(r.value);
box.appendChild(el('span', 'val-text', valText));

var copyBtn = el('button', 'btn', 'Copy');
copyBtn.addEventListener('click', function() {
navigator.clipboard.writeText(valText).then(function() {
copyBtn.textContent = 'Copied!';
setTimeout(function() { copyBtn.textContent = 'Copy'; }, 1500);
});
});
box.appendChild(copyBtn);
row.appendChild(box);
}
return row;
}

// Set on reveal for a watermarked share: its files come back stamped, and the
// same line is laid over the page so a screenshot of plain values carries it.
var watermarkLine = '';

var stampedTypes = { 'image/png': '.png', 'image/jpeg': '.jpg', 'application/pdf': '.pdf' };

// A stamped file is fetched once: the one download token serves both the
// preview and the save, and the preview is shown from memory rather than by
// loading the file URL inline, so nothing uploaded ever renders from this origin.
function renderStampedFile(r) {
var wrap = el('div');
var box = el('div', 'val-box');
box.appendChild(el('span', 'val-text', (r.filename || 'file') + ' · ' + fmtBytes(r.size || 0)));
var b = el('button', 'btn primary', 'View');
box.appendChild(b);
wrap.appendChild(box);

b.addEventListener('click', function() {
b.disabled = true;
b.textContent = 'Loading…';
var u = '/api/public/links/' + encodeURIComponent(slug) + '/files/' + encodeURIComponent(r.id) + '?dl=' + encodeURIComponent(r.downloadToken || '');
fetch(u).then(function(res) {
if (!res.ok) {
return res.json().then(function(j) { throw new Error((j && j.message) || 'This file could not be loaded.'); },
function() { throw new Error('This file could not be loaded.'); });
}
return res.blob();
}).then(function(blob) {
var ext = stampedTypes[blob.type];
if (!ext) { throw new Error('This file could not be loaded.'); }
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
wrap.appendChild(preview);

var save = el('a', 'btn', 'Save');
save.href = url;
save.download = String(r.filename || 'file').replace(/\.[^.]+$/, '') + ext;
box.replaceChild(save, b);
}).catch(function(err) {
b.remove();
box.appendChild(el('span', 'bad sm', err.message));
});
});
return wrap;
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

function makeCard(name, key, count, action) {
var card = el('div', 'card');
var header = el('div', 'card-header');
var title = el('div', 'card-header-title');
title.appendChild(el('span', '', name));
if (key) {
title.appendChild(el('span', 'key-tag', '(' + key + ')'));
}
header.appendChild(title);
var badge = el('span', 'badge', count + (count === 1 ? ' item' : ' items'));
if (action) {
var actions = el('div', 'card-header-actions');
actions.appendChild(badge);
actions.appendChild(action);
header.appendChild(actions);
} else {
header.appendChild(badge);
}
card.appendChild(header);
return card;
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
var label = 'Download all (.zip)';
var b = el('button', 'btn primary', label);
b.id = 'download-all';
b.addEventListener('click', function() {
b.disabled = true;
b.textContent = 'Preparing…';
report('');
var u = '/api/public/links/' + encodeURIComponent(slug) + '/archive?dl=' + encodeURIComponent(data.archiveToken);
fetch(u).then(function(res) {
if (!res.ok) {
return res.json().then(function(j) { return j; }, function() { return {}; }).then(function(j) {
var msg = (j && j.message) || 'The archive could not be downloaded.';
if (res.status === 401) msg = 'This download has expired or was already used. Reload the page to get a fresh one.';
b.textContent = label;
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
b.textContent = 'Downloaded';
});
}).catch(function() {
b.disabled = false;
b.textContent = label;
report('Could not communicate with the vault server.');
});
});
return b;
}

// reporter shows a message in a row of its own under the card's first child:
// the header of a listing card, or the content of a padded one.
function reporter(card, padded) {
var row = null;
return function(msg) {
if (!msg) { if (row) row.remove(); row = null; return; }
if (!row) {
row = el('div', padded ? '' : 'record-row');
if (padded) row.style.marginTop = '8px';
card.insertBefore(row, card.children[1] || null);
}
row.textContent = '';
row.appendChild(el('span', 'bad sm', msg));
};
}

function renderApplicantRow(r) {
var row = el('div', 'record-row kv-row');
row.appendChild(el('span', 'muted sm', r.label || r.key));
row.appendChild(el('span', 'val-text', r.value == null ? '—' : String(r.value)));
return row;
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
var who = makeCard('Applicant', '', applicant.length);
applicant.forEach(function(r) { who.appendChild(renderApplicantRow(r)); });
out.appendChild(who);
}
if (documents.length) {
var report = null;
var action = data.archiveToken ? archiveButton(data, function(msg) { report(msg); }) : null;
var docs = makeCard('Documents', '', documents.length, action);
report = reporter(docs);
documents.forEach(function(r) { docs.appendChild(renderRecordItem(r)); });
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
var archiveCard = el('div', 'card card-pad');
var archiveRow = el('div', 'kv-row');
archiveRow.style.alignItems = 'center';
archiveRow.appendChild(el('span', 'muted sm', 'Every file in this share, in one archive.'));
var report = reporter(archiveCard, true);
archiveRow.appendChild(archiveButton(data, report));
archiveCard.appendChild(archiveRow);
out.appendChild(archiveCard);
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
var card = makeCard(s.name || 'Section', s.key, secRecords.length);

if (!secRecords.length) {
var empty = el('div', 'record-row');
empty.appendChild(el('span', 'muted sm', 'No records inside this section.'));
card.appendChild(empty);
} else {
secRecords.forEach(function(r) {
card.appendChild(renderRecordItem(r));
});
}
out.appendChild(card);
});

if (looseRecords.length > 0) {
var card = makeCard(isApplication ? 'Further details' : 'General Records', '', looseRecords.length);
looseRecords.forEach(function(r) {
card.appendChild(renderRecordItem(r));
});
out.appendChild(card);
}

if (!rootRecords.length && !sections.length) {
var emptyCard = el('div', 'card card-pad');
emptyCard.appendChild(el('p', 'muted sm', 'No items are shared in this link.'));
out.appendChild(emptyCard);
}

if (watermarkLine) {
out.classList.add('wm-host');
out.appendChild(watermarkOverlay(watermarkLine));
}
}

var btn = document.getElementById('reveal');
if (btn) {
btn.addEventListener('click', function() {
btn.disabled = true;
btn.textContent = 'Loading…';
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
gate.appendChild(el('p', 'bad sm', (res.body && res.body.message) || 'This share is no longer available.'));
return;
}
gate.remove();
render(res.body);
})
.catch(function() {
btn.disabled = false;
btn.textContent = 'Load & Show';
var n = document.getElementById('capnote');
n.className = 'bad sm';
n.textContent = 'Could not communicate with the vault server.';
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
