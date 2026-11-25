package routes

// requestPageScript answers a request in the browser (BROWSER.md §4.2). It
// probes the public endpoint, signs in inside the page, fills what the
// responder's vault already holds as living references, and submits to the
// same endpoint the app uses, so every gate stays the server's.
//
// The page never calls the server verified: it is served by the server it
// would be vouching for. What it states is the address, the name the server
// reports, and whether this browser remembered a different server key for
// that domain before (BROWSER.md §3.1).
const requestPageScript = `
var probe = null, closedMessage = '', notFound = false;
var vault = [], byId = {}, existing = null;
// key -> { mode: 'vault' | 'typed', record, input }
var answers = {};
var submitted = null;

var TRUST_KEY = 'revoked_trusted_domains';
function trustMap() {
  try { var m = JSON.parse(localStorage.getItem(TRUST_KEY) || '{}'); return m && typeof m === 'object' ? m : {}; }
  catch (e) { return {}; }
}
function setTrusted(domain, pin, on) {
  var m = trustMap();
  if (on) m[domain] = String(pin); else delete m[domain];
  try { localStorage.setItem(TRUST_KEY, JSON.stringify(m)); } catch (e) {}
  redraw();
}

function fields() {
  var out = [];
  var tpl = (probe && probe.template) || {};
  (tpl.records || []).forEach(function (f) { out.push(f); });
  (tpl.sections || []).forEach(function (s) { (s.records || []).forEach(function (f) { out.push(f); }); });
  return out;
}
function isFile(f) { return f.type === 'file'; }
// A verified identity is proven in the page with a passkey identity (§4.8);
// a file is still answered in the app.
function appOnly() {
  if (fields().some(function (f) { return isFile(f) && f.required; })) return 'req.appOnlyFile';
  return '';
}
function valueOf(rec) {
  if (!rec) return '';
  var carrier = rec.aliasOf && byId[rec.aliasOf] ? byId[rec.aliasOf] : rec;
  return carrier.value || '';
}
function usable(rec) {
  if (!rec || rec.sealed || rec.type === 'file') return false;
  var carrier = rec.aliasOf && byId[rec.aliasOf] ? byId[rec.aliasOf] : rec;
  return !carrier.sealed;
}
function vaultMatch(key) {
  var alias = null;
  for (var i = 0; i < vault.length; i++) {
    var r = vault[i];
    if (r.key !== key || !usable(r)) continue;
    if (!r.aliasOf) return r;
    alias = alias || r;
  }
  return alias;
}

// The address as the address bar shows it, the expiry, and this browser's
// memory of the server key. Never a verdict (BROWSER.md §3.1).
function metaItems() {
  var items = [location.host, probe.expiresAt ? t('req.expiresOn', formatDate(probe.expiresAt)) : t('req.never')];
  var claim = probe.server || {};
  if (claim.domain && claim.rootFingerprint) {
    var remembered = trustMap()[claim.domain];
    if (!remembered || remembered === String(claim.rootFingerprint)) {
      var b = el('button', 'text-btn', t(remembered ? 'pin.untrust' : 'pin.trust'));
      b.type = 'button';
      b.addEventListener('click', function () { setTrusted(claim.domain, claim.rootFingerprint, !remembered); });
      if (remembered) items.push(t('pin.trustedShort'));
      items.push(b);
    }
  }
  return items;
}
function pinWarning() {
  var claim = probe.server || {};
  var remembered = claim.domain && trustMap()[claim.domain];
  return remembered && remembered !== String(claim.rootFingerprint) ? callout('warn', 'alert', t('pin.changed', claim.domain)) : null;
}

// A field as a form row, in the same rhythm as the list before sign-in: the
// label, what it is for, then the value from the vault or the input.
function fieldEntry(f) {
  var box = el('div', 'form-row');
  var head = el('div', 'form-row-h');
  head.appendChild(el('span', 'form-row-t', f.label || f.key));
  if (!f.required) head.appendChild(el('span', 'tag', t('req.optional')));
  box.appendChild(head);
  if (f.reason) box.appendChild(el('p', 'entry-reason', f.reason));
  if (isFile(f)) {
    box.appendChild(el('p', 'entry-reason', t('req.fileApp')));
    return box;
  }
  if (!session) return box;
  var a = answers[f.key];
  var foot = el('div', 'form-row-foot');
  if (a.mode === 'vault') {
    box.appendChild(el('div', 'value', valueOf(a.record)));
    foot.appendChild(el('span', '', t('req.fromVault')));
    var other = el('button', 'text-btn', t('req.typeInstead'));
    other.type = 'button';
    other.addEventListener('click', function () { a.mode = 'typed'; redraw(); a.input.focus(); });
    foot.appendChild(other);
    box.appendChild(foot);
  } else {
    box.appendChild(a.input);
    if (a.record) {
      var back = el('button', 'text-btn', t('req.useVault'));
      back.type = 'button';
      back.addEventListener('click', function () { a.mode = 'vault'; redraw(); });
      foot.appendChild(back);
      box.appendChild(foot);
    }
  }
  return box;
}

var secretInputs = { password: null, identifier: null };
function secretField(name, labelKey, type, hintKey) {
  if (!secretInputs[name]) {
    var input = el('input');
    input.type = type;
    input.autocomplete = 'off';
    secretInputs[name] = input;
  }
  var label = el('label', 'form-row');
  label.appendChild(el('span', 'form-row-t', t(labelKey)));
  if (hintKey) label.appendChild(el('span', 'entry-reason', t(hintKey)));
  label.appendChild(secretInputs[name]);
  return label;
}

async function submit() {
  fail('');
  var data = {}, mappings = {};
  var list = fields().filter(function (f) { return !isFile(f); });
  for (var i = 0; i < list.length; i++) {
    var f = list[i], a = answers[f.key];
    if (a.mode === 'vault' && a.record) { mappings[f.key] = a.record.id; continue; }
    var v = a.input.value.trim();
    if (v) data[f.key] = v;
    else if (f.required) { fail(t('req.missing', f.label || f.key)); a.input.focus(); return; }
  }
  var body = { data: data, mappings: mappings };
  if (probe.requiresPassword) body.password = secretInputs.password.value;
  if (probe.requiresIdentifier) body.identifier = secretInputs.identifier.value.trim();
  try {
    if (probe.requireHandshake) {
      var ch = await api('GET', '/api/challenges/request/' + encodeURIComponent(server.slug) + '?identityId=' + encodeURIComponent(identity.id));
      body.identityId = identity.id;
      body.challengeNonce = ch.nonce;
      body.challengeSignature = await identitySign(ch.nonce);
    }
    var res = await api('POST', '/api/public/requests/' + encodeURIComponent(server.slug), body);
    submitted = { updated: !!res.updated, given: list.map(function (f) {
      var a = answers[f.key];
      if (a.mode === 'vault' && a.record) return { label: f.label || f.key, value: valueOf(a.record), from: 'req.fromVault' };
      var v = a.input.value.trim();
      return v ? { label: f.label || f.key, value: v, from: 'req.typed' } : null;
    }).filter(Boolean) };
    redraw();
    window.scrollTo(0, 0);
  } catch (e) {
    fail((e && e.message) || t('err.generic'));
  }
}

function renderSubmitted() {
  var flow = $('flow');
  heading(t(submitted.updated ? 'req.updated' : 'req.sent'), t('req.sentLead'), 'check', 'ok');
  eyebrow(probe.label || '');
  flow.appendChild(summaryList(submitted.given.map(function (g) {
    return { label: g.label, value: g.value, tag: t(g.from) };
  })));
  var manage = el('a', 'big');
  manage.href = '/answers';
  manage.appendChild(el('span', '', t('req.manage')));
  flow.appendChild(manage);
  show($('app-way'), false);
}

redraw = function () {
  var flow = $('flow');
  flow.textContent = '';
  if (closedMessage) {
    // Nothing is left to open, in the app or here.
    show($('app-way'), false);
    if (notFound) heading(t('req.notFound'), t('req.notFoundLead'), 'alert', 'warn');
    else heading(t('req.closed'), closedMessage, 'alert', 'warn');
    return;
  }
  if (!probe) return;
  if (submitted) { renderSubmitted(); return; }
  var name = probe.requester && probe.requester.name;
  heading(probe.label || t('req.untitled'), '');
  eyebrow(name ? t('req.eyebrow', name) : '');
  flow.appendChild(metaLine(metaItems()));
  var pin = pinWarning();
  if (pin) flow.appendChild(pin);

  var only = appOnly();
  if (only) {
    flow.appendChild(callout('info', 'lock', t(only)));
  }
  var list = fields();
  if (list.length) {
    if (!session) {
      flow.appendChild(lockedList(list.map(function (f) {
        return { label: f.label || f.key, note: isFile(f) ? t('req.fileApp') : f.reason, tag: f.required ? '' : t('req.optional') };
      }), t('req.fields'), !!only));
    } else {
      var head = el('div', 'asked-h');
      head.appendChild(el('span', 'section-t', t('req.fields')));
      flow.appendChild(head);
      list.forEach(function (f) { flow.appendChild(fieldEntry(f)); });
    }
  }
  if (only || !session) return;

  if (probe.requiresPassword) flow.appendChild(secretField('password', 'req.password', 'password'));
  if (probe.requiresIdentifier) flow.appendChild(secretField('identifier', 'req.identifier', 'text', 'req.identifierHint'));
  if (existing) flow.appendChild(callout('info', 'info', t('req.existing')));
  var needsIdentity = probe.requireHandshake && !(identity && identity.id);
  if (probe.requireHandshake) flow.appendChild(identityStep(redraw));
  var send = button('big', t(existing ? 'req.update' : 'req.send'), null);
  send.disabled = needsIdentity;
  send.addEventListener('click', busyWhile(send, submit));
  flow.appendChild(send);
  flow.appendChild(signedInLine());
};

async function afterSignIn() {
  var me = session.user.id;
  try {
    await ensureWorkspace();
    // The sign-in assertion already carried the identity secret.
    if (probe.requireHandshake && pendingPrf) {
      try { await unlockIdentity(); } catch (e) { fail((e && e.message) || t('err.generic')); }
    }
    var recs = await api('GET', listPath('records', 'user = ' + quoted(me), '&sort=-created'));
    vault = recs.items || [];
    vault.forEach(function (r) { byId[r.id] = r; });
    var links = await api('GET', listPath('links', 'request = ' + quoted(probe.requestId) + ' && user = ' + quoted(me), '&sort=-created'));
    existing = (links.items || []).filter(function (l) { return l.status !== 'revoked'; })[0] || null;
  } catch (e) {
    fail((e && e.message) || t('err.load'));
  }
  var grants = (existing && existing.grants) || {};
  fields().forEach(function (f) {
    if (isFile(f)) return;
    var input = el('textarea');
    input.rows = 1;
    input.setAttribute('aria-label', f.label || f.key);
    // Grows with what is typed rather than showing a resize handle.
    input.addEventListener('input', function () { input.style.height = 'auto'; input.style.height = input.scrollHeight + 2 + 'px'; });
    var rec = (grants[f.key] && usable(byId[grants[f.key]]) && byId[grants[f.key]]) || vaultMatch(f.key);
    answers[f.key] = { mode: rec ? 'vault' : 'typed', record: rec, input: input };
  });
  redraw();
}

(async function () {
  try {
    var res = await fetch('/api/public/requests/' + encodeURIComponent(server.slug));
    var data = await res.json().catch(function () { return {}; });
    if (!res.ok) {
      closedMessage = serverMessage(data);
      notFound = res.status === 404;
      redraw();
      return;
    }
    probe = data;
  } catch (e) {
    closedMessage = t('err.load');
    redraw();
    return;
  }
  redraw();
  if (!appOnly()) startSignIn('auth.lead', afterSignIn, !!probe.requireHandshake);
})();
`
