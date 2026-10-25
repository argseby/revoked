package routes

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"html/template"

	"revoked/cmd/revoked/server"

	"github.com/pocketbase/pocketbase/core"
)

// The hand-off page fetches nothing and leaves only by opening the app.
const oidcPageCSP = passkeyPageCSP

type oidcPageData struct {
	// Why the page cannot go on; empty when it can.
	Problem string
	// The service's origin.
	Client string
	// The revoked://signin link that carries the request to the app.
	AppLink string
	Nonce   string
}

func renderOIDCPage(re *core.RequestEvent, root *server.RootKey, data oidcPageData, status int) error {
	nonceBytes := make([]byte, 16)
	if _, err := rand.Read(nonceBytes); err != nil {
		return re.InternalServerError("Failed to render the page.", err)
	}
	data.Nonce = base64.StdEncoding.EncodeToString(nonceBytes)

	var buf bytes.Buffer
	if err := oidcPageTemplate.Execute(&buf, data); err != nil {
		return re.InternalServerError("Failed to render the page.", err)
	}
	h := re.Response.Header()
	h.Set("Content-Security-Policy", oidcPageCSP+"; script-src 'nonce-"+data.Nonce+"'")
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("Referrer-Policy", "no-referrer")
	h.Set("Cache-Control", "no-store")
	h.Set("Content-Type", "text/html; charset=utf-8")
	re.Response.WriteHeader(status)
	_, err := re.Response.Write(buf.Bytes())
	return err
}

