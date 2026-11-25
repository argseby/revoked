package routes

// answersPageScript lists the answers this account gave and lets the
// responder pause, resume and revoke them and change what they grant
// (BROWSER.md §4.3). Invariant 12 holds only if a responder without the app
// can still manage an answer, so this page is the browser's half of it. It
// uses the collection endpoints and their rules; it adds no access path.
const answersPageScript = `
var links = null, byId = {};
var editing = {}, confirming = {};

function statusOf(l) {
  if (l.status === 'active' && l.expiresAt && new Date(l.expiresAt).getTime() < Date.now()) return 'expired';
  return l.status || 'active';
}
var TONE = { active: 'ok', paused: 'warn', revoked: 'bad', expired: 'bad' };
function carrierOf(id) {
  var rec = byId[id];
  if (!rec) return null;
  return rec.aliasOf && byId[rec.aliasOf] ? byId[rec.aliasOf] : rec;
}

async function setStatus(l, status) {
  fail('');
  try {
    var updated = await api('PATCH', '/api/collections/links/records/' + encodeURIComponent(l.id), { status: status });
    Object.assign(l, updated);
    delete confirming[l.id];
  } catch (e) { fail((e && e.message) || t('err.generic')); }
  redraw();
}
async function saveValue(key, rec, input) {
  fail('');
  try {
    var updated = await api('PATCH', '/api/collections/records/records/' + encodeURIComponent(rec.id), { value: input.value });
    byId[rec.id] = Object.assign(rec, updated);
    delete editing[key];
  } catch (e) { fail((e && e.message) || t('err.generic')); }
  redraw();
}

function grantRow(l, key, id) {
  var rec = byId[id], carrier = carrierOf(id);
  var editKey = l.id + '/' + key;
  var label = labelOf(rec, key);
  if (carrier && !carrier.sealed && editing[editKey]) {
    var form = el('div', 'form-row edit-row');
    form.appendChild(el('span', 'form-row-t', label));
    var input = editing[editKey];
    form.appendChild(input);
    form.appendChild(el('span', 'entry-reason', t('ans.editNote')));
    var actions = el('div', 'row');
    var save = button('big small', t('ans.save'), null);
    save.addEventListener('click', busyWhile(save, function () { return saveValue(editKey, carrier, input); }));
    actions.appendChild(save);
    actions.appendChild(button('quiet small', t('ans.cancel'), function () { delete editing[editKey]; redraw(); }));
    form.appendChild(actions);
    return form;
  }
  var row = el('div', 'asked-row');
  var text = el('span', 'locked-t');
  text.appendChild(el('span', 'entry-reason', label));
  if (!carrier) text.appendChild(el('span', 'summary-v muted', t('ans.gone')));
  else if (carrier.sealed) text.appendChild(el('span', 'summary-v muted', t('ans.sealed')));
  else text.appendChild(el('span', 'summary-v', carrier.value || ''));
  row.appendChild(text);
  if (carrier && !carrier.sealed && statusOf(l) !== 'revoked' && carrier.type !== 'file') {
    var edit = el('button', 'text-btn', t('ans.edit'));
    edit.type = 'button';
    edit.setAttribute('aria-label', t('ans.edit') + ': ' + label);
    edit.addEventListener('click', function () {
      var input = el('textarea');
      input.rows = 1;
      input.setAttribute('aria-label', label);
      input.value = carrier.value || '';
      editing[editKey] = input;
      redraw();
      input.focus();
    });
    row.appendChild(edit);
  }
  return row;
}

function answerCard(l) {
  var card = el('div', 'entry');
  var status = statusOf(l);
  var head = el('div', 'entry-h');
  head.appendChild(el('span', 'entry-t', l.label || t('req.untitled')));
  head.appendChild(el('span', 'pill ' + (TONE[status] || ''), t('status.' + status)));
  card.appendChild(head);
  var meta = [t('ans.answered', formatDate(l.created))];
  if (l.expiresAt) meta.push(t('ans.expires', formatDate(l.expiresAt)));
  card.appendChild(el('p', 'entry-reason', meta.join(' · ')));

  var grants = l.grants || {};
  var list = el('div', 'asked summary');
  Object.keys(grants).forEach(function (key) { list.appendChild(grantRow(l, key, grants[key])); });
  card.appendChild(list);

  if (status === 'revoked') return card;
  if (confirming[l.id]) {
    card.appendChild(callout('warn', 'alert', t('ans.revokeAsk')));
    var yes = button('quiet small danger', t('ans.revokeGo'), null);
    yes.addEventListener('click', busyWhile(yes, function () { return setStatus(l, 'revoked'); }));
    var row = el('div', 'row');
    row.appendChild(yes);
    row.appendChild(button('quiet small', t('ans.cancel'), function () { delete confirming[l.id]; redraw(); }));
    card.appendChild(row);
    return card;
  }
  var actions = el('div', 'row');
  if (status === 'active' || status === 'paused') {
    var next = status === 'active' ? 'paused' : 'active';
    var toggle = button('quiet small', t(status === 'active' ? 'ans.pause' : 'ans.resume'), null);
    toggle.addEventListener('click', busyWhile(toggle, function () { return setStatus(l, next); }));
    actions.appendChild(toggle);
  }
  actions.appendChild(button('quiet small danger', t('ans.revoke'), function () { confirming[l.id] = true; redraw(); }));
  card.appendChild(actions);
  return card;
}

redraw = function () {
  var flow = $('flow');
  flow.textContent = '';
  if (!session) { heading(t('ans.title'), t('ans.lead')); return; }
  if (!links) return;
  if (!links.length) {
    heading(t('ans.none'), t('ans.noneLead'));
  } else {
    heading(t('ans.title'), t('ans.lead'));
    links.forEach(function (l) { flow.appendChild(answerCard(l)); });
  }
  flow.appendChild(signedInLine());
};

async function afterSignIn() {
  var me = session.user.id;
  redraw();
  try {
    var recs = await api('GET', listPath('records', 'user = ' + quoted(me)));
    (recs.items || []).forEach(function (r) { byId[r.id] = r; });
    var res = await api('GET', listPath('links', 'user = ' + quoted(me) + ' && request != ""', '&sort=-created'));
    links = res.items || [];
  } catch (e) {
    links = [];
    fail((e && e.message) || t('err.load'));
  }
  redraw();
}

show($('app-way'), false);
redraw();
startSignIn('auth.leadAnswers', afterSignIn);
`
