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
  heading(t('cn.title', req.name), session ? '' : t('cn.lead', req.name, host));
  eyebrow(t('cn.eyebrow'));
  flow.appendChild(metaLine([req.client, t('cn.nameNote')]));
  if (!session) {
    var asked = [];
    if (req.section) asked.push({ label: t('cn.section', req.name) });
    (req.permissions || []).forEach(function (k) {
      if (req.section && k.indexOf('vault:') === 0) return;
      asked.push({ label: (catalogue[k] && catalogue[k].label) || k });
    });
    if (req.vault) asked.push({ label: t('cn.vault') });
    if (asked.length) flow.appendChild(lockedList(asked, t('cn.actions')));
    return;
  }

  // One list of choices; each reason sits under the choice it explains.
  var head = el('div', 'asked-h');
  head.appendChild(el('span', 'section-t', t('cn.actions')));
  flow.appendChild(head);
  var list = el('div', 'asked choices');
  function add(key, make, reasonKey) {
    rows[key] = rows[key] || make();
    if (reasonKey && !rows[key].reasoned) {
      var r = req.reasons && req.reasons[reasonKey];
      if (r) rows[key].querySelector('.check-t').appendChild(el('span', 'check-reason', t('cn.why', req.name) + ': “' + r + '”'));
      rows[key].reasoned = true;
    }
    list.appendChild(rows[key]);
  }
  if (req.section) add('section', function () { return checkRow(t('cn.section', req.name), t('cn.sectionNote'), true, false); }, 'section');
  var perms = (req.permissions || []).filter(function (k) { return !(req.section && k.indexOf('vault:') === 0); });
  perms.forEach(function (k, i) {
    var p = catalogue[k] || { label: k, description: '' };
    if (!rows.perms[k]) rows.perms[k] = checkRow(p.label, p.description, true, false);
    rows['perm:' + k] = rows.perms[k];
    add('perm:' + k, function () { return rows.perms[k]; }, i === perms.length - 1 ? 'permissions' : '');
  });
  if (req.vault) add('vault', function () { return checkRow(t('cn.vault'), t('cn.vaultNote'), false, false); }, 'vault');
  add('handOver', function () { return checkRow(t('cn.handOver'), t('cn.handOverNote'), true, false); }, 'links');
  add('revoke', function () { return checkRow(t('cn.revoke'), t('cn.revokeNote'), true, false); }, 'revoke');
  flow.appendChild(list);
  flow.appendChild(el('p', 'fine left', t('cn.expiry')));

  var go = button('big', t('cn.connect'), null);
  go.addEventListener('click', busyWhile(go, connect));
  flow.appendChild(go);
  flow.appendChild(button('quiet', t('cn.decline'), function () {
    back({ state: req.state, status: 'declined', server: location.origin });
  }));
  flow.appendChild(signedInLine());
};

async function loadCatalogue() {
  try {
    var data = await (await fetch('/api/permissions')).json();
    (data.permissions || []).forEach(function (p) { catalogue[p.key] = p; });
  } catch (e) {}
}

async function afterSignIn() {
  try {
    await ensureWorkspace();
    if (!Object.keys(catalogue).length) await loadCatalogue();
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
if (!server.problem) {
  loadCatalogue().then(function () { if (!session) redraw(); });
  startSignIn('cn.auth', afterSignIn);
}
`