var oidcPageTemplate = template.Must(template.New("oidc").Funcs(brandFuncs).Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<link rel="icon" type="image/svg+xml" href="{{logoLight}}" media="(prefers-color-scheme: light)">
<link rel="icon" type="image/svg+xml" href="{{logoDark}}" media="(prefers-color-scheme: dark)">
<title>Sign in with Revoked</title>
<style>
:root {
color-scheme: light dark;
--bg: #f4f6fb; --card: #ffffff; --border: #dde1e8; --fg: #191c20; --fg-muted: #555b64;
--primary: #35618e; --primary-subtle: #d8e7fb; --primary-fg: #ffffff;
--bad: #ba1a1a; --bad-subtle: #ffdad6;
--shadow: 0 1px 2px rgba(16, 24, 40, .04), 0 4px 16px rgba(16, 24, 40, .06);
}
@media (prefers-color-scheme: dark) {
:root {
--bg: #0f1216; --card: #181c21; --border: #2c3137; --fg: #e3e5ea; --fg-muted: #a9aeb7;
--primary: #a0cafd; --primary-subtle: #1c3b5c; --primary-fg: #003258;
--bad: #ffb4ab; --bad-subtle: #5c1512; --shadow: none;
}
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: var(--bg); color: var(--fg); font: 15px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; min-height: 100vh; -webkit-font-smoothing: antialiased; }
header { border-bottom: 1px solid var(--border); }
.nav { max-width: 640px; margin: 0 auto; padding: 10px 16px; display: flex; align-items: center; justify-content: space-between; }
.brand { display: flex; align-items: center; gap: 8px; font-weight: 700; font-size: 16px; }
.logo { width: 24px; height: 24px; border-radius: 6px; }
.logo-dark { display: none; }
@media (prefers-color-scheme: dark) { .logo-light { display: none; } .logo-dark { display: block; } }
.lang { min-width: 38px; height: 38px; padding: 0 10px; border-radius: 11px; border: 1px solid var(--border); background: var(--card); color: var(--fg); font: inherit; font-size: 13px; font-weight: 650; cursor: pointer; }
main { max-width: 440px; margin: 0 auto; padding: 18px 16px 40px; display: flex; flex-direction: column; gap: 16px; }
@media (min-width: 600px) { main { padding-top: 10vh; } }
h1 { font-size: 22px; font-weight: 650; line-height: 1.25; overflow-wrap: anywhere; }
.lead { color: var(--fg-muted); font-size: 14px; overflow-wrap: anywhere; }
.card { background: var(--card); border: 1px solid var(--border); border-radius: 18px; box-shadow: var(--shadow); padding: 16px; display: flex; flex-direction: column; gap: 12px; }
.asks { list-style: none; display: flex; flex-direction: column; gap: 10px; }
.asks li { display: flex; gap: 10px; align-items: flex-start; }
.asks input[type=checkbox] { margin-top: 3px; width: 18px; height: 18px; accent-color: var(--primary); flex: none; }
.ask-t { font-weight: 600; }
.ask-v { color: var(--fg-muted); font-size: 13px; overflow-wrap: anywhere; }
select { width: 100%; height: 44px; padding: 0 10px; margin-top: 4px; font: inherit; color: var(--fg); background: var(--bg); border: 1px solid var(--border); border-radius: 12px; }
.callout { padding: 12px 14px; border-radius: 14px; background: var(--bad-subtle); color: var(--bad); font-size: 14px; }
.big, .quiet { display: flex; align-items: center; justify-content: center; text-decoration: none; width: 100%; min-height: 50px; border-radius: 15px; font: inherit; font-size: 16px; font-weight: 650; cursor: pointer; }
.big { border: 0; background: var(--primary); color: var(--primary-fg); }
.big:disabled { opacity: .7; cursor: progress; }
.quiet { border: 1px solid var(--border); background: transparent; color: var(--fg); font-weight: 600; }
.big:focus-visible, .quiet:focus-visible, .lang:focus-visible, select:focus-visible { outline: 2px solid var(--primary); outline-offset: 2px; }
.fine { text-align: center; color: var(--fg-muted); font-size: 12px; }
[hidden] { display: none !important; }
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
<button class="lang" id="lang-toggle"></button>
</div>
</header>
<main>
<div>
<h1 id="title"></h1>
<p class="lead" id="lead"></p>
</div>
<div class="card">
<div id="error" class="callout" role="alert" hidden></div>
<a id="go" class="big" hidden></a>
<p class="fine" id="note"></p>
</div>
</main>
<script nonce="{{.Nonce}}">
(function () {
'use strict';
var server = { problem: {{.Problem}}, client: {{.Client}}, appLink: {{.AppLink}} };
var $ = function (id) { return document.getElementById(id); };
var show = function (n, on) { n.hidden = !on; };

var STRINGS = {
  en: {
    'lang.label': 'DE', 'title': 'Sign in to {0}', 'title.problem': 'Signing in cannot continue',
    'lead': '{0} asks to sign you in with Revoked. You decide in the Revoked app what {0} learns.',
    'go': 'Open the Revoked app',
    'note': 'Nothing happened? The Revoked app is needed to sign in. Install it on this device, then open this page again.',
    'problem.client': 'This service did not identify itself correctly, so signing in cannot continue. Nothing was shared.'
  },
  de: {
    'lang.label': 'EN', 'title': 'Bei {0} anmelden', 'title.problem': 'Die Anmeldung kann nicht fortgesetzt werden',
    'lead': '{0} möchte dich mit Revoked anmelden. In der Revoked-App entscheidest du, was {0} erfährt.',
    'go': 'Revoked-App öffnen',
    'note': 'Nichts passiert? Zum Anmelden wird die Revoked-App gebraucht. Installiere sie auf diesem Gerät und öffne diese Seite dann erneut.',
    'problem.client': 'Dieser Dienst hat sich nicht korrekt ausgewiesen, daher kann die Anmeldung nicht fortgesetzt werden. Es wurde nichts geteilt.'
  }
};
var LANG_KEY = 'revoked.web.locale';
var lang = 'en';
try { lang = localStorage.getItem(LANG_KEY) || ''; } catch (e) {}
if (!STRINGS[lang]) lang = /^de\b/i.test(navigator.language || '') ? 'de' : 'en';
function t(key) {
  var s = STRINGS[lang][key] || STRINGS.en[key] || key;
  for (var i = 1; i < arguments.length; i++) s = s.split('{' + (i - 1) + '}').join(arguments[i]);
  return s;
}
var host = server.client.replace(/^https?:\/\//, '');

function redraw() {
  document.documentElement.lang = lang;
  $('lang-toggle').textContent = t('lang.label');
  if (server.problem) {
    $('title').textContent = t('title.problem');
    $('lead').textContent = '';
    $('error').textContent = t('problem.' + server.problem);
    show($('error'), true);
    show($('go'), false);
    $('note').textContent = '';
    return;
  }
  $('title').textContent = t('title', host);
  $('lead').textContent = t('lead', host);
  $('go').textContent = t('go');
  show($('go'), true);
  $('note').textContent = t('note');
}
$('lang-toggle').addEventListener('click', function () {
  lang = lang === 'de' ? 'en' : 'de';
  try { localStorage.setItem(LANG_KEY, lang); } catch (e) {}
  redraw();
});
redraw();
if (!server.problem) {
  // The request goes on in the app; this page decides nothing.
  $('go').href = server.appLink;
  location.href = server.appLink;
}
})();
</script>
</body>
</html>
`))
