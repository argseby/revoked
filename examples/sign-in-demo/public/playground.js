const status = document.getElementById('status');
const output = document.getElementById('output');
const summary = document.getElementById('result-summary');
const openApp = document.getElementById('open-app');
const resultLink = document.getElementById('result-link');
const authStatus = document.getElementById('auth-status');
const connectionStatus = document.getElementById('connection-status');
let refreshing = false;

async function api(path, body) {
  const res = await fetch(path, {
    ...(body && { method: 'POST', body: JSON.stringify(body), headers: { 'Content-Type': 'application/json' } }),
  });
  const result = await res.json();
  if (!res.ok) throw new Error(result.error ?? `HTTP ${res.status}`);
  return result;
}

async function refresh() {
  if (refreshing) return;
  refreshing = true;
  try {
    const result = await api('/playground/status');
    status.textContent = result.message;
    authStatus.textContent = result.authenticated
      ? `Signed in${result.user.name || result.user.email ? ` as ${result.user.name || result.user.email}` : ''} with ${result.user.issuer}.`
      : 'Not signed in to Corner Shop. Use “Sign in with Revoked” below.';
    connectionStatus.textContent = result.connected
      ? `Showdown demo is connected to ${result.server}. Allowed permissions: ${(result.connection.permissions ?? []).join(', ') || 'proposed-link controls only'}.`
      : result.connectionState === 'not-connected'
        ? 'Showdown demo is not connected in this browser session.'
        : `Showdown demo is ${result.connectionState === 'inactive' ? 'paused, disconnected or expired' : 'unreachable'}. ${result.connectionError}`;
    if (result.connectionError) status.textContent = 'The saved tool connection could not be verified. See its status below.';
    if (new URLSearchParams(location.search).get('result') === 'expired') {
      status.textContent = 'That request expired or was already answered. Start a new one.';
      history.replaceState(null, '', '/playground');
    }
  } finally {
    refreshing = false;
  }
}

function show(value, message) {
  summary.textContent = message;
  output.textContent = JSON.stringify(value, null, 2);
  resultLink.hidden = true;
  if (typeof value.url === 'string') {
    try {
      const url = new URL(value.url);
      if (['https:', 'http:'].includes(url.protocol)) {
        resultLink.href = url.href;
        resultLink.hidden = false;
      }
    } catch { /* API result is shown as text regardless. */ }
  }
}

document.addEventListener('click', async event => {
  const button = event.target.closest('button[data-start],button[data-action]');
  if (!button) return;
  if (button.dataset.action === 'disconnect' && !confirm('Disconnect this demo? Records and links remain in Revoked.')) return;
  if (button.dataset.action === 'revoke' && !confirm('Revoke the sample sharing link created by this demo?')) return;
  button.disabled = true;
  openApp.hidden = true;
  try {
    if (button.dataset.start) {
      const result = await api('/playground/start', { kind: button.dataset.start });
      show(result, 'Request ready. Approve or decline it in Revoked, then return here.');
      openApp.href = result.app_link;
      openApp.hidden = false;
      // Keep a real link available when the browser blocks automatic app opening.
      openApp.click();
    } else {
      const result = await api('/playground/action', { action: button.dataset.action });
      show(result, `${button.textContent}: completed.`);
    }
    await refresh();
  } catch (err) {
    show({ error: err.message }, 'The action did not complete. Check the selected permissions or connection status.');
  } finally {
    button.disabled = false;
  }
});

function proposal(kind, values) {
  const params = new URLSearchParams({ client: location.origin, ref: `playground-${Date.now()}`, ...values });
  openApp.href = `revoked://${kind}?${params}`;
  openApp.hidden = false;
  show({ app_link: openApp.href }, 'Review and finish this proposal in Revoked. Refresh the connection afterwards.');
  openApp.click();
}

document.getElementById('request-form').addEventListener('submit', event => {
  event.preventDefault();
  proposal('pr', { from: 'Showdown demo', template: document.getElementById('template').value.trim(), label: 'Demo player registration', days: '7' });
});
document.getElementById('attest-form').addEventListener('submit', event => {
  event.preventDefault();
  proposal('attest', { name: 'Showdown demo', type: 'participation', claims: 'event', for: document.getElementById('fingerprint').value.trim().toLowerCase() });
});
document.getElementById('check').addEventListener('click', () => {
  proposal('check', { from: 'Showdown demo', type: 'participation', claims: 'event' });
});
window.addEventListener('focus', () => refresh().catch(err => { status.textContent = err.message; }));
document.addEventListener('visibilitychange', () => {
  if (!document.hidden) refresh().catch(err => { status.textContent = err.message; });
});
document.getElementById('refresh-status').addEventListener('click', () => {
  refresh().catch(err => { status.textContent = err.message; });
});
document.addEventListener('revoked-sign-in-done', event => {
  event.preventDefault();
  refresh().catch(err => { status.textContent = err.message; });
});
refresh().catch(err => { status.textContent = err.message; });
