// Local manual test harness. Credentials stay in the demo's browser session
// on the Node process, so returning in a new browser tab still works.
import { createHash, randomBytes } from 'node:crypto';
import { config } from './config.js';
import { issuerFor } from './auth.js';
import { session } from './sessions.js';

const pending = new Map();
const lifetime = 10 * 60 * 1000;
const name = 'Showdown demo';

export function toolRequest(kind, client, state, challenge) {
  if (!['connect', 'vault', 'share'].includes(kind)) throw new Error('Unknown flow.');
  const params = new URLSearchParams({
    client, redirect: `${client}/playground/return`, state, challenge,
    links_reason: 'To show your approved sharing link on your profile.',
    revoke_reason: 'To stop sharing when you turn your status off.',
  });
  if (kind === 'share') {
    params.set('from', name);
    params.set('label', 'My current game');
    params.set('keys', 'now_playing');
    params.set('ref', `playground-${state.slice(0, 8)}`);
  } else {
    params.set('name', name);
    params.set('section', '1');
    params.set('permissions', 'shares:read,shares:manage,requests:manage,attestations:issue,vault:read,vault:write');
    params.set('section_reason', 'To keep one entry up to date with the game you are playing.');
    params.set('permissions_reason', 'To share your game, collect player details and issue participation attestations.');
    if (kind === 'vault') {
      params.set('vault', 'read');
      params.set('vault_reason', 'To find existing game entries outside the section created for this demo.');
    }
  }
  return `revoked://${kind === 'share' ? 'p' : 'connect'}?${params}`;
}

export function serverOrigin(raw) {
  const url = new URL(raw);
  if (url.username || url.password || url.pathname !== '/' || url.search || url.hash) {
    throw new Error('The Revoked server must be an origin without a path or credentials.');
  }
  const allowed = issuerFor(url.origin);
  if (url.origin !== allowed) throw new Error('Use HTTPS, or HTTP on localhost.');
  return allowed;
}

async function upstream(connection, path, method = 'GET', body) {
  const res = await fetch(`${connection.server}${path}`, {
    method, redirect: 'error', signal: AbortSignal.timeout(15000),
    headers: {
      'Content-Type': 'application/json',
      ...(connection.token && { 'X-Revoked-Connection': connection.token }),
    },
    ...(body && { body: JSON.stringify(body) }),
  });
  const text = await res.text();
  let result;
  try { result = text ? JSON.parse(text) : {}; } catch { result = { message: text.slice(0, 500) }; }
  if (!res.ok) {
    const error = new Error(`Revoked HTTP ${res.status}: ${JSON.stringify(result)}`);
    error.status = res.status;
    throw error;
  }
  return result;
}

// Only explicit, bounded demo actions; never an arbitrary API proxy.
export async function performAction(data, action, call = upstream) {
  const connection = data.connection;
  if (!connection) throw new Error('Connect the demo first.');
  switch (action) {
    case 'status': return call(connection, '/api/connection');
    case 'vault': return call(connection, '/api/vault');
    case 'write': {
      const body = { key: 'now_playing', label: 'Now playing', value: 'Hunt: Showdown' };
      if (!data.record) {
        const listing = await call(connection, '/api/vault');
        data.record = listing.records?.find(record => record.key === body.key && record.writable === true);
      }
      data.record = await call(connection,
        data.record ? `/api/vault/${encodeURIComponent(data.record.id)}` : '/api/vault',
        data.record ? 'PATCH' : 'POST', body);
      return data.record;
    }
    case 'share': {
      if (!data.record?.id) throw new Error('Create the sample record first.');
      data.link = await call(connection, '/api/connection/links', 'POST', {
        label: 'Demo: now playing', records: [data.record.id], ref: 'playground-record',
      });
      return data.link;
    }
    case 'revoke': {
      if (!data.link?.id) throw new Error('Create a sample sharing link first.');
      return call(connection, `/api/connection/links/${encodeURIComponent(data.link.id)}/revoke`, 'POST');
    }
    case 'disconnect': {
      const result = await call(connection, '/api/connection', 'DELETE');
      delete data.connection;
      delete data.record;
      delete data.link;
      data.message = 'Disconnected. Records and links remain in your vault. Consent can be tested again.';
      return result;
    }
    default: throw new Error('Unknown demo action.');
  }
}

