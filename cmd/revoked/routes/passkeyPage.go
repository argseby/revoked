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
	data := passkeyPageData{OriginOK: originOK, Signups: util.SignupsAllowed(), Nonce: nonce}
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
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<link rel="icon" type="image/svg+xml" href="{{logoLight}}" media="(prefers-color-scheme: light)">
<link rel="icon" type="image/svg+xml" href="{{logoDark}}" media="(prefers-color-scheme: dark)">
<title>Sign in · Revoked</title>
<style>
:root {
color-scheme: light;
--bg: #f8f9ff; --surface-subtle: #e1e2e8; --border: #c3c7cf; --fg: #191c20; --fg-muted: #42474e;
--primary: #35618e; --primary-fg: #ffffff; --ok: #216a4d; --bad: #ba1a1a; --bad-subtle: #ffdad6;
}
@media (prefers-color-scheme: dark) {
:root {
color-scheme: dark;
--bg: #101418; --surface-subtle: #32353a; --border: #42474e; --fg: #e1e2e8; --fg-muted: #c3c7cf;
--primary: #a0cafd; --primary-fg: #003258; --ok: #8ed5b1; --bad: #ffb4ab; --bad-subtle: #93000a;
}
.logo-light { display: none; }
}
@media (prefers-color-scheme: light) { .logo-dark { display: none; } }
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
background: var(--bg); color: var(--fg);
font-family: system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
font-size: 15px; line-height: 1.5;
min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 24px;
}
main { width: 100%; max-width: 360px; }
img { width: 40px; height: 40px; margin-bottom: 20px; }
h1 { font-size: 20px; font-weight: 600; }
p { color: var(--fg-muted); margin-top: 4px; }
.stack { margin-top: 24px; display: grid; gap: 12px; }
label { font-size: 14px; }
input {
width: 100%; margin-top: 6px; padding: 10px 12px; font: inherit; color: inherit;
background: transparent; border: 1px solid var(--border); border-radius: 8px;
}
input:focus { outline: 2px solid var(--primary); outline-offset: 1px; }
button, a.button {
display: block; width: 100%; padding: 10px 14px; font: inherit; font-weight: 600; text-align: center;
text-decoration: none; cursor: pointer; border-radius: 8px; border: 1px solid transparent;
background: var(--primary); color: var(--primary-fg);
}
button.quiet { background: transparent; color: var(--fg); border-color: var(--border); font-weight: 500; }
button:disabled { opacity: .6; cursor: default; }
.alert { padding: 10px 12px; border-radius: 8px; background: var(--bad-subtle); color: var(--fg); font-size: 14px; }
.note { font-size: 13px; }
.done { color: var(--ok); font-weight: 600; }
[hidden] { display: none !important; }
</style>
</head>
<body>
<main>
<img class="logo-light" src="{{logoLight}}" alt="">
<img class="logo-dark" src="{{logoDark}}" alt="">
<h1 id="title">Sign in</h1>
<p id="lead"></p>
<div class="stack">
<div id="error" class="alert" role="alert" hidden></div>
<label id="emailRow" hidden>Email
<input id="email" type="email" autocomplete="username webauthn" placeholder="name@example.com">
</label>
<button id="go" hidden></button>
<button id="other" class="quiet" hidden></button>
<a id="open" class="button" hidden>Open revoked</a>
<p id="note" class="note"></p>
</div>
</main>
<script nonce="{{.Nonce}}">
(function () {
'use strict';
var server = { originOK: {{.OriginOK}}, signups: {{.Signups}}, ticketEmail: {{.TicketEmail}} };
var query = new URLSearchParams(location.search);
var pkce = /^[A-Za-z0-9._~-]{43,128}$/.test(query.get('challenge') || '') ? query.get('challenge') : '';
var state = /^[A-Za-z0-9._~-]{1,128}$/.test(query.get('state') || '') ? query.get('state') : '';
var ticket = query.get('ticket') || '';
var mode = ticket ? 'enroll' : (query.get('mode') === 'signup' ? 'signup' : 'signin');

var $ = function (id) { return document.getElementById(id); };
function show(el, on) { el.hidden = !on; }
function fail(message) { $('error').textContent = message; show($('error'), true); }

// A passkey cannot be bound to an IP address; on a development machine the
// same server answers at localhost.
if (!server.originOK) {
  if (/^(127\.0\.0\.1|\[::1\])$/.test(location.hostname)) {
    location.replace(location.protocol + '//localhost' + (location.port ? ':' + location.port : '') +
      location.pathname + location.search);
    return;
  }
  fail('Passkeys only work at this server’s own address.');
  return;
}
if (!window.PublicKeyCredential) {
  fail('This browser does not support passkeys.');
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
  if (!res.ok) throw new Error(data.message || 'The server refused the request.');
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
  if (mode === 'enroll') body.ticket = ticket; else body.email = $('email').value.trim();
  var begin = await call('/api/passkeys/register/begin', body);
  var options = begin.options.publicKey;
  options.challenge = decode(options.challenge);
  options.user.id = decode(options.user.id);
  (options.excludeCredentials || []).forEach(function (c) { c.id = decode(c.id); });
  var credential = await navigator.credentials.create({ publicKey: options });
  return call('/api/passkeys/register/finish', { session: begin.session, credential: credentialJSON(credential) });
}

function finished(result) {
  show($('emailRow'), false); show($('go'), false); show($('other'), false);
  if (result.code) {
    // The code is useless without the verifier only the app that asked holds.
    var back = 'revoked://auth?code=' + encodeURIComponent(result.code) + '&state=' + encodeURIComponent(state);
    $('title').textContent = 'Signed in';
    $('lead').textContent = 'Returning to revoked…';
    $('open').href = back;
    show($('open'), true);
    $('note').textContent = 'You can close this page once the app has opened.';
    location.href = back;
    return;
  }
  $('title').textContent = 'Passkey saved';
  $('title').className = 'done';
  $('lead').textContent = 'Open revoked on this device and sign in with it. You can close this page.';
  $('note').textContent = '';
}

function render() {
  show($('error'), false);
  show($('emailRow'), mode === 'signup');
  show($('go'), true);
  show($('other'), false);
  $('note').textContent = '';
  if (mode === 'enroll') {
    if (!server.ticketEmail) {
      show($('go'), false);
      $('title').textContent = 'This link no longer works';
      $('lead').textContent = 'It is unknown, already used, or has expired. Ask for a new one.';
      return;
    }
    $('title').textContent = 'Add a passkey';
    $('lead').textContent = 'For ' + server.ticketEmail + '. It is saved on this device and is how you sign in from now on.';
    $('go').textContent = 'Create passkey';
    return;
  }
  if (mode === 'signup') {
    $('title').textContent = 'Create an account';
    $('lead').textContent = 'No password: a passkey saved on this device is how you sign in.';
    $('go').textContent = 'Create account';
    $('other').textContent = 'I already have an account';
    show($('other'), true);
    return;
  }
  $('title').textContent = 'Sign in';
  if (!pkce) {
    show($('go'), false);
    $('lead').textContent = 'Start from the revoked app: it opens this page and takes you back signed in.';
    return;
  }
  $('lead').textContent = 'Use the passkey saved on this device.';
  $('go').textContent = 'Sign in with a passkey';
  if (server.signups) {
    $('other').textContent = 'Create an account';
    show($('other'), true);
  } else {
    $('note').textContent = 'No passkey yet? Ask whoever runs this server for a link to add one.';
  }
}

$('other').addEventListener('click', function () {
  mode = mode === 'signup' ? 'signin' : 'signup';
  render();
});
$('go').addEventListener('click', async function () {
  show($('error'), false);
  $('go').disabled = true;
  try {
    finished(await (mode === 'signin' ? signIn() : register()));
  } catch (e) {
    // Dismissing the system sheet is not an error worth explaining.
    if (!e || e.name !== 'NotAllowedError') fail((e && e.message) || 'Something went wrong.');
    if (e && e.name === 'InvalidStateError') fail('This device already has a passkey for this account.');
  } finally {
    $('go').disabled = false;
  }
});
$('email').addEventListener('keydown', function (e) { if (e.key === 'Enter') $('go').click(); });
render();
})();
</script>
</body>
</html>
`))
