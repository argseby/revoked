package routes

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"html/template"

	"revoked/cmd/revoked/server"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// The consent page talks to its own origin and nothing else, and leaves for
// the service only by a navigation it computes from the server's answer.
const oidcPageCSP = passkeyPageCSP

type oidcPageData struct {
	// Why the page cannot go on; empty when it can.
	Problem string
	// The id of the stored authorization request.
	Request string
	// The service's origin.
	Client string
	// The optional scopes asked for, and the vault keys asked for.
	Scopes   []string
	LinkKeys []string
	// Whether a passkey can be bound to the address the page was reached at.
	OriginOK bool
	Nonce    string
}

func renderOIDCPage(re *core.RequestEvent, root *server.RootKey, data oidcPageData, status int) error {
	nonceBytes := make([]byte, 16)
	if _, err := rand.Read(nonceBytes); err != nil {
		return re.InternalServerError("Failed to render the page.", err)
	}
	data.Nonce = base64.StdEncoding.EncodeToString(nonceBytes)
	_, _, data.OriginOK = util.PasskeyRelyingParty(pageOrigin(re, root))
	if data.Scopes == nil {
		data.Scopes = []string{}
	}
	if data.LinkKeys == nil {
		data.LinkKeys = []string{}
	}

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
.big, .quiet { width: 100%; min-height: 50px; border-radius: 15px; font: inherit; font-size: 16px; font-weight: 650; cursor: pointer; }
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
<ul class="asks" id="asks"></ul>
<button id="go" class="big" hidden></button>
<button id="deny" class="quiet" hidden></button>
<p class="fine" id="note"></p>
</div>
</main>
<script nonce="{{.Nonce}}">
(function () {
'use strict';
var server = {
  problem: {{.Problem}}, request: {{.Request}}, client: {{.Client}},
  scopes: {{.Scopes}}, linkKeys: {{.LinkKeys}}, originOK: {{.OriginOK}}
};
var $ = function (id) { return document.getElementById(id); };
var show = function (n, on) { n.hidden = !on; };

var STRINGS = {
  en: {
    'lang.label': 'DE', 'title': 'Sign in to {0}', 'title.done': 'Returning to {0}…',
    'lead': '{0} asks to sign you in with your Revoked account. It learns only what you allow below.',
    'lead.signed': 'Signed in as {0}. Choose what {1} may know.',
    'ask.id': 'That it is you, under an identifier only {0} uses',
    'scope.profile': 'Your name', 'scope.email': 'Your email address',
    'scope.revoked_identity': 'Your Revoked identity',
    'link': 'Your entry “{0}”, as a grant you can revoke', 'link.none': 'Do not share',
    'go': 'Continue with passkey', 'allow': 'Allow', 'deny': 'Cancel',
    'note': 'Shared entries stay in your vault. {0} reads them from there until you revoke them.',
    'problem.client': 'This service did not identify itself correctly, so signing in cannot continue. Nothing was shared.',
    'problem.origin': 'Passkeys cannot be used at this address.',
    'problem.browser': 'This browser cannot use passkeys.',
    'err.generic': 'Something went wrong. Please try again.'
  },
  de: {
    'lang.label': 'EN', 'title': 'Bei {0} anmelden', 'title.done': 'Zurück zu {0} …',
    'lead': '{0} möchte dich mit deinem Revoked-Konto anmelden. Es erfährt nur, was du unten erlaubst.',
    'lead.signed': 'Angemeldet als {0}. Wähle, was {1} erfahren darf.',
    'ask.id': 'Dass du es bist, unter einer Kennung, die nur {0} verwendet',
    'scope.profile': 'Dein Name', 'scope.email': 'Deine E-Mail-Adresse',
    'scope.revoked_identity': 'Deine Revoked-Identität',
    'link': 'Dein Eintrag „{0}“, als widerrufbare Freigabe', 'link.none': 'Nicht teilen',
    'go': 'Mit Passkey fortfahren', 'allow': 'Erlauben', 'deny': 'Abbrechen',
    'note': 'Geteilte Einträge bleiben in deinem Tresor. {0} liest sie von dort, bis du sie widerrufst.',
    'problem.client': 'Dieser Dienst hat sich nicht korrekt ausgewiesen, daher kann die Anmeldung nicht fortgesetzt werden. Es wurde nichts geteilt.',
    'problem.origin': 'An dieser Adresse können keine Passkeys verwendet werden.',
    'problem.browser': 'Dieser Browser kann keine Passkeys verwenden.',
    'err.generic': 'Etwas ist schiefgelaufen. Bitte versuche es erneut.'
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
var redraw = function () {};
$('lang-toggle').addEventListener('click', function () {
  lang = lang === 'de' ? 'en' : 'de';
  try { localStorage.setItem(LANG_KEY, lang); } catch (e) {}
  document.documentElement.lang = lang;
  $('lang-toggle').textContent = t('lang.label');
  redraw();
});
document.documentElement.lang = lang;
$('lang-toggle').textContent = t('lang.label');

function fail(message) { $('error').textContent = message; show($('error'), true); }
function stop(key) {
  redraw = function () {
    $('title').textContent = t('title', host || 'Revoked');
    $('lead').textContent = '';
    $('asks').textContent = '';
    show($('go'), false); show($('deny'), false);
    $('note').textContent = '';
    fail(t(key));
  };
  redraw();
}
if (server.problem) { stop('problem.' + server.problem); return; }
if (!server.originOK) {
  if (/^(127\.0\.0\.1|\[::1\])$/.test(location.hostname)) {
    location.replace(location.protocol + '//localhost' + (location.port ? ':' + location.port : '') +
      location.pathname + location.search);
    return;
  }
  stop('problem.origin');
  return;
}
if (!window.PublicKeyCredential || !window.crypto || !crypto.subtle) { stop('problem.browser'); return; }

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
async function call(path, body) {
  var res = await fetch(path, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
  });
  var data = await res.json().catch(function () { return {}; });
  if (!res.ok) throw new Error(data.message || t('err.generic'));
  return data;
}

function item(title, value, control) {
  var li = document.createElement('li');
  if (control) li.appendChild(control);
  var box = document.createElement('div');
  box.style.minWidth = '0';
  box.style.flex = '1';
  var tt = document.createElement('div');
  tt.className = 'ask-t';
  tt.textContent = title;
  box.appendChild(tt);
  if (value) {
    var v = document.createElement('div');
    v.className = 'ask-v';
    v.textContent = value;
    box.appendChild(v);
  }
  li.appendChild(box);
  return li;
}

// ---- Before signing in: what the service asks for ----------------------
function intro() {
  redraw = intro;
  $('title').textContent = t('title', host);
  $('lead').textContent = t('lead', host);
  var asks = $('asks');
  asks.textContent = '';
  asks.appendChild(item(t('ask.id', host)));
  server.scopes.forEach(function (s) { asks.appendChild(item(t('scope.' + s))); });
  server.linkKeys.forEach(function (k) { asks.appendChild(item(t('link', k))); });
  $('go').textContent = t('go');
  show($('go'), true);
  show($('deny'), false);
  $('note').textContent = server.linkKeys.length ? t('note', host) : '';
}

// ---- After signing in: the decision ------------------------------------
var consent = null;
var choices = { scopes: {}, links: {} };
function decide() {
  redraw = decide;
  $('title').textContent = t('title', host);
  $('lead').textContent = t('lead.signed', consent.account.email, host);
  var asks = $('asks');
  asks.textContent = '';
  asks.appendChild(item(t('ask.id', host)));
  consent.scopes.forEach(function (s) {
    var box = document.createElement('input');
    box.type = 'checkbox';
    box.checked = choices.scopes[s.scope] !== false;
    box.addEventListener('change', function () { choices.scopes[s.scope] = box.checked; });
    choices.scopes[s.scope] = box.checked;
    asks.appendChild(item(t('scope.' + s.scope), s.value || '', box));
  });
  consent.links.forEach(function (l) {
    var li = item(t('link', l.key));
    var select = document.createElement('select');
    var none = document.createElement('option');
    none.value = '';
    none.textContent = t('link.none');
    select.appendChild(none);
    l.options.forEach(function (o, i) {
      var opt = document.createElement('option');
      opt.value = o.id;
      opt.textContent = (o.label || o.key) + (o.preview ? ' — ' + o.preview : '');
      select.appendChild(opt);
    });
    if (!(l.key in choices.links)) {
      var match = l.options.filter(function (o) { return o.key === l.key; })[0];
      choices.links[l.key] = match ? match.id : '';
    }
    select.value = choices.links[l.key];
    select.addEventListener('change', function () { choices.links[l.key] = select.value; });
    li.lastChild.appendChild(select);
    asks.appendChild(li);
  });
  $('go').textContent = t('allow');
  $('deny').textContent = t('deny');
  show($('go'), true);
  show($('deny'), true);
  $('note').textContent = consent.links.length ? t('note', host) : '';
}

async function signIn() {
  var raw = new Uint8Array(32);
  crypto.getRandomValues(raw);
  var verifier = encode(raw.buffer);
  var challenge = encode(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier)));
  var begin = await call('/api/passkeys/login/begin', { challenge: challenge });
  var options = begin.options.publicKey;
  options.challenge = decode(options.challenge);
  (options.allowCredentials || []).forEach(function (c) { c.id = decode(c.id); });
  var c = await navigator.credentials.get({ publicKey: options });
  var r = c.response;
  var finish = await call('/api/passkeys/login/finish', {
    session: begin.session,
    credential: {
      id: c.id, rawId: encode(c.rawId), type: c.type,
      clientExtensionResults: c.getClientExtensionResults(),
      response: {
        clientDataJSON: encode(r.clientDataJSON), authenticatorData: encode(r.authenticatorData),
        signature: encode(r.signature), userHandle: r.userHandle ? encode(r.userHandle) : undefined
      }
    }
  });
  return call('/oidc/authorize/session', { request: server.request, code: finish.code, verifier: verifier });
}

async function answer(approve) {
  var scopes = Object.keys(choices.scopes).filter(function (s) { return choices.scopes[s]; });
  var data = await call('/oidc/authorize/consent', {
    ticket: consent.ticket, approve: approve, scopes: scopes, links: choices.links
  });
  redraw = function () { $('title').textContent = t('title.done', host); };
  redraw();
  show($('go'), false); show($('deny'), false);
  $('asks').textContent = ''; $('lead').textContent = ''; $('note').textContent = '';
  location.replace(data.redirect);
}

var busy = false;
async function run(fn) {
  if (busy) return;
  busy = true;
  show($('error'), false);
  $('go').disabled = true; $('deny').disabled = true;
  try { await fn(); }
  catch (e) {
    // Dismissing the system sheet is not an error worth explaining.
    if (!e || e.name !== 'NotAllowedError') fail((e && e.message) || t('err.generic'));
  } finally {
    busy = false;
    $('go').disabled = false; $('deny').disabled = false;
  }
}
$('go').addEventListener('click', function () {
  run(async function () {
    if (!consent) { consent = await signIn(); decide(); }
    else await answer(true);
  });
});
$('deny').addEventListener('click', function () { run(function () { return answer(false); }); });
intro();
})();
</script>
</body>
</html>
`))