export async function playgroundStatus(s, call = upstream) {
  const owner = s.playground ?? {};
  let connectionState = 'not-connected';
  let connectionError;
  let connection;
  if (owner.connection) {
    try {
      connection = await call(owner.connection, '/api/connection');
      connectionState = 'connected';
    } catch (err) {
      connectionState = err.status === 401 ? 'inactive' : 'unavailable';
      connectionError = err.message;
    }
  }
  return {
    authenticated: Boolean(s.user),
    user: s.user ? {
      name: s.user.name, email: s.user.email, issuer: s.user.issuer,
    } : null,
    connected: connectionState === 'connected',
    connectionState,
    connectionError,
    connection,
    server: owner.connection?.server,
    message: owner.message ?? 'Ready. Choose a flow below.',
  };
}

setInterval(() => {
  for (const [state, entry] of pending) if (entry.expires < Date.now()) pending.delete(state);
}, 60000).unref();

export async function playgroundRoute(req, res, url, { readJson, sendJson, redirect }) {
  if (!url.pathname.startsWith('/playground/')) return false;
  const data = () => {
    const s = session(req, res);
    return s.playground ??= {};
  };
  try {
    if (req.method === 'POST' && url.pathname === '/playground/start') {
      const body = await readJson(req);
      const owner = data();
      const state = randomBytes(24).toString('base64url');
      const verifier = randomBytes(32).toString('base64url');
      const challenge = createHash('sha256').update(verifier).digest('base64url');
      const link = toolRequest(body?.kind, config.clientId, state, challenge);
      pending.set(state, { verifier, owner, expires: Date.now() + lifetime });
      owner.message = 'Waiting for your decision in Revoked.';
      sendJson(res, 200, { app_link: link });
      return true;
    }
    if (req.method === 'GET' && url.pathname === '/playground/return') {
      const state = url.searchParams.get('state');
      const entry = pending.get(state);
      pending.delete(state);
      if (!entry || entry.expires < Date.now()) {
        return redirect(res, '/playground?result=expired'), true;
      }
      try {
        const status = url.searchParams.get('status');
        if (!['connected', 'created', 'declined'].includes(status)) throw new Error('Unknown callback status.');
        if (status === 'declined') {
          entry.owner.message = 'Declined or cancelled. No new connection was approved.';
        } else if (status === 'created' && !url.searchParams.get('code')) {
          entry.owner.message = 'Link created. No new connection token was returned. Review the link in Revoked.';
        } else {
          const server = serverOrigin(url.searchParams.get('server'));
          const code = url.searchParams.get('code');
          if (!code) throw new Error('The callback did not contain a connection code.');
          const result = await upstream({ server }, '/api/connect/token', 'POST', {
            code, verifier: entry.verifier, redirectUri: `${config.clientId}/playground/return`,
          });
          if (typeof result.token !== 'string' || !result.token) throw new Error('No connection token returned.');
          entry.owner.connection = { server, token: result.token };
          entry.owner.message = status === 'created'
            ? 'Link created and tool connected. Refresh the connection to see the result.'
            : 'Connected. Refresh the connection to inspect the permissions you allowed.';
        }
      } catch (err) {
        entry.owner.message = `Connection failed: ${err.message}`;
      }
      redirect(res, '/playground');
      return true;
    }
    if (req.method === 'GET' && url.pathname === '/playground/status') {
      sendJson(res, 200, await playgroundStatus(session(req, res)));
      return true;
    }
    if (req.method === 'POST' && url.pathname === '/playground/action') {
      const body = await readJson(req);
      const result = await performAction(data(), body?.action);
      sendJson(res, 200, result);
      return true;
    }
  } catch (err) {
    sendJson(res, 400, { error: err.message });
    return true;
  }
  return false;
}
