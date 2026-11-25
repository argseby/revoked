package routes

// connectPageScript connects a tool in the browser (BROWSER.md §4.6). It shows
// what the app's connect screen shows, signs in, and posts the owner's choice
// to POST /api/connections/authorize, the endpoint the app uses. The answer
// goes back through the tool's return address in this same tab, never by
// polling, so the vault and requests:manage stay limited to answers that
// reach the owner's own browser.
//
// The session alone authorizes the connection, as it does for the app. A
// passkey approval here would be checked by nothing until the server requires
// one of both clients (BROWSER.md §10.3).
const connectPageScript = `
var req = server.data || {};
var host = '';
var catalogue = {};
var rows = { perms: {}, vault: null, section: null, revoke: null, handOver: null };

function back(params) {
  var u = new URL(req.redirect);
  Object.keys(params).forEach(function (k) { u.searchParams.set(k, params[k]); });
  location.replace(u.toString());
}

function asks(key) { return (req.permissions || []).indexOf(key) >= 0; }

function reason(key) {
  var text = req.reasons && req.reasons[key];
  if (!text) return null;
  var q = el('div', 'quote');
  q.appendChild(el('div', 'entry-reason', t('cn.why', req.name)));
  q.appendChild(el('div', '', '“' + text + '”'));
  return q;
}

function permissionsToSend() {
  var keys = [];
  (req.permissions || []).forEach(function (k) {
    if (k.indexOf('vault:') === 0) return;
    if (rows.perms[k] && rows.perms[k].box.checked) keys.push(k);
  });
  if (req.section && rows.section && rows.section.box.checked) {
    keys.push(!asks('vault:read') || asks('vault:write') ? 'vault:write' : 'vault:read');
  } else {
    ['vault:read', 'vault:write'].forEach(function (k) {
      if (asks(k) && rows.perms[k] && rows.perms[k].box.checked) keys.push(k);
    });
  }
  if (!(req.permissions || []).length && !req.section) return undefined;
  return keys;
}

async function connect() {
  fail('');
  var body = {
    clientId: req.client, clientName: req.name, redirectUri: req.redirect, challenge: req.challenge,
    allowRevoke: rows.revoke.box.checked, allowHandOver: rows.handOver.box.checked
  };
  if (req.vault) body.allowVaultRead = rows.vault.box.checked;
  if (req.section) body.section = rows.section.box.checked;
  var perms = permissionsToSend();
  if (perms) body.permissions = perms;
  try {
    var res = await api('POST', '/api/connections/authorize', body);
    back({ state: req.state, status: 'connected', server: location.origin, code: res.code });
  } catch (e) {
    fail((e && e.message) || t('err.generic'));
  }
}

redraw = function () {
  var flow = $('flow');
  flow.textContent = '';
  if (server.problem) {
    heading(t('cn.problem'), t('cn.problemLead'), 'alert', 'bad');
    return;
  }
  heading(t('cn.title', req.name), t('cn.lead', req.name, host), 'key');
  var facts = el('div', 'facts');
  [[t('cn.address'), req.client], [t('cn.name'), req.name + ' · ' + t('cn.nameNote')]].forEach(function (f) {
    var row = el('div', 'fact');
    row.appendChild(el('span', 'fact-k', f[0]));
    row.appendChild(el('span', 'fact-v', f[1]));
    facts.appendChild(row);
  });
  flow.appendChild(facts);
  if (!session) return;

  flow.appendChild(el('p', 'section-t', t('cn.actions')));
  if (req.section) {
    rows.section = rows.section || checkRow(t('cn.section', req.name), t('cn.sectionNote'), true, false);
    flow.appendChild(rows.section);
    var rs = reason('section');
    if (rs) flow.appendChild(rs);
  }
  (req.permissions || []).forEach(function (k) {
    if (req.section && k.indexOf('vault:') === 0) return;
    var p = catalogue[k] || { label: k, description: '' };
    rows.perms[k] = rows.perms[k] || checkRow(p.label, p.description, true, false);
    flow.appendChild(rows.perms[k]);
  });
  var rp = reason('permissions');
  if (rp) flow.appendChild(rp);
  if (req.vault) {
    rows.vault = rows.vault || checkRow(t('cn.vault'), t('cn.vaultNote'), false, false);
    flow.appendChild(rows.vault);
    var rv = reason('vault');
    if (rv) flow.appendChild(rv);
  }
  rows.handOver = rows.handOver || checkRow(t('cn.handOver'), t('cn.handOverNote'), true, false);
  flow.appendChild(rows.handOver);
  var rl = reason('links');
  if (rl) flow.appendChild(rl);
  rows.revoke = rows.revoke || checkRow(t('cn.revoke'), t('cn.revokeNote'), true, false);
  flow.appendChild(rows.revoke);
  var rr = reason('revoke');
  if (rr) flow.appendChild(rr);
  flow.appendChild(el('p', 'fine left', t('cn.expiry')));

  var go = button('big', t('cn.connect'), null);
  go.addEventListener('click', busyWhile(go, connect));
  flow.appendChild(go);
  flow.appendChild(button('quiet', t('cn.decline'), function () {
    back({ state: req.state, status: 'declined', server: location.origin });
  }));
  flow.appendChild(signedInLine());
};

async function afterSignIn() {
  try {
    await ensureWorkspace();
    var res = await fetch('/api/permissions');
    var data = await res.json();
    (data.permissions || []).forEach(function (p) { catalogue[p.key] = p; });
  } catch (e) {
    fail((e && e.message) || t('err.load'));
  }
  show($('app-way'), false);
  redraw();
}

if (server.problem) {
  show($('app-way'), false);
} else {
  host = String(req.client).replace(/^https?:\/\//, '');
}
redraw();
if (!server.problem) startSignIn('auth.leadAnswers', afterSignIn);
`
