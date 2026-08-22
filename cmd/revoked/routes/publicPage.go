package routes

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"html/template"
	"net"
	"net/http"
	"net/url"
	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"strconv"
	"strings"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"golang.org/x/crypto/bcrypt"
)

// The page fetches nothing but its own origin and the two DoH resolvers it
// needs to check this server's DNS pin. No CDN, no analytics, no fonts: a
// secret-sharing page that phones anywhere else is a page that leaks slugs.
const pageCSP = "default-src 'none'; " +
	"style-src 'unsafe-inline'; " +
	"img-src 'self' data:; " +
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
	MaxViews         int
	ViewCount        int
	AppLink          template.URL
	Nonce            string
}

// BindPublicLinkRoutes registers public link viewing, submission, and download routes.
func BindPublicLinkRoutes(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		// Browser landing & JSON probe endpoint: /s/:slug or /api/public/links/:slug
		e.Router.GET("/s/{slug}", func(re *core.RequestEvent) error {
			return handlePublicLinkGet(app, re, root)
		})
		e.Router.GET("/api/public/links/{slug}", func(re *core.RequestEvent) error {
			return handlePublicLinkGet(app, re, root)
		})

		// Unlock submission endpoint: POST /api/public/links/:slug
		e.Router.POST("/api/public/links/{slug}", func(re *core.RequestEvent) error {
			return handlePublicLinkSubmit(app, re, root)
		})

		// Download endpoint: GET /api/public/links/:slug/files/:fileId
		e.Router.GET("/api/public/links/{slug}/files/{fileId}", func(re *core.RequestEvent) error {
			return handlePublicFileDownload(app, re)
		})

		return e.Next()
	})
}

func wantsHTML(accept string) bool {
	return strings.Contains(strings.ToLower(accept), "text/html")
}

func handlePublicLinkGet(app core.App, re *core.RequestEvent, root *server.RootKey) error {
	slug := re.Request.PathValue("slug")
	if slug == "" {
		return re.NotFoundError("Link not found.", nil)
	}

	link, err := app.FindFirstRecordByData(util.Coll.Links, util.Fields.Link.Slug, slug)
	if err != nil || link == nil {
		if wantsHTML(re.Request.Header.Get("Accept")) {
			return linkStatusPage(re, "Link Not Found", "This shared link does not exist or has been removed.", http.StatusNotFound)
		}
		return re.NotFoundError("Link not found.", nil)
	}

	status := link.GetString(util.Fields.Link.Status)
	if status == "revoked" {
		if wantsHTML(re.Request.Header.Get("Accept")) {
			return linkStatusPage(re, "Link Revoked", "This link has been revoked by the owner and can no longer be viewed.", http.StatusGone)
		}
		return re.BadRequestError("This link has been revoked.", nil)
	}

	if status == "paused" {
		if wantsHTML(re.Request.Header.Get("Accept")) {
			return linkStatusPage(re, "Link Paused", "This link is temporarily paused by the owner.", http.StatusForbidden)
		}
		return re.BadRequestError("This link is paused.", nil)
	}

	if expiresAt := link.GetDateTime(util.Fields.Link.ExpiresAt); !expiresAt.IsZero() && expiresAt.Time().Before(time.Now()) {
		if wantsHTML(re.Request.Header.Get("Accept")) {
			return linkStatusPage(re, "Link Expired", "This share has expired.", http.StatusGone)
		}
		return re.BadRequestError("This link has expired.", nil)
	}

	maxViews := link.GetInt(util.Fields.Link.MaxViews)
	viewCount := link.GetInt(util.Fields.Link.ViewCount)
	if maxViews > 0 && viewCount >= maxViews {
		if wantsHTML(re.Request.Header.Get("Accept")) {
			return linkStatusPage(re, "View Limit Reached", "This link has reached its maximum view limit.", http.StatusGone)
		}
		return re.BadRequestError("View limit reached.", nil)
	}

	if wantsHTML(re.Request.Header.Get("Accept")) {
		return servePublicPage(app, re, root, link, slug)
	}

	probe := map[string]any{
		"slug":             slug,
		"label":            link.GetString(util.Fields.Link.Label),
		"requiresPassword": link.GetString(util.Fields.Link.Password) != "",
		"requireHandshake": link.GetBool(util.Fields.Link.RequireHandshake),
		"server": map[string]any{
			"domain":          root.Domain(),
			"rootFingerprint": root.Fingerprint(),
		},
	}

	if idId := link.GetString(util.Fields.Link.Identity); idId != "" {
		if id, err := app.FindRecordById(util.Coll.Identities, idId); err == nil && id != nil {
			sharer := map[string]any{
				"name":            id.GetString(util.Fields.Identity.Name),
				"domainAtIssue":   id.GetString(util.Fields.Identity.DomainAtIssue),
				"fingerprint":     id.GetString(util.Fields.Identity.Fingerprint),
				"parentSignature": id.GetString(util.Fields.Identity.ParentSignature),
				"status":          services.IdentityStatusOf(id),
			}
			stapleIdentityStatus(app, root, sharer, id.GetString(util.Fields.Identity.Fingerprint))
			probe["sharer"] = sharer
		}
	}

	return re.JSON(http.StatusOK, probe)
}

