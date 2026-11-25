package routes

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"html/template"
	"net/http"
	"net/url"

	"revoked/cmd/revoked/server"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// The flow pages talk to their own origin and nothing else, like the sign-in
// page they share a ceremony with.
const flowPageCSP = passkeyPageCSP

type flowPageData struct {
	// "request", "answers", "signin" or "connect": which script the shell runs.
	Page string
	// Why the page cannot go on; empty when it can.
	Problem string
	// What the page works on, checked by the server first: the sign-in
	// request's parameters, or the connect request.
	Data any
	// The request slug on /r/{slug}; empty on /answers.
	Slug string
	// The matching revoked:// address, for a person who has the app.
	AppLink     string
	OriginOK    bool
	Signups     bool
	VerifyEmail bool
	Nonce       string
}

// BrowserFlowsRoute serves the pages a counterparty completes a flow on
// without the app (BROWSER.md §4): answering a request, and managing the
// answers given. They call the same endpoints the app calls; the session they
// sign in to lives in the page's memory for one visit and is never stored.
//
//	GET /r/{slug}          answer a request
//	GET /answers           the answers this account has given
//	GET /connect           connect a tool (BROWSER.md §4.6)
//	GET /s/{slug}/identity open an identity-protected share (§4.8)
//
// The sign-in consent page (§4.7) is served at /oidc/authorize by OIDCRoute.
func BrowserFlowsRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/r/{slug}", func(re *core.RequestEvent) error {
			slug := re.Request.PathValue("slug")
			// Not looked up: the page is then no slug-existence oracle and
			// spends no probe budget. It probes for itself.
			if !requestSlugPattern.MatchString(slug) || len(slug) > 100 {
				return linkStatusPage(re, "Request not found", "This request does not exist.", http.StatusNotFound)
			}
			return serveFlowPage(re, root, http.StatusOK, flowPageData{
				Page:    "request",
				Slug:    slug,
				AppLink: "revoked://r/" + pageOrigin(re, root) + "/" + url.PathEscape(slug),
			})
		})
		e.Router.GET("/answers", func(re *core.RequestEvent) error {
			return serveFlowPage(re, root, http.StatusOK, flowPageData{Page: "answers", AppLink: "revoked://open"})
		})
		e.Router.GET("/s/{slug}/identity", func(re *core.RequestEvent) error {
			slug := re.Request.PathValue("slug")
			// Not looked up, as on /r/{slug}: the page probes for itself.
			if !requestSlugPattern.MatchString(slug) || len(slug) > 100 {
				return linkStatusPage(re, "Link not found", "This link does not exist.", http.StatusNotFound)
			}
			return serveFlowPage(re, root, http.StatusOK, flowPageData{
				Page:    "share",
				Slug:    slug,
				AppLink: "revoked://s/" + pageOrigin(re, root) + "/" + url.PathEscape(slug),
			})
		})
		e.Router.GET("/connect", func(re *core.RequestEvent) error {
			if !allowRequest(re, probeLimiter, "connect") {
				return rateLimitedResponse(re)
			}
			q := re.Request.URL.Query()
			req, ok := parseConnectLink(q)
			if !ok {
				return serveFlowPage(re, root, http.StatusBadRequest, flowPageData{Page: "connect", Problem: "client"})
			}
			return serveFlowPage(re, root, http.StatusOK, flowPageData{
				Page:    "connect",
				Data:    req,
				AppLink: "revoked://connect?" + q.Encode(),
			})
		})
		return e.Next()
	})
}

func serveFlowPage(re *core.RequestEvent, root *server.RootKey, status int, data flowPageData) error {
	nonceBytes := make([]byte, 16)
	if _, err := rand.Read(nonceBytes); err != nil {
		return re.InternalServerError("Failed to render the page.", err)
	}
	data.Nonce = base64.StdEncoding.EncodeToString(nonceBytes)
	_, _, data.OriginOK = util.PasskeyRelyingParty(pageOrigin(re, root))
	data.Signups = util.SignupsAllowed()
	data.VerifyEmail = util.SignupEmailVerification()

	var buf bytes.Buffer
	if err := flowPageTemplate.Execute(&buf, data); err != nil {
		return re.InternalServerError("Failed to render the page.", err)
	}
	h := re.Response.Header()
	h.Set("Content-Security-Policy", flowPageCSP+"; script-src 'nonce-"+data.Nonce+"'")
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("Referrer-Policy", "no-referrer")
	h.Set("Cache-Control", "no-store")
	h.Set("Content-Type", "text/html; charset=utf-8")
	re.Response.WriteHeader(status)
	_, err := re.Response.Write(buf.Bytes())
	return err
}

