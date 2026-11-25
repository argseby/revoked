package routes

// passkeyCeremonyScript is the one implementation of the passkey ceremony in
// a page: the sign-in page, which hands its code to the app, and the flow
// pages (BROWSER.md §4.1), which redeem it themselves. It is spliced into a
// page's own script, inside that page's closure, and calls the page's
// serverMessage and t for what a person reads.
const passkeyCeremonyScript = `
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
// The PRF output never travels to the server: it is taken out of the
// extension results before they are sent, whatever the browser serialises
// them as.
function credentialJSON(c) {
  var ext = Object.assign({}, c.getClientExtensionResults());
  delete ext.prf;
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
    clientExtensionResults: ext,
    response: out
  };
}
async function call(path, body, token) {
  var headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = token;
  var res = await fetch(path, { method: 'POST', headers: headers, body: JSON.stringify(body) });
  var data = await res.json().catch(function () { return {}; });
  if (!res.ok) {
    var err = new Error(serverMessage(data));
    err.code = data.code || '';
    err.data = data;
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
// The WebAuthn Signal API, where the browser has it. Best effort: a browser
// without it, or a password manager that declines, changes nothing here.
async function signal(name, args) {
  if (typeof PublicKeyCredential[name] !== 'function') return false;
  try { await PublicKeyCredential[name](args); return true; } catch (e) { return false; }
}
// challenge is the PKCE challenge the code is bound to; prepare may add
// extensions to the request; extra carries an autofill's mediation and abort
// signal. Resolves with the server's answer and the credential.
async function passkeySignIn(challenge, prepare, extra) {
  var begin = await call('/api/passkeys/login/begin', { challenge: challenge });
  var options = begin.options.publicKey;
  options.challenge = decode(options.challenge);
  (options.allowCredentials || []).forEach(function (c) { c.id = decode(c.id); });
  if (prepare) options = prepare(options);
  var credential = await navigator.credentials.get(Object.assign({ publicKey: options }, extra || {}));
  var rpId = options.rpId || location.hostname;
  var result;
  try {
    result = await call('/api/passkeys/login/finish', { session: begin.session, credential: credentialJSON(credential) });
  } catch (e) {
    // A passkey left behind by a deleted account or a removed key: the
    // password manager is told, where the browser can tell it, so the dead
    // passkey stops being offered.
    if (e && e.code === 'passkey_unknown') {
      var told = await signal('signalUnknownCredential', { rpId: rpId, credentialId: credential.id });
      throw new Error(t(told ? 'err.unknownRemoved' : 'err.unknownManual'));
    }
    throw e;
  }
  // The keys this account still has, and its address: a passkey removed in
  // the app leaves the password manager as well, and a changed address shows.
  var a = result.accepted;
  if (a && a.userId) {
    signal('signalAllAcceptedCredentials', { rpId: rpId, userId: a.userId, allAcceptedCredentialIds: a.credentials || [] });
    if (a.name) signal('signalCurrentUserDetails', { rpId: rpId, userId: a.userId, name: a.name, displayName: a.name });
  }
  return { result: result, credential: credential };
}
async function passkeyRegister(body, prepare) {
  body.name = body.name || deviceName();
  var begin = await call('/api/passkeys/register/begin', body);
  var options = begin.options.publicKey;
  options.challenge = decode(options.challenge);
  options.user.id = decode(options.user.id);
  (options.excludeCredentials || []).forEach(function (c) { c.id = decode(c.id); });
  if (prepare) options = prepare(options);
  var credential = await navigator.credentials.create({ publicKey: options });
  var result = await call('/api/passkeys/register/finish', { session: begin.session, credential: credentialJSON(credential) });
  return { result: result, credential: credential };
}
// A PKCE pair for a page that redeems its own code. The verifier exists only
// in the closure that asked for it.
async function pkcePair() {
  var raw = new Uint8Array(32);
  crypto.getRandomValues(raw);
  var verifier = encode(raw.buffer);
  var digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
  return { verifier: verifier, challenge: encode(digest) };
}
`