type submitPayload struct {
	Password           *string `json:"password"`
	HandshakeToken     *string `json:"handshakeToken"`
	IdentityID         *string `json:"identityId"`
	ChallengeNonce     *string `json:"challengeNonce"`
	ChallengeSignature *string `json:"challengeSignature"`
}

func handlePublicLinkSubmit(app core.App, re *core.RequestEvent, root *server.RootKey) error {
	slug := re.Request.PathValue("slug")
	link, err := app.FindFirstRecordByData(util.Coll.Links, util.Fields.Link.Slug, slug)
	if err != nil || link == nil {
		return re.NotFoundError("Link not found.", nil)
	}

	if link.GetString(util.Fields.Link.Status) != "active" {
		return re.BadRequestError("This link is not active.", nil)
	}

	maxViews := link.GetInt(util.Fields.Link.MaxViews)
	viewCount := link.GetInt(util.Fields.Link.ViewCount)
	if maxViews > 0 && viewCount >= maxViews {
		return re.BadRequestError("Maximum view count reached.", nil)
	}

	var payload submitPayload
	if err := re.BindBody(&payload); err != nil {
		return re.BadRequestError("Invalid request payload.", err)
	}

	storedHash := link.GetString(util.Fields.Link.Password)
	if storedHash != "" {
		if payload.Password == nil || *payload.Password == "" {
			return re.BadRequestError("Password required.", nil)
		}
		if err := bcrypt.CompareHashAndPassword([]byte(storedHash), []byte(*payload.Password)); err != nil {
			return re.BadRequestError("Incorrect password.", nil)
		}
	}

	link.Set(util.Fields.Link.ViewCount, viewCount+1)
	if err := app.Save(link); err != nil {
		return re.InternalServerError("Failed to record view.", err)
	}

	recordsList := link.Get("records")
	sectionsList := link.Get("sections")

	responseBody := map[string]any{
		"label":    link.GetString(util.Fields.Link.Label),
		"records":  recordsList,
		"sections": sectionsList,
	}

	if link.GetBool(util.Fields.Link.RequireHandshake) && payload.IdentityID != nil {
		tokenBytes := make([]byte, 32)
		_, _ = rand.Read(tokenBytes)
		newToken := base64.URLEncoding.EncodeToString(tokenBytes)
		re.Response.Header().Set("X-Handshake-Token", newToken)
	}

	return re.JSON(http.StatusOK, responseBody)
}