var flowPageTemplate = template.Must(template.New("flow").Funcs(brandFuncs).Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<link rel="icon" type="image/svg+xml" href="{{logoLight}}" media="(prefers-color-scheme: light)">
<link rel="icon" type="image/svg+xml" href="{{logoDark}}" media="(prefers-color-scheme: dark)">
<title>Revoked</title>
<style>` + pageTokens + authPageStyle + flowPageStyle + `</style>
</head>
<body class="flow-body">

<header>
<div class="nav">
<div class="brand">
<img class="logo logo-light" src="{{logoLight}}" alt="">
<img class="logo logo-dark" src="{{logoDark}}" alt="">
<span>Revoked</span>
</div>
<div class="tools">
<button class="lang" id="lang-toggle"></button>
<button class="theme" id="theme-toggle" aria-label="Toggle visual theme"></button>
</div>
</div>
</header>

<main>
<div class="hero">
<div class="hero-tile" id="tile"></div>
<div><p class="eyebrow" id="eyebrow"></p><h1 id="title"></h1>
<p class="lead" id="lead"></p></div>
</div>

<div id="error" class="callout" role="alert" hidden><i data-i="alert" data-s="20"></i><span id="error-t"></span></div>
<div id="flow" class="flow"></div>

</main>

<div class="dock" id="dock">
<div class="card" id="auth" hidden>
<p class="dock-t" id="auth-t"></p>
<div id="auth-error" class="callout" role="alert" hidden><i data-i="alert" data-s="20"></i><span id="auth-error-t"></span></div>
<p class="fine left" id="auth-lead"></p>
<label class="field" id="emailRow" hidden><span class="sr-only" data-t="field.email">Email</span>
<input id="email" type="email" autocomplete="username webauthn" data-ph="field.emailPh" placeholder="Email address">
</label>
<label class="field" id="codeRow" hidden><span id="code-l" data-t="field.code">Code</span>
<input id="code" type="text" inputmode="numeric" autocomplete="one-time-code" maxlength="6" placeholder="000000">
</label>
<button id="go" class="big" hidden><span class="spin"></span><span class="big-ic" id="go-ic"></span><span id="go-t"></span></button>
<button id="resend" class="quiet" hidden></button>
<button id="other" class="quiet link" hidden></button>
<p id="auth-note" class="fine"></p>
<div class="alt" id="alt" hidden>
<button id="passkey" class="text-btn" type="button" data-t="auth.otherDevice">Passkey on another device</button>
</div>
<div class="app-choice" id="app-choice" hidden>
<div class="or"><span data-t="auth.or">or</span></div>
<a id="open-app-alt" class="quiet"><img class="logo logo-light app-logo" src="{{logoLight}}" alt=""><img class="logo logo-dark app-logo" src="{{logoDark}}" alt=""><span data-t="app.open">Open in the Revoked app</span></a>
<p class="fine" data-t="app.note">The app checks the server before anything is entered.</p>
</div>
</div>

<div class="app-way" id="app-way" hidden>
<a id="open-app" class="big"><img class="logo logo-light app-logo" src="{{logoLight}}" alt=""><img class="logo logo-dark app-logo" src="{{logoDark}}" alt=""><span data-t="app.open">Open in the Revoked app</span></a>
<p class="fine" data-t="app.note">The app checks the server before anything is entered.</p>
</div>
</div>

<script nonce="{{.Nonce}}">
(function () {
'use strict';
var server = { page: {{.Page}}, problem: {{.Problem}}, data: {{.Data}}, slug: {{.Slug}}, appLink: {{.AppLink}}, originOK: {{.OriginOK}}, signups: {{.Signups}}, verifyEmail: {{.VerifyEmail}} };
` + flowShellScript + `
if (server.page === 'request') {
` + requestPageScript + `
} else if (server.page === 'answers') {
` + answersPageScript + `
} else if (server.page === 'signin') {
` + signInPageScript + `
} else if (server.page === 'connect') {
` + connectPageScript + `
} else if (server.page === 'share') {
` + sharePageScript + `
}
})();
</script>
</body>
</html>`))

const flowPageStyle = `
.flow { display: flex; flex-direction: column; gap: 16px; }
.flow:empty { display: none; }
.section-t { font-size: 13px; font-weight: 650; color: var(--fg-muted); letter-spacing: .02em; }
.fine.left { text-align: left; }
.facts { display: flex; flex-direction: column; border: 1px solid var(--border); border-radius: var(--radius-lg); }
.fact { display: flex; justify-content: space-between; align-items: baseline; gap: 12px; padding: 12px 14px; font-size: 14px; }
.fact + .fact { border-top: 1px solid var(--border); }
.fact-k { color: var(--fg-muted); flex: none; }
.fact-v { text-align: right; overflow-wrap: anywhere; min-width: 0; }
.callout.warn { background: var(--warn-subtle); color: var(--warn); }
.callout.info { background: var(--surface-subtle); color: var(--fg); }
.callout svg { margin-top: 1px; }
.entry { display: flex; flex-direction: column; gap: 8px; padding: 12px 14px; border: 1px solid var(--border); border-radius: var(--radius-lg); }
.entry-h { display: flex; justify-content: space-between; align-items: center; gap: 8px; flex-wrap: wrap; }
.entry-t { font-weight: 650; font-size: 15px; overflow-wrap: anywhere; min-width: 0; }
.entry-reason { color: var(--fg-muted); font-size: 13px; }
.value { padding: 11px 12px; border-radius: var(--radius-md); background: var(--surface-subtle); font-size: 15px; line-height: 1.4; overflow-wrap: anywhere; white-space: pre-wrap; }
.form-row { display: flex; flex-direction: column; gap: 6px; margin-bottom: 6px; }
.form-row-h { display: flex; justify-content: space-between; align-items: center; gap: 8px; }
.form-row-t { font-size: 14px; font-weight: 600; overflow-wrap: anywhere; min-width: 0; }
.form-row-foot { display: flex; flex-wrap: wrap; gap: 4px 12px; font-size: 13px; color: var(--fg-muted); }
.form-row-foot .text-btn { font-size: 13px; }
.value.muted { color: var(--fg-muted); }
.pill { display: inline-flex; align-items: center; gap: 4px; padding: 2px 8px; border-radius: var(--radius-pill); font-size: 12px; font-weight: 600; background: var(--surface-subtle); color: var(--fg-muted); white-space: nowrap; }
.pill.ok { background: var(--ok-subtle); color: var(--ok); }
.pill.warn { background: var(--warn-subtle); color: var(--warn); }
.pill.bad { background: var(--bad-subtle); color: var(--bad); }
.row { display: flex; gap: 8px; flex-wrap: wrap; }
.row > .quiet, .row > .big { flex: 1 1 140px; width: auto; }
.small { min-height: 36px !important; font-size: 14px !important; padding: 6px 12px !important; }
.quiet.danger { color: var(--bad); border-color: color-mix(in srgb, var(--bad) 50%, transparent); }
.text-btn { background: none; border: 0; padding: 0; color: var(--fg-muted); font-size: 13px; text-decoration: underline; text-underline-offset: 3px; cursor: pointer; text-align: left; }
.text-btn:hover { color: var(--fg); }
.flow-body { display: flex; flex-direction: column; }
.flow-body main { flex: 1 0 auto; width: 100%; padding-bottom: 24px; }
@media (min-width: 600px) { .flow-body main { padding-top: 8vh; } }
/* The way to act: sign-in, or the app. After what is asked, at the bottom
   of a short page, so the page reads top to bottom and the account never
   looks like one more question. Not pinned: it is tall enough to cover what
   it follows. Gone once nothing in it is showing. */
.dock {
position: relative;
width: 100%; margin: 0 auto;
background: var(--bg); border-top: 1px solid var(--border);
border-radius: var(--radius-lg) var(--radius-lg) 0 0;
padding: 18px 16px calc(16px + env(safe-area-inset-bottom));
display: flex; flex-direction: column; gap: 14px;
}
.dock:not(:has(> :not([hidden]))) { display: none; }
/* On a wide screen the panel follows the content rather than the window's
   bottom edge, which can be far away; it still sticks when the page scrolls. */
@media (min-width: 600px) {
.flow-body main { flex: 0 0 auto; padding-bottom: 8px; }
.dock { position: static; width: calc(100% - 32px); max-width: 408px; padding: 24px 0 48px; border-radius: 0; background: transparent; }
}

.dock .card { animation: none; gap: 10px; }
.dock-t { font-size: 16px; font-weight: 650; }
.dock .fine.left:empty { display: none; }
.app-way, .app-choice { display: flex; flex-direction: column; gap: 10px; }
.app-way .fine, .app-choice .fine { text-align: center; margin: 0; font-size: 12px; }
.app-logo { width: 18px; height: 18px; border-radius: var(--radius-sm); }
.or { display: flex; align-items: center; gap: 12px; font-size: 13px; color: var(--fg-muted); }
.or::before, .or::after { content: ""; flex: 1; height: 1px; background: var(--border); }
.alt { display: flex; flex-wrap: wrap; justify-content: center; gap: 4px 0; }
.alt > * + *::before { content: "·"; display: inline-block; margin: 0 10px; text-decoration: none; color: var(--fg-muted); }
.alt .text-btn { font-size: 13px; }
.app-way .fine { text-align: left; }
.eyebrow { font-size: 13px; font-weight: 600; color: var(--fg-muted); margin-bottom: 4px; }
.eyebrow:empty { display: none; }
.meta { display: flex; flex-wrap: wrap; align-items: center; row-gap: 4px; font-size: 13px; color: var(--fg-muted); }
.meta > * + *::before { content: "·"; margin: 0 8px; color: var(--fg-muted); }
.meta .text-btn { font-size: 13px; }
.meta > .text-btn::before { display: inline-block; text-decoration: none; }
.asked { margin-top: 12px; }
.asked { display: flex; flex-direction: column; }
.asked-h { display: flex; justify-content: space-between; align-items: center; gap: 12px; padding-bottom: 10px; border-bottom: 1px solid var(--border); }
.asked-h .section-t { font-size: 13px; color: var(--fg); }
.asked-hint { display: inline-flex; align-items: center; gap: 6px; font-size: 13px; color: var(--fg-muted); white-space: nowrap; }
.asked-row { display: flex; justify-content: space-between; align-items: center; gap: 12px; padding: 11px 0; border-bottom: 1px solid var(--border); }
.asked-row .entry-t { font-weight: 600; font-size: 15px; }
.asked-row:last-child { border-bottom: 0; }
.summary { border-top: 1px solid var(--border); margin-top: 0; }
.summary .asked-row:last-child { border-bottom: 1px solid var(--border); }
.summary-v { font-size: 15px; overflow-wrap: anywhere; white-space: pre-wrap; }
.summary-v.muted { color: var(--fg-muted); }
.entry .summary { margin: 4px 0; }
.entry .summary .asked-row:last-child { border-bottom: 0; }
.edit-row { padding: 12px 0; border-bottom: 1px solid var(--border); margin: 0; }
.flow > .asked-h { margin-top: 8px; }
.flow > .asked-h + .asked, .flow > .asked-h + .form-row { margin-top: -6px; }
.choices > :first-child { padding-top: 8px; }
#passkey.loading .spin { display: block; }
#passkey.loading .big-ic { display: none; }
.tag { flex: none; font-size: 12px; font-weight: 600; padding: 2px 8px; border-radius: var(--radius-pill); background: var(--surface-subtle); color: var(--fg-muted); }
.locked { display: flex; flex-direction: column; border: 1px solid var(--border); border-radius: var(--radius-lg); }
.locked-row { display: flex; justify-content: space-between; align-items: center; gap: 12px; padding: 12px 14px; }
.locked-row + .locked-row { border-top: 1px solid var(--border); }
.locked-row svg { color: var(--fg-muted); }
.locked-t { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.check-row { display: flex; gap: 12px; align-items: flex-start; padding: 12px 14px; border: 1px solid var(--border); border-radius: var(--radius-lg); cursor: pointer; }
.check-row input { width: 18px; height: 18px; margin-top: 2px; flex: none; accent-color: var(--primary); }
.check-row input:disabled + .check-t { opacity: .6; }
.check-t { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.choices .check-row { border: 0; border-radius: 0; border-bottom: 1px solid var(--border); padding: 12px 0; }
.choices .check-row:last-child { border-bottom: 0; }
.choices > .pick-row, .choices > .flow { padding: 12px 0; margin: 0; border-bottom: 1px solid var(--border); }
.choices > :last-child { border-bottom: 0; }
.choices > .flow .check-row { border: 0; padding: 0; }
.check-reason { font-size: 13px; color: var(--fg-muted); font-style: italic; margin-top: 2px; overflow-wrap: anywhere; }
select { width: 100%; height: 44px; padding: 0 10px; font: inherit; font-size: 15px; color: var(--fg); background: var(--field); border: 1px solid var(--control); border-radius: var(--radius-md); }
.quote { padding: 10px 14px; border-left: 3px solid var(--border); color: var(--fg-muted); font-size: 14px; overflow-wrap: anywhere; }
textarea {
width: 100%; min-height: 44px; padding: 10px 12px; resize: none; overflow: hidden; line-height: 1.4;
font: inherit; font-size: 16px; color: var(--fg);
background: var(--field); border: 1px solid var(--control); border-radius: var(--radius-md);
}
textarea:focus { outline: none; border-color: var(--fg); box-shadow: 0 0 0 3px color-mix(in srgb, var(--fg) 15%, transparent); }
`
