package routes

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"html/template"

	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// The sign-in page talks to its own origin and nothing else.
const passkeyPageCSP = "default-src 'none'; " +
	"style-src 'unsafe-inline'; " +
	"img-src data:; " +
	"connect-src 'self'; " +
	"base-uri 'none'; form-action 'none'; frame-ancestors 'none'"

type passkeyPageData struct {
	// Whether a passkey can be bound to the address the page was reached at.
	OriginOK bool
	// Whether anyone may make their own account here.
	Signups bool
	// Whether a new account confirms its address with a mailed code first.
	VerifyEmail bool
	// The account a ticket in the address is for; empty when it names none.
	TicketEmail string
	Nonce       string
}

// servePasskeyPage renders the one page a passkey ceremony runs on. What to do
// — sign in, make an account, redeem a ticket — and where the result goes are
// read from the address by the page itself; the server only says what is
// possible here.
func servePasskeyPage(app core.App, re *core.RequestEvent, root *server.RootKey) error {
	nonceBytes := make([]byte, 16)
	if _, err := rand.Read(nonceBytes); err != nil {
		return re.InternalServerError("Failed to render the page.", err)
	}
	nonce := base64.StdEncoding.EncodeToString(nonceBytes)

	_, _, originOK := util.PasskeyRelyingParty(pageOrigin(re, root))
	data := passkeyPageData{
		OriginOK:    originOK,
		Signups:     util.SignupsAllowed(),
		VerifyEmail: util.SignupEmailVerification(),
		Nonce:       nonce,
	}
	if ticket := re.Request.URL.Query().Get("ticket"); ticket != "" && allowRequest(re, passkeyLimiter, "") {
		if _, account, err := services.FindPasskeyTicket(app, ticket); err == nil {
			data.TicketEmail = account.Email()
		}
	}

	var buf bytes.Buffer
	if err := passkeyPageTemplate.Execute(&buf, data); err != nil {
		return re.InternalServerError("Failed to render the page.", err)
	}
	h := re.Response.Header()
	h.Set("Content-Security-Policy", passkeyPageCSP+"; script-src 'nonce-"+nonce+"'")
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("Referrer-Policy", "no-referrer")
	h.Set("Cache-Control", "no-store")
	return writeText(re, "text/html", buf.String())
}