func handlePublicFileDownload(app core.App, re *core.RequestEvent) error {
	slug := re.Request.PathValue("slug")
	fileId := re.Request.PathValue("fileId")
	dlToken := re.Request.URL.Query().Get("dl")

	if slug == "" || fileId == "" || dlToken == "" {
		return re.BadRequestError("Invalid download request parameters.", nil)
	}

	record, err := app.FindRecordById(util.Coll.Records, fileId)
	if err != nil || record == nil {
		return re.NotFoundError("File record not found.", nil)
	}

	filename := record.GetString("filename")
	if filename == "" {
		filename = "download"
	}

	fileField := record.GetString("file")
	if fileField == "" {
		return re.NotFoundError("No file attached to this record.", nil)
	}

	fsys, err := app.NewFilesystem()
	if err != nil {
		return re.InternalServerError("Failed to initialize storage filesystem.", err)
	}
	defer fsys.Close()

	fileKey := record.BaseFilesPath() + "/" + fileField
	reader, err := fsys.GetFile(fileKey)
	if err != nil {
		return re.NotFoundError("File not found in storage.", err)
	}
	defer reader.Close()

	re.Response.Header().Set("Content-Disposition", "attachment; filename="+url.QueryEscape(filename))
	http.ServeContent(re.Response, re.Request, filename, time.Time{}, reader)
	return nil
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

var pageTemplate = template.Must(template.New("page").Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>{{if .Label}}{{.Label}}{{else}}Shared Items{{end}} · Revoked</title>
<style>
:root {
--font-sans: system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
--font-mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
}

:root,
html[data-theme="light"] {
color-scheme: light;
--bg: #f6fbf7;
--surface: #f6fbf7;
--surface-subtle: #e8f0eb;
--surface-hover: #dbe5de;
--border: #c0c9c2;
--border-strong: #707973;
--fg: #171d1a;
--fg-muted: #535f58;
--primary: #006c4c;
--primary-subtle: #e6f6ee;
--primary-fg: #ffffff;
--ok: #006c4c;
--ok-subtle: #dcfce7;
--bad: #ba1a1a;
--bad-subtle: #ffdad6;
--badge-bg: #e1e7e2;
--badge-fg: #3f4943;
}

html[data-theme="dark"] {
color-scheme: dark;
--bg: #0f1512;
--surface: #0f1512;
--surface-subtle: #1b221e;
--surface-hover: #262e2a;
--border: #3f4943;
--border-strong: #89938d;
--fg: #dfe4df;
--fg-muted: #89938d;
--primary: #59dc9e;
--primary-subtle: #003825;
--primary-fg: #003825;
--ok: #59dc9e;
--ok-subtle: #003825;
--bad: #ffb4ab;
--bad-subtle: #690005;
--badge-bg: #28312c;
--badge-fg: #c0c9c2;
}

@media (prefers-color-scheme: dark) {
html:not([data-theme="light"]) {
color-scheme: dark;
--bg: #0f1512;
--surface: #0f1512;
--surface-subtle: #1b221e;
--surface-hover: #262e2a;
--border: #3f4943;
--border-strong: #89938d;
--fg: #dfe4df;
--fg-muted: #89938d;
--primary: #59dc9e;
--primary-subtle: #003825;
--primary-fg: #003825;
--ok: #59dc9e;
--ok-subtle: #003825;
--bad: #ffb4ab;
--bad-subtle: #690005;
--badge-bg: #28312c;
--badge-fg: #c0c9c2;
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
border-bottom: 1px solid var(--border);
}

.card-header-title {
font-size: 14px;
font-weight: 600;
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
a { color: var(--primary); text-decoration: none; }
a:hover { text-decoration: underline; }
</style>
</head>
<body>

<header>
<div class="nav">
<div class="brand">
<span>Revoked</span>
</div>
<div class="nav-actions">
<span class="badge">READ-ONLY SHARE</span>
<button class="btn" id="theme-toggle" aria-label="Toggle visual theme">Theme</button>
</div>
</div>
</header>

<main>
<div class="grid">
<div style="display: flex; flex-direction: column; gap: 16px;">

<div class="card card-pad">
<h1 class="header-title">{{if .Label}}{{.Label}}{{else}}Shared Items{{end}}</h1>
<div class="header-sub">read only link provided by Revoked.</div>
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
<div style="font-weight: 600; margin-bottom: 2px;">Vault Contents Ready</div>
<div class="muted sm" id="capnote">
{{if gt .MaxViews 0}}Limited view: {{.ViewCount}} of {{.MaxViews}} views used. Revealing spends 1 view.{{else}}Nothing is exposed until requested.{{end}}
</div>
</div>
<button class="btn primary" id="reveal">Reveal Data</button>
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
Revoked replaces copies of your data with revocable, always-current references — and lets every party verify the other through DNS.
</p>
<p class="sm" style="margin-top: 8px;">
<a href="https://revoked.link" target="_blank" rel="noopener noreferrer" style="display: inline-flex; align-items: center; gap: 6px;">
revoked.link
</a>
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
themeToggle.innerHTML = sunIcon + '<span>Light</span>';
themeToggle.setAttribute('aria-label', 'Switch to light theme');
} else {
themeToggle.innerHTML = moonIcon + '<span>Dark</span>';
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

if (r.type === 'file') {
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

function render(data) {
var out = document.getElementById('out');
out.textContent = '';

var rootRecords = data.records || [];
if (rootRecords.length > 0) {
var card = el('div', 'card');
var header = el('div', 'card-header');
header.appendChild(el('div', 'card-header-title', 'General Records'));
header.appendChild(el('span', 'badge', rootRecords.length + (rootRecords.length === 1 ? ' item' : ' items')));
card.appendChild(header);

rootRecords.forEach(function(r) {
card.appendChild(renderRecordItem(r));
});
out.appendChild(card);
}

var sections = data.sections || [];
sections.forEach(function(s) {
var secRecords = (s.records || []).filter(function(r) { return r && typeof r === 'object'; });
var card = el('div', 'card');
var header = el('div', 'card-header');
var title = el('div', 'card-header-title', s.name || 'Section');
if (s.key) {
title.appendChild(el('span', 'key-tag', '(' + s.key + ')'));
}
header.appendChild(title);
header.appendChild(el('span', 'badge', secRecords.length + (secRecords.length === 1 ? ' item' : ' items')));
card.appendChild(header);

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

if (!rootRecords.length && !sections.length) {
var emptyCard = el('div', 'card card-pad');
emptyCard.appendChild(el('p', 'muted sm', 'No items are shared in this link.'));
out.appendChild(emptyCard);
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
btn.textContent = 'Reveal Data';
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

var statusTemplate = template.Must(template.New("status").Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>{{.Title}} · Revoked</title>
<style>
:root {
--font-sans: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}
:root,
html[data-theme="light"] {
color-scheme: light;
--bg: #f6fbf7;
--surface: #f6fbf7;
--border: #c0c9c2;
--fg: #171d1a;
--fg-muted: #535f58;
--primary: #006c4c;
}
html[data-theme="dark"] {
color-scheme: dark;
--bg: #0f1512;
--surface: #0f1512;
--border: #3f4943;
--fg: #dfe4df;
--fg-muted: #89938d;
--primary: #59dc9e;
}
@media (prefers-color-scheme: dark) {
html:not([data-theme="light"]) {
color-scheme: dark;
--bg: #0f1512;
--surface: #0f1512;
--border: #3f4943;
--fg: #dfe4df;
--fg-muted: #89938d;
--primary: #59dc9e;
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
