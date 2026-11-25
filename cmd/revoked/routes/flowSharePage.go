package routes

// sharePageScript opens an identity-protected share in the browser (BROWSER.md
// §4.8). The reader signs in on this server, proves an identity derived from
// the passkey by signing the link's challenge, and gets the values from
// POST /api/public/links/{slug}, the endpoint the app uses. The handshake
// token the server returns is not kept: the next visit signs again.
//
// Values are listed plainly. Encrypted entries, which open with the link key
// in the share page's address, stay with the share page and the app.
const sharePageScript = `
var probe = null, closedMessage = '', opened = null, notFound = false;
var pwInput = null;

async function open() {
  fail('');
  try {
    var ch = await api('GET', '/api/challenges/link/' + encodeURIComponent(server.slug) + '?identityId=' + encodeURIComponent(identity.id));
    var body = { identityId: identity.id, challengeNonce: ch.nonce, challengeSignature: await identitySign(ch.nonce) };
    if (probe.requiresPassword) body.password = pwInput.value;
    opened = await api('POST', '/api/public/links/' + encodeURIComponent(server.slug), body);
    redraw();
  } catch (e) {
    fail((e && e.message) || t('err.generic'));
  }
}

function recordEntry(r) {
  var box = el('div', 'entry');
  box.appendChild(el('span', 'entry-t', r.label || r.key || ''));
  if (r.sealed) {
    box.appendChild(el('div', 'value muted', t('sh.sealed')));
  } else if (r.type === 'file') {
    var a = el('a', 'text-btn', t('sh.download') + (r.filename ? ' · ' + r.filename : ''));
    a.href = '/api/public/links/' + encodeURIComponent(server.slug) + '/files/' + encodeURIComponent(r.id) + '?dl=' + encodeURIComponent(r.downloadToken || '');
    box.appendChild(a);
  } else {
    box.appendChild(el('div', 'value', r.value || ''));
  }
  return box;
}

redraw = function () {
  var flow = $('flow');
  flow.textContent = '';
  if (closedMessage) {
    show($('app-way'), false);
    if (notFound) heading(t('sh.notFound'), t('req.notFoundLead'), 'alert', 'warn');
    else heading(t('req.closed'), closedMessage, 'alert', 'warn');
    return;
  }
  if (!probe) return;
  var name = probe.sharer && probe.sharer.name;
  heading(probe.label || t('sh.untitled'), '');
  eyebrow(name ? t('sh.eyebrow', name) : '');
  if (!opened) flow.appendChild(metaLine([location.host, t('sh.needsIdentity')]));
  if (opened) {
    show($('app-way'), false);
    var records = opened.records || [];
    if (!records.length) flow.appendChild(el('p', 'fine left', t('sh.empty')));
    records.forEach(function (r) { flow.appendChild(recordEntry(r)); });
    flow.appendChild(el('p', 'fine left', t('sh.signedNote', identity.name)));
    return;
  }
  if (!session) return;
  flow.appendChild(identityStep(redraw));
  if (probe.requiresPassword) {
    pwInput = pwInput || el('input');
    pwInput.type = 'password';
    pwInput.autocomplete = 'off';
    var label = el('label', 'field');
    label.appendChild(el('span', '', t('sh.password')));
    label.appendChild(pwInput);
    flow.appendChild(label);
  }
  var go = button('big', t('sh.open'), null);
  go.disabled = !(identity && identity.id);
  go.addEventListener('click', busyWhile(go, open));
  flow.appendChild(go);
  flow.appendChild(signedInLine());
};

async function afterSignIn() {
  try {
    await ensureWorkspace();
    if (pendingPrf) await unlockIdentity();
  } catch (e) {
    fail((e && e.message) || t('err.generic'));
  }
  redraw();
}

(async function () {
  try {
    var res = await fetch('/api/public/links/' + encodeURIComponent(server.slug));
    var data = await res.json().catch(function () { return {}; });
    if (!res.ok) { closedMessage = serverMessage(data); notFound = res.status === 404; redraw(); return; }
    probe = data;
  } catch (e) {
    closedMessage = t('err.load');
    redraw();
    return;
  }
  // A share that asks for no identity is the share page's to show.
  if (!probe.requireHandshake) { location.replace('/s/' + encodeURIComponent(server.slug)); return; }
  redraw();
  startSignIn('sh.auth', afterSignIn, true);
})();
`