var passkeyPageTemplate = template.Must(template.New("passkey").Funcs(brandFuncs).Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<link rel="icon" type="image/svg+xml" href="{{logoLight}}" media="(prefers-color-scheme: light)">
<link rel="icon" type="image/svg+xml" href="{{logoDark}}" media="(prefers-color-scheme: dark)">
<title>Sign in · Revoked</title>
<style>
:root {
--font-sans: system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
--ease: cubic-bezier(.2, .8, .2, 1);
}

:root,
html[data-theme="light"] {
color-scheme: light;
--bg: #f4f6fb;
--card: #ffffff;
--surface-subtle: #eceef4;
--border: #dde1e8;
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
--shadow: 0 1px 2px rgba(16, 24, 40, .04), 0 4px 16px rgba(16, 24, 40, .06);
}

html[data-theme="dark"] {
color-scheme: dark;
--bg: #0f1216;
--card: #181c21;
--surface-subtle: #24282e;
--border: #2c3137;
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
--shadow: none;
}

@media (prefers-color-scheme: dark) {
html:not([data-theme="light"]) {
color-scheme: dark;
--bg: #0f1216;
--card: #181c21;
--surface-subtle: #24282e;
--border: #2c3137;
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
.logo { width: 24px; height: 24px; border-radius: 6px; }
.logo-dark { display: none; }
html[data-theme="dark"] .logo-light { display: none; }
html[data-theme="dark"] .logo-dark { display: block; }
@media (prefers-color-scheme: dark) {
html:not([data-theme="light"]) .logo-light { display: none; }
html:not([data-theme="light"]) .logo-dark { display: block; }
}
.tools { display: flex; gap: 8px; }
.theme, .lang {
min-width: 38px; height: 38px; border-radius: 11px; border: 1px solid var(--border);
background: var(--card); color: var(--fg); cursor: pointer;
display: inline-flex; align-items: center; justify-content: center;
}
.lang { padding: 0 10px; font-size: 13px; font-weight: 650; letter-spacing: .04em; }

.steps { display: flex; flex-direction: column; gap: 8px; }
.steps-t { font-size: 13px; font-weight: 600; color: var(--fg-muted); }
.steps ol { list-style: none; display: grid; grid-auto-flow: column; grid-auto-columns: 1fr; gap: 6px; }
.steps li { height: 4px; border-radius: 2px; background: var(--border); transition: background .3s; }
.steps li.done { background: var(--primary); }
.steps li.now { background: color-mix(in srgb, var(--primary) 55%, var(--border)); }

main {
max-width: 440px;
margin: 0 auto;
padding: 18px 16px calc(40px + env(safe-area-inset-bottom));
display: flex;
flex-direction: column;
gap: 16px;
}
@media (min-width: 600px) { main { padding-top: 12vh; gap: 18px; } }

.hero { display: flex; align-items: center; gap: 14px; }
.hero-tile {
width: 48px; height: 48px; border-radius: 15px; flex: none;
display: flex; align-items: center; justify-content: center;
background: var(--primary-subtle); color: var(--primary);
transition: background .3s, color .3s;
}
.hero-tile.ok { background: var(--ok-subtle); color: var(--ok); }
.hero-tile.warn { background: var(--warn-subtle); color: var(--warn); }
.hero-tile.bad { background: var(--bad-subtle); color: var(--bad); }
.hero-tile svg { animation: pop .3s var(--ease); }
.hero h1 { font-size: 21px; font-weight: 650; line-height: 1.25; letter-spacing: -0.015em; }
@media (min-width: 600px) { .hero h1 { font-size: 24px; } }
.lead { color: var(--fg-muted); font-size: 14px; line-height: 1.45; margin-top: 2px; overflow-wrap: anywhere; }
.lead:empty { display: none; }

.card {
background: var(--card);
border: 1px solid var(--border);
border-radius: 18px;
box-shadow: var(--shadow);
padding: 16px;
display: flex;
flex-direction: column;
gap: 12px;
animation: rise .4s var(--ease) both;
}

.callout {
display: flex; gap: 12px; align-items: flex-start;
padding: 14px; border-radius: 14px;
background: var(--bad-subtle); color: var(--bad);
font-size: 14px; line-height: 1.45;
}

.field { display: flex; flex-direction: column; gap: 6px; font-size: 13px; font-weight: 600; color: var(--fg-muted); }
input {
width: 100%; height: 50px; padding: 0 14px;
font: inherit; font-size: 16px; font-weight: 400; color: var(--fg);
background: var(--bg); border: 1px solid var(--border); border-radius: 14px;
transition: border-color .15s, box-shadow .15s;
}
input::placeholder { color: var(--fg-muted); opacity: .7; }
input:focus { outline: none; border-color: var(--primary); box-shadow: 0 0 0 3px var(--primary-subtle); }
#code { font-size: 22px; letter-spacing: .4em; font-variant-numeric: tabular-nums; text-align: center; }
.quiet:disabled { cursor: default; opacity: .6; }

.big, .quiet {
width: 100%; min-height: 54px; border-radius: 15px;
font-size: 16px; font-weight: 650;
display: flex; align-items: center; justify-content: center; gap: 10px;
padding: 12px 16px; text-align: center;
cursor: pointer; text-decoration: none;
transition: transform .12s var(--ease), filter .15s, background .15s;
}
.big { border: 0; background: var(--primary); color: var(--primary-fg); }
.big:hover { filter: brightness(1.06); }
.quiet { min-height: 48px; border: 1px solid var(--border); background: transparent; color: var(--fg); font-size: 15px; font-weight: 600; }
.quiet:hover { background: var(--surface-subtle); }
.big:active, .quiet:active { transform: scale(.985); }
.big:disabled { cursor: progress; opacity: .75; }
.big:focus-visible, .quiet:focus-visible, .theme:focus-visible, .lang:focus-visible { outline: 2px solid var(--primary); outline-offset: 2px; }
.spin { width: 18px; height: 18px; border-radius: 50%; border: 2px solid currentColor; border-right-color: transparent; animation: spin .7s linear infinite; display: none; flex: none; }
.big.loading .spin { display: block; }
.big.loading .big-ic { display: none; }
.big-logo { width: 24px; height: 24px; }

.fine { text-align: center; color: var(--fg-muted); font-size: 12px; line-height: 1.45; }
/* The way to the other mode, while creating an account: a quiet text link
   for a wrong tap, not a second choice beside the step being taken. */
.quiet.link { min-height: 44px; border: 0; font-size: 13px; font-weight: 500; color: var(--fg-muted); text-decoration: underline; text-underline-offset: 3px; }
.quiet.link:hover { background: transparent; color: var(--fg); }
.fine:empty { display: none; }
[hidden] { display: none !important; }

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
<div class="steps" id="steps" hidden>
<span class="steps-t" id="steps-t"></span>
<ol id="steps-bar" aria-hidden="true"></ol>
</div>

<div class="hero">
<div class="hero-tile" id="tile"></div>
<div style="min-width: 0;">
<h1 id="title">Sign in</h1>
<p class="lead" id="lead"></p>
</div>
</div>

<div class="card" id="card">
<div id="error" class="callout" role="alert" hidden><i data-i="alert" data-s="20"></i><span id="error-t"></span></div>
<label class="field" id="emailRow" hidden><span data-t="field.email">Email</span>
<input id="email" type="email" autocomplete="email" placeholder="name@example.com">
</label>
<label class="field" id="codeRow" hidden><span data-t="field.code">Confirmation code</span>
<input id="code" type="text" inputmode="numeric" autocomplete="one-time-code" maxlength="6" placeholder="000000">
</label>
<button id="go" class="big" hidden><span class="spin"></span><span class="big-ic" id="go-ic"></span><span id="go-t"></span></button>
<button id="resend" class="quiet" hidden></button>
<button id="other" class="quiet" hidden></button>
<a id="open" class="big" hidden><img class="logo logo-light big-logo" src="{{logoLight}}" alt=""><img class="logo logo-dark big-logo" src="{{logoDark}}" alt=""><span data-t="open">Open Revoked</span></a>
<p id="note" class="fine"></p>
</div>
</main>

<script nonce="{{.Nonce}}">
(function () {
'use strict';
var server = { originOK: {{.OriginOK}}, signups: {{.Signups}}, verifyEmail: {{.VerifyEmail}}, ticketEmail: {{.TicketEmail}} };
var query = new URLSearchParams(location.search);
var pkce = /^[A-Za-z0-9._~-]{43,128}$/.test(query.get('challenge') || '') ? query.get('challenge') : '';
var state = /^[A-Za-z0-9._~-]{1,128}$/.test(query.get('state') || '') ? query.get('state') : '';
var ticket = query.get('ticket') || '';
var mode = ticket ? 'enroll' : (query.get('mode') === 'signup' ? 'signup' : 'signin');

var $ = function (id) { return document.getElementById(id); };
function show(el, on) { el.hidden = !on; }

// ---- Language: English and German, like the tools around revoked ---------
// Both catalogues are here: the page loads nothing but its own origin. The
// server's refusals carry a code, so they are said in the page's language
// too; one this page does not know keeps the server's English.
var STRINGS = {
  en: {
    'lang.label': 'DE', 'lang.switch': 'Auf Deutsch wechseln',
    'theme.light': 'Switch to light theme', 'theme.dark': 'Switch to dark theme',
    'field.email': 'Email', 'field.code': 'Confirmation code', 'open': 'Open Revoked',
    'step': function (n, total, label) { return 'Step ' + n + ' of ' + total + ' · ' + label; },
    'step.email': 'Your email', 'step.code': 'Confirm email', 'step.passkey': 'Save passkey',
    'step.name': 'Your name, in the app',
    'left.2m': 'about 2 minutes left', 'left.1m': 'about a minute left',
    'left.lt1m': 'less than a minute left', 'left.last': 'last step',
    'signin.title': 'Sign in', 'signin.lead': 'Use the passkey saved on this device. It takes about 10 seconds.',
    'signin.fromApp': 'Start from the Revoked app: it opens this page and takes you back signed in.',
    'signin.go': 'Sign in with a passkey', 'signin.other': 'Create an account',
    'signin.noPasskey': 'No passkey yet? Ask whoever runs this server for a link to add one.',
    'signup.title': 'Create an account',
    'signup.leadCode': 'Your email first: we send a 6-digit code to check it is yours. There is no password.',
    'signup.lead': 'Your email first. There is no password: a passkey on this device signs you in.',
    'signup.sendCode': 'Send code', 'signup.create': 'Continue', 'signup.other': 'Tapped the wrong button? Sign in instead',
    'code.title': 'Confirm your email',
    'code.lead': function (email) { return 'Enter the 6-digit code we sent to ' + email + '.'; },
    'code.go': 'Continue',
    'code.note': 'No email? Check your spam folder. The code works for 10 minutes.',
    'code.resendIn': function (s) { return 'Send a new code in ' + s + ' s'; },
    'code.resend': 'Send a new code',
    'passkey.title': 'Save your passkey',
    'passkey.lead': function (host) { return 'Your device will ask to save a passkey for ' + host + '. From now on your fingerprint, face or device PIN signs you in, and there is nothing to remember.'; },
    'passkey.go': 'Create passkey',
    'enroll.title': 'Add a passkey',
    'enroll.lead': function (email) { return 'For ' + email + '. It is saved on this device and is how you sign in from now on.'; },
    'enroll.dead': 'This link no longer works',
    'enroll.deadLead': 'It is unknown, already used, or has expired. Ask for a new one.',
    'done.signedIn': 'Signed in', 'done.created': 'Account created',
    'done.returning': 'Returning to Revoked…',
    'done.next': 'Returning to Revoked for the last step: the name others see.',
    'done.close': 'You can close this page once the app has opened.',
    'done.saved': 'Passkey saved', 'done.savedLead': 'Open Revoked on this device and sign in with it.',
    'done.closeNow': 'You can close this page.',
    'stop.title': 'Passkeys unavailable',
    'stop.origin': 'Passkeys only work at this server’s own address.',
    'stop.browser': 'This browser does not support passkeys.',
    'err.codeFormat': 'Enter the 6-digit code from the email.',
    'err.exists': 'This device already has a passkey for this account.',
    'err.refused': 'The server refused the request.', 'err.generic': 'Something went wrong.'
  },
  de: {
    'lang.label': 'EN', 'lang.switch': 'Switch to English',
    'theme.light': 'Zum hellen Design wechseln', 'theme.dark': 'Zum dunklen Design wechseln',
    'field.email': 'E-Mail', 'field.code': 'Bestätigungscode', 'open': 'Revoked öffnen',
    'step': function (n, total, label) { return 'Schritt ' + n + ' von ' + total + ' · ' + label; },
    'step.email': 'Deine E-Mail', 'step.code': 'E-Mail bestätigen', 'step.passkey': 'Passkey speichern',
    'step.name': 'Dein Name, in der App',
    'left.2m': 'noch etwa 2 Minuten', 'left.1m': 'noch etwa eine Minute',
    'left.lt1m': 'noch weniger als eine Minute', 'left.last': 'letzter Schritt',
    'signin.title': 'Anmelden', 'signin.lead': 'Mit dem Passkey, der auf diesem Gerät gespeichert ist. Dauert etwa 10 Sekunden.',
    'signin.fromApp': 'Starte in der Revoked-App: Sie öffnet diese Seite und bringt dich angemeldet zurück.',
    'signin.go': 'Mit Passkey anmelden', 'signin.other': 'Konto erstellen',
    'signin.noPasskey': 'Noch kein Passkey? Bitte die Person, die diesen Server betreibt, um einen Link dafür.',
    'signup.title': 'Konto erstellen',
    'signup.leadCode': 'Zuerst deine E-Mail: Wir schicken einen 6-stelligen Code, um zu prüfen, dass sie dir gehört. Es gibt kein Passwort.',
    'signup.lead': 'Zuerst deine E-Mail. Es gibt kein Passwort: Ein Passkey auf diesem Gerät meldet dich an.',
    'signup.sendCode': 'Code senden', 'signup.create': 'Weiter', 'signup.other': 'Falschen Knopf erwischt? Stattdessen anmelden',
    'code.title': 'E-Mail bestätigen',
    'code.lead': function (email) { return 'Gib den 6-stelligen Code ein, den wir an ' + email + ' geschickt haben.'; },
    'code.go': 'Weiter',
    'code.note': 'Keine E-Mail? Schau im Spam-Ordner nach. Der Code gilt 10 Minuten.',
    'code.resendIn': function (s) { return 'Neuen Code senden in ' + s + ' s'; },
    'code.resend': 'Neuen Code senden',
    'passkey.title': 'Passkey speichern',
    'passkey.lead': function (host) { return 'Dein Gerät fragt, ob es einen Passkey für ' + host + ' speichern soll. Ab jetzt meldet dich dein Fingerabdruck, dein Gesicht oder die Geräte-PIN an, und du musst dir nichts merken.'; },
    'passkey.go': 'Passkey erstellen',
    'enroll.title': 'Passkey hinzufügen',
    'enroll.lead': function (email) { return 'Für ' + email + '. Er wird auf diesem Gerät gespeichert; damit meldest du dich ab jetzt an.'; },
    'enroll.dead': 'Dieser Link funktioniert nicht mehr',
    'enroll.deadLead': 'Er ist unbekannt, schon benutzt oder abgelaufen. Bitte um einen neuen.',
    'done.signedIn': 'Angemeldet', 'done.created': 'Konto erstellt',
    'done.returning': 'Zurück zu Revoked …',
    'done.next': 'Zurück zu Revoked für den letzten Schritt: den Namen, den andere sehen.',
    'done.close': 'Du kannst diese Seite schließen, sobald sich die App geöffnet hat.',
    'done.saved': 'Passkey gespeichert', 'done.savedLead': 'Öffne Revoked auf diesem Gerät und melde dich damit an.',
    'done.closeNow': 'Du kannst diese Seite schließen.',
    'stop.title': 'Passkeys nicht verfügbar',
    'stop.origin': 'Passkeys funktionieren nur unter der eigenen Adresse dieses Servers.',
    'stop.browser': 'Dieser Browser unterstützt keine Passkeys.',
    'err.codeFormat': 'Gib den 6-stelligen Code aus der E-Mail ein.',
    'err.exists': 'Dieses Gerät hat schon einen Passkey für dieses Konto.',
    'err.refused': 'Der Server hat die Anfrage abgelehnt.', 'err.generic': 'Etwas ist schiefgelaufen.',
    'server.signups_disabled': 'Dieser Server nimmt keine neuen Registrierungen an.',
    'server.rate_limited': 'Zu viele Versuche. Warte kurz und versuche es noch einmal.',
    'server.passkey_request_invalid': 'Die Anfrage ist fehlerhaft.',
    'server.passkey_email_invalid': 'Gib eine gültige E-Mail-Adresse ein.',
    'server.passkey_email_taken': 'Für diese E-Mail-Adresse gibt es schon ein Konto. Melde dich stattdessen an.',
    'server.passkey_ticket_invalid': 'Dieser Link ist unbekannt, schon benutzt oder abgelaufen. Bitte um einen neuen.',
    'server.passkey_ceremony_invalid': 'Das hat zu lange gedauert oder war schon abgeschlossen. Fang noch einmal an.',
    'server.passkey_verification_failed': 'Der Passkey konnte nicht geprüft werden.',
    'server.email_verification_off': 'Dieser Server bestätigt keine E-Mail-Adressen. Erstelle das Konto direkt.',
    'server.email_verification_required': 'Bestätige zuerst deine E-Mail-Adresse mit dem Code, den wir geschickt haben.',
    'server.email_code_invalid': 'Dieser Code ist falsch, abgelaufen oder wurde zu oft versucht. Fordere einen neuen an.',
    'server.email_code_too_soon': 'Gerade wurde ein Code an diese Adresse geschickt. Warte eine Minute, bevor du einen neuen anforderst.',
    'server.email_send_failed': 'Die Bestätigungs-E-Mail konnte nicht gesendet werden. Versuche es später noch einmal.'
  }
};
// The key the web tools use, so a choice made there holds here on the same
// origin.
var LANG_KEY = 'revoked.web.locale';
var lang = (function () {
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
function serverMessage(data) {
  return (data.code && STRINGS[lang]['server.' + data.code]) || data.message || t('err.refused');
}

// Icons are drawn here rather than fetched: the page loads nothing but its
// own origin.
var ICONS = {
  'key': '<circle cx="7.5" cy="15.5" r="5.5"/><path d="m21 2-9.6 9.6M15.5 7.5l3 3L22 7l-3-3"/>',
  'user-plus': '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M19 8v6M22 11h-6"/>',
  'smartphone': '<rect x="5" y="2" width="14" height="20" rx="2"/><path d="M12 18h.01"/>',
  'alert': '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3z"/><path d="M12 9v4M12 17h.01"/>',
  'check': '<path d="M20 6 9 17l-5-5"/>',
  'mail': '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/>',
  'arrow-right': '<path d="M5 12h14M12 5l7 7-7 7"/>',
  'sun': '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/>',
  'moon': '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>'
};
function svg(name, size) {
  var s = size || 18;
  var box = document.createElement('span');
  box.innerHTML = '<svg width="' + s + '" height="' + s + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (ICONS[name] || '') + '</svg>';
  return box.firstChild;
}
Array.prototype.forEach.call(document.querySelectorAll('i[data-i]'), function (n) {
  n.replaceWith(svg(n.getAttribute('data-i'), Number(n.getAttribute('data-s')) || 18));
});

// ---- Theme: shared with the link pages on this origin --------------------
var themeToggle = $('theme-toggle');
function isDark() {
  var current = document.documentElement.getAttribute('data-theme');
  if (current === 'dark') return true;
  if (current === 'light') return false;
  return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
}
function updateToggle() {
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
themeToggle.addEventListener('click', function () {
  var next = isDark() ? 'light' : 'dark';
  try { localStorage.setItem('revoked_theme', next); } catch (e) {}
  applyTheme(next);
});
if (window.matchMedia) {
  var mq = window.matchMedia('(prefers-color-scheme: dark)');
  if (mq.addEventListener) mq.addEventListener('change', updateToggle);
  else if (mq.addListener) mq.addListener(updateToggle);
}

// What is on screen, drawn again when the language changes: the form, a
// result, or a stop.
var redraw = function () {};
function applyLang() {
  document.documentElement.lang = lang;
  Array.prototype.forEach.call(document.querySelectorAll('[data-t]'), function (n) {
    n.textContent = t(n.getAttribute('data-t'));
  });
  $('lang-toggle').textContent = t('lang.label');
  $('lang-toggle').setAttribute('aria-label', t('lang.switch'));
  updateToggle();
}
$('lang-toggle').addEventListener('click', function () {
  lang = lang === 'de' ? 'en' : 'de';
  try { localStorage.setItem(LANG_KEY, lang); } catch (e) {}
  applyLang();
  redraw();
});
applyLang();

// ---- Layout helpers ------------------------------------------------------
function heading(title, lead, icon, tone) {
  $('title').textContent = title;
  $('lead').textContent = lead || '';
  document.title = title + ' · Revoked';
  var tile = $('tile');
  tile.className = 'hero-tile' + (tone ? ' ' + tone : '');
  tile.textContent = '';
  tile.appendChild(svg(icon, 24));
}
function action(label, icon) {
  $('go-t').textContent = label;
  $('go-ic').textContent = '';
  $('go-ic').appendChild(svg(icon, 20));
}
// Where a new account is in its setup: a numbered step with a bar and the
// time left, so it is clear how much is to come. The count includes the last
// step, the name, which the app asks once this page sends the person back:
// the app's welcome screen announced the same steps before opening this page.
var STEP_NAMES = server.verifyEmail
  ? ['step.email', 'step.code', 'step.passkey', 'step.name']
  : ['step.email', 'step.passkey', 'step.name'];
var STEP_LEFT = server.verifyEmail
  ? ['left.2m', 'left.1m', 'left.lt1m', 'left.last']
  : ['left.1m', 'left.lt1m', 'left.last'];
function steps(at) {
  var names = STEP_NAMES;
  if (!at) { show($('steps'), false); return; }
  var bar = $('steps-bar');
  bar.textContent = '';
  names.forEach(function (_, i) {
    var li = document.createElement('li');
    if (i + 1 < at) li.className = 'done';
    else if (i + 1 === at) li.className = 'now';
    bar.appendChild(li);
  });
  $('steps-t').textContent = at > names.length ? '' :
    t('step', at, names.length, t(names[at - 1])) + ' · ' + t(STEP_LEFT[at - 1]);
  show($('steps-t'), at <= names.length);
  show($('steps'), true);
}
function fail(message) { $('error-t').textContent = message; show($('error'), true); }
// Says the page cannot go on, with nothing left to press.
function stop(titleKey, messageKey) {
  redraw = function () {
    show($('error'), false);
    heading(t(titleKey), '', 'alert', 'bad');
    fail(t(messageKey));
  };
  redraw();
}

// A passkey cannot be bound to an IP address; on a development machine the
// same server answers at localhost.
if (!server.originOK) {
  if (/^(127\.0\.0\.1|\[::1\])$/.test(location.hostname)) {
    location.replace(location.protocol + '//localhost' + (location.port ? ':' + location.port : '') +
      location.pathname + location.search);
    return;
  }
  stop('stop.title', 'stop.origin');
  return;
}
if (!window.PublicKeyCredential) {
  stop('stop.title', 'stop.browser');
  return;
}

function decode(s) {
  var b = atob(s.replace(/-/g, '+').replace(/_/g, '/'));
  var out = new Uint8Array(b.length);
  for (var i = 0; i < b.length; i++) out[i] = b.charCodeAt(i);
  return out.buffer;
}
function encode(buf) {
  var bytes = new Uint8Array(buf), s = '';
  for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function credentialJSON(c) {
  var r = c.response, out = { clientDataJSON: encode(r.clientDataJSON) };
  if (r.attestationObject) {
    out.attestationObject = encode(r.attestationObject);
    if (r.getTransports) out.transports = r.getTransports();
  } else {
    out.authenticatorData = encode(r.authenticatorData);
    out.signature = encode(r.signature);
    if (r.userHandle) out.userHandle = encode(r.userHandle);
  }
  return {
    id: c.id, rawId: encode(c.rawId), type: c.type,
    authenticatorAttachment: c.authenticatorAttachment || undefined,
    clientExtensionResults: c.getClientExtensionResults(),
    response: out
  };
}
async function call(path, body) {
  var res = await fetch(path, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
  });
  var data = await res.json().catch(function () { return {}; });
  if (!res.ok) {
    var err = new Error(serverMessage(data));
    err.code = data.code || '';
    throw err;
  }
  return data;
}
// Names a passkey after where it was made, so its owner can tell them apart.
function deviceName() {
  var ua = navigator.userAgent;
  var os = /iPhone/.test(ua) ? 'iPhone' : /iPad/.test(ua) ? 'iPad' : /Android/.test(ua) ? 'Android'
    : /Mac OS X/.test(ua) ? 'Mac' : /Windows/.test(ua) ? 'Windows' : /Linux/.test(ua) ? 'Linux' : '';
  var browser = /Edg\//.test(ua) ? 'Edge' : /Firefox\//.test(ua) ? 'Firefox' : /Chrome\//.test(ua) ? 'Chrome'
    : /Safari\//.test(ua) ? 'Safari' : '';
  return [browser, os].filter(Boolean).join(' on ') || 'Passkey';
}

async function signIn() {
  var begin = await call('/api/passkeys/login/begin', { challenge: pkce });
  var options = begin.options.publicKey;
  options.challenge = decode(options.challenge);
  (options.allowCredentials || []).forEach(function (c) { c.id = decode(c.id); });
  var credential = await navigator.credentials.get({ publicKey: options });
  return call('/api/passkeys/login/finish', { session: begin.session, credential: credentialJSON(credential) });
}
async function register() {
  var body = { name: deviceName() };
  if (pkce) body.challenge = pkce;
  if (mode === 'enroll') body.ticket = ticket;
  else {
    body.email = $('email').value.trim();
    if (proof) body.proof = proof;
  }
  var begin = await call('/api/passkeys/register/begin', body);
  var options = begin.options.publicKey;
  options.challenge = decode(options.challenge);
  options.user.id = decode(options.user.id);
  (options.excludeCredentials || []).forEach(function (c) { c.id = decode(c.id); });
  var credential = await navigator.credentials.create({ publicKey: options });
  return call('/api/passkeys/register/finish', { session: begin.session, credential: credentialJSON(credential) });
}

// Set once the page has its answer, so nothing redraws over the result.
var done = false;

// ---- Confirming a new account's address --------------------------------
// The address the last code went to, and the proof the right code bought. The
// proof outlives a dismissed passkey sheet: it is spent with the account.
var codeSentTo = '', proof = '', resendAt = 0, resendTimer = null;
function currentEmail() { return $('email').value.trim().toLowerCase(); }
async function sendCode() {
  var email = currentEmail();
  var sent = await call('/api/passkeys/register/email', { email: email, locale: lang });
  codeSentTo = email;
  proof = '';
  resendAt = Date.now() + (sent.resendAfter || 60) * 1000;
  $('code').value = '';
  render();
  $('code').focus();
}
async function confirmCode() {
  var code = $('code').value.replace(/\s+/g, '');
  if (!/^[0-9]{6}$/.test(code)) throw new Error(t('err.codeFormat'));
  proof = (await call('/api/passkeys/register/verify', { email: codeSentTo, code: code })).proof;
}
function updateResend() {
  var wait = Math.ceil((resendAt - Date.now()) / 1000);
  $('resend').disabled = wait > 0;
  $('resend').textContent = wait > 0 ? t('code.resendIn', wait) : t('code.resend');
  if (wait <= 0 && resendTimer) { clearInterval(resendTimer); resendTimer = null; }
}
function confirming() { return mode === 'signup' && server.verifyEmail && codeSentTo !== '' && !proof; }
// The address is confirmed and only the passkey is left.
function saving() { return mode === 'signup' && server.verifyEmail && proof !== ''; }

function finished(result) {
  done = true;
  var created = mode === 'signup';
  if (result.code) {
    // The code is useless without the verifier only the app that asked holds.
    var back = 'revoked://auth?code=' + encodeURIComponent(result.code) + '&state=' + encodeURIComponent(state);
    redraw = function () {
      show($('emailRow'), false); show($('codeRow'), false); show($('go'), false); show($('other'), false); show($('resend'), false);
      steps(created ? STEP_NAMES.length : 0);
      heading(t(created ? 'done.created' : 'done.signedIn'), t(created ? 'done.next' : 'done.returning'), 'check', 'ok');
      $('open').href = back;
      show($('open'), true);
      $('note').textContent = t('done.close');
    };
    redraw();
    location.href = back;
    return;
  }
  redraw = function () {
    show($('emailRow'), false); show($('codeRow'), false); show($('go'), false); show($('other'), false); show($('resend'), false);
    steps(created ? STEP_NAMES.length : 0);
    heading(t('done.saved'), t('done.savedLead'), 'check', 'ok');
    $('note').textContent = t('done.closeNow');
  };
  redraw();
}

function render() {
  redraw = render;
  show($('card'), true);
  show($('error'), false);
  show($('emailRow'), mode === 'signup' && !saving());
  show($('codeRow'), confirming());
  show($('resend'), confirming());
  show($('go'), true);
  show($('other'), false);
  steps(0);
  $('note').textContent = '';
  if (mode === 'enroll') {
    if (!server.ticketEmail) {
      show($('go'), false);
      heading(t('enroll.dead'), t('enroll.deadLead'), 'alert', 'warn');
      show($('card'), false);
      return;
    }
    heading(t('enroll.title'), t('enroll.lead', server.ticketEmail), 'key');
    action(t('passkey.go'), 'key');
    return;
  }
  if (mode === 'signup') {
    if (saving()) {
      steps(3);
      heading(t('passkey.title'), t('passkey.lead', location.hostname), 'key');
      action(t('passkey.go'), 'key');
      return;
    }
    if (confirming()) {
      steps(2);
      heading(t('code.title'), t('code.lead', codeSentTo), 'mail');
      action(t('code.go'), 'arrow-right');
      $('note').textContent = t('code.note');
      updateResend();
      if (!resendTimer && $('resend').disabled) resendTimer = setInterval(updateResend, 1000);
    } else if (server.verifyEmail) {
      steps(1);
      heading(t('signup.title'), t('signup.leadCode'), 'user-plus');
      action(t('signup.sendCode'), 'mail');
    } else {
      steps(1);
      heading(t('signup.title'), t('signup.lead'), 'user-plus');
      action(t('signup.create'), 'user-plus');
    }
    $('other').textContent = t('signup.other');
    $('other').classList.add('link');
    show($('other'), true);
    return;
  }
  if (!pkce) {
    heading(t('signin.title'), t('signin.fromApp'), 'smartphone');
    show($('card'), false);
    return;
  }
  heading(t('signin.title'), t('signin.lead'), 'key');
  action(t('signin.go'), 'key');
  if (server.signups) {
    $('other').classList.remove('link');
    $('other').textContent = t('signin.other');
    show($('other'), true);
  } else {
    $('note').textContent = t('signin.noPasskey');
  }
}

$('other').addEventListener('click', function () {
  mode = mode === 'signup' ? 'signin' : 'signup';
  render();
  if (mode === 'signup') $('email').focus();
});
var busy = false;
$('go').addEventListener('click', async function () {
  if (busy) return;
  busy = true;
  show($('error'), false);
  $('go').disabled = true;
  $('go').classList.add('loading');
  try {
    if (mode === 'signin') {
      finished(await signIn());
    } else if (mode === 'signup' && server.verifyEmail && !proof) {
      if (!confirming()) {
        await sendCode();
        return;
      }
      await confirmCode();
      // Confirmed: the passkey is the last step, and the device's own
      // sheet opens for it right away.
      render();
      finished(await register());
    } else {
      if (mode === 'signup' && !server.verifyEmail) steps(2);
      finished(await register());
    }
  } catch (e) {
    // A proof that ran out sends the address back to be confirmed again.
    if (e && e.code === 'email_verification_required') {
      proof = ''; codeSentTo = '';
      render();
    } else if (mode === 'signup' && !server.verifyEmail) {
      steps(1);
    }
    // Dismissing the system sheet is not an error worth explaining.
    if (!e || e.name !== 'NotAllowedError') fail((e && e.message) || t('err.generic'));
    if (e && e.name === 'InvalidStateError') fail(t('err.exists'));
  } finally {
    busy = false;
    $('go').disabled = false;
    $('go').classList.remove('loading');
  }
});
$('email').addEventListener('keydown', function (e) { if (e.key === 'Enter') $('go').click(); });
$('code').addEventListener('keydown', function (e) { if (e.key === 'Enter') $('go').click(); });
// Six digits typed or pasted are the whole code: go on without a click.
$('code').addEventListener('input', function () {
  var digits = $('code').value.replace(/[^0-9]/g, '').slice(0, 6);
  if (digits !== $('code').value) $('code').value = digits;
  if (digits.length === 6) $('go').click();
});
// A different address needs its own code.
$('email').addEventListener('input', function () {
  if (codeSentTo && currentEmail() !== codeSentTo) {
    codeSentTo = ''; proof = '';
    render();
  }
});
$('resend').addEventListener('click', async function () {
  show($('error'), false);
  $('resend').disabled = true;
  try { await sendCode(); } catch (e) { fail((e && e.message) || t('err.generic')); updateResend(); }
});
render();
if (mode === 'signup') $('email').focus();
})();
</script>
</body>
</html>
`))
