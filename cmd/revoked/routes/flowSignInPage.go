package routes

// signInPageScript approves Sign in with Revoked in the browser (BROWSER.md
// §4.7). It opens the request the way the app does (POST /oidc/authorize/app),
// shows what the service asks for, and answers at /oidc/authorize/consent with
// a passkey approval bound to the ticket in place of the app's identity
// signature. When the service asks for the verified identity, the page can
// instead sign the consent with an identity derived from the passkey (§4.8),
// exactly as the app signs it; only that signature lets the server share
// revoked_identity.
const signInPageScript = `
var host = '';
var consent = null, pausedRedirect = '';
var controls = { scopes: {}, name: null, links: {} };

function scopeRow(item) {
  if (item.scope === 'revoked_identity') {
    var wrap = el('div', 'flow');
    var ready = identity && identity.id;
    var row = controls.scopes[item.scope];
    if (!row || row.box.disabled !== !ready) {
      row = checkRow(t('si.scope.revoked_identity'), ready ? identity.name : t('si.identityNeeds'), !!ready, !ready);
      controls.scopes[item.scope] = row;
    }
    wrap.appendChild(row);
    if (!ready) wrap.appendChild(identityStep(redraw));
    return wrap;
  }
  if (item.scope === 'profile') {
    var box = el('label', 'form-row pick-row');
    box.appendChild(el('span', 'form-row-t', t('si.scope.profile')));
    var opts = [{ value: '', label: t('si.noName') }];
    (consent.nameOptions || []).forEach(function (o) {
      opts.push({ value: o.kind + ':' + o.id, label: o.value + (o.label ? ' · ' + o.label : '') });
    });
    var sel = consent.nameSelected ? consent.nameSelected.kind + ':' + consent.nameSelected.id : '';
    controls.name = controls.name || selectOf(opts, sel);
    box.appendChild(controls.name);
    return box;
  }
  var row = controls.scopes[item.scope] || checkRow(t('si.scope.' + item.scope), item.value || '', true, false);
  controls.scopes[item.scope] = row;
  return row;
}

function linkRow(item) {
  var box = el('label', 'form-row pick-row');
  box.appendChild(el('span', 'form-row-t', labelOf(null, item.key)));
  if (!controls.links[item.key]) {
    var opts = [{ value: '', label: t('si.notShared') }];
    var pick = '';
    (item.options || []).forEach(function (o) {
      opts.push({ value: o.id, label: (o.label || o.key) + (o.preview ? ' · ' + o.preview : '') });
      if (o.shared) pick = o.id;
      if (!pick && o.key === item.key) pick = o.id;
    });
    controls.links[item.key] = selectOf(opts, pick);
  }
  box.appendChild(controls.links[item.key]);
  return box;
}

function decision(approve) {
  var body = { ticket: consent.ticket, approve: approve };
  if (!approve) return body;
  body.scopes = [];
  (consent.scopes || []).forEach(function (s) {
    if (s.scope === 'profile') { if (controls.name && controls.name.value) body.scopes.push('profile'); return; }
    var row = controls.scopes[s.scope];
    if (row && row.box.checked && !row.box.disabled) body.scopes.push(s.scope);
  });
  if (controls.name && controls.name.value) {
    var parts = controls.name.value.split(':');
    body.name = { kind: parts[0], id: parts.slice(1).join(':') };
  }
  body.links = {};
  Object.keys(controls.links).forEach(function (k) {
    if (controls.links[k].value) body.links[k] = controls.links[k].value;
  });
  return body;
}

async function answer(approve) {
  fail('');
  try {
    var body = decision(approve);
    if (approve && identity && identity.id && body.scopes.indexOf('revoked_identity') >= 0) {
      // The consent the app signs, signed by the passkey identity instead.
      body.identityId = identity.id;
      body.signature = await identitySign('revoked-oidc-consent:' + consent.ticket);
    } else if (approve) {
      body.approval = await passkeyApprove('signin', consent.ticket);
    }
    var res = await api('POST', '/oidc/authorize/consent', body);
    location.replace(res.redirect);
  } catch (e) {
    if (e && e.name === 'NotAllowedError') return;
    fail((e && e.message) || t('err.generic'));
  }
}

redraw = function () {
  var flow = $('flow');
  flow.textContent = '';
  if (server.problem) {
    heading(t('si.problem'), t('si.problemLead'), 'alert', 'bad');
    return;
  }
  heading(t('si.title', host), session ? '' : t('si.lead', host));
  eyebrow(t('si.eyebrow'));
  if (pausedRedirect) {
    flow.appendChild(callout('warn', 'alert', t('si.paused', host)));
    var back = el('a', 'quiet');
    back.href = pausedRedirect;
    back.appendChild(el('span', '', t('si.back')));
    flow.appendChild(back);
    return;
  }
  if (!consent) {
    if (!session) flow.appendChild(askedBeforeSignIn());
    return;
  }
  var meta = [t('si.as', consent.account.email)];
  if (consent.returning && consent.returning.lastAt) meta.push(t('si.lastOn', formatDate(consent.returning.lastAt)));
  flow.appendChild(metaLine(meta));
  function section(title, items, render) {
    var head = el('div', 'asked-h');
    head.appendChild(el('span', 'section-t', title));
    flow.appendChild(head);
    var list = el('div', 'asked choices');
    items.forEach(function (i) { list.appendChild(render(i)); });
    flow.appendChild(list);
  }
  if ((consent.scopes || []).length) section(t('si.asks'), consent.scopes, scopeRow);
  if ((consent.links || []).length) section(t('si.entries'), consent.links, linkRow);
  var allow = button('big', t('si.allow'), null);
  allow.addEventListener('click', busyWhile(allow, function () { return answer(true); }));
  flow.appendChild(allow);
  var decline = button('quiet', t('si.decline'), null);
  decline.addEventListener('click', busyWhile(decline, function () { return answer(false); }));
  flow.appendChild(decline);
  flow.appendChild(el('p', 'fine', t('si.approveNote')));
  flow.appendChild(signedInLine());
};

// What the service asks for, read from its request, shown locked until the
// consent screen can show the person's own values.
function askedBeforeSignIn() {
  var p = (server.data && server.data.params) || {};
  var rows = [];
  String(p.scope || '').split(/\s+/).forEach(function (s) {
    if (s === 'profile' || s === 'email' || s === 'revoked_identity') rows.push({ label: t('si.scope.' + s) });
  });
  try {
    var claims = JSON.parse(p.claims || '{}');
    var keys = [];
    ['userinfo', 'id_token'].forEach(function (m) {
      var c = claims[m] && claims[m].revoked_links;
      ((c && c.values) || []).forEach(function (k) { if (keys.indexOf(k) < 0) keys.push(k); });
    });
    keys.forEach(function (k) { rows.push({ label: labelOf(null, k), note: t('si.entry') }); });
  } catch (e) {}
  var wrap = el('div', 'flow');
  if (!rows.length) return wrap;
  wrap.appendChild(lockedList(rows, t('si.asks')));
  return wrap;
}

function asksIdentity() {
  return String((server.data && server.data.params && server.data.params.scope) || '').split(/\s+/).indexOf('revoked_identity') >= 0;
}

async function afterSignIn() {
  try {
    await ensureWorkspace();
    if (asksIdentity() && pendingPrf) {
      try { await unlockIdentity(); } catch (e) { fail((e && e.message) || t('err.generic')); }
    }
    var res = await api('POST', '/oidc/authorize/app', { params: server.data.params });
    if (res.redirect) {
      if (res.paused) { pausedRedirect = res.redirect; redraw(); return; }
      location.replace(res.redirect);
      return;
    }
    consent = res;
    show($('app-way'), false);
  } catch (e) {
    fail((e && e.message) || t('err.load'));
  }
  redraw();
}

if (server.problem) {
  show($('app-way'), false);
} else {
  host = String(server.data.client).replace(/^https?:\/\//, '');
}
redraw();
if (!server.problem) startSignIn('si.auth', afterSignIn, asksIdentity());
`
