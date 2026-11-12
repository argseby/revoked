import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createHash } from 'node:crypto';
import { toolRequest, serverOrigin, performAction, playgroundStatus } from '../src/playground.js';

test('status distinguishes sign-in, tool access, inactive tokens and unreachable servers', async () => {
  const anonymous = await playgroundStatus({});
  assert.equal(anonymous.authenticated, false);
  assert.equal(anonymous.connected, false);
  const s = {
    user: { name: 'Alex', email: 'alex@example.com', issuer: 'https://vault.example', subject: 'private-subject' },
    playground: { connection: { server: 'https://vault.example', token: 'private-token' } },
  };
  const active = await playgroundStatus(s, async () => ({ id: 'c1', permissions: ['vault:write'] }));
  assert.equal(active.authenticated, true);
  assert.equal(active.user.name, 'Alex');
  assert.equal(active.connected, true);
  assert.ok(!JSON.stringify(active).includes('private-token'));
  assert.ok(!JSON.stringify(active).includes('private-subject'));
  const paused = await playgroundStatus(s, async () => { throw Object.assign(new Error('connection_paused'), { status: 401 }); });
  assert.equal(paused.authenticated, true);
  assert.equal(paused.connected, false);
  assert.equal(paused.connectionState, 'inactive');
  const offline = await playgroundStatus(s, async () => { throw new Error('fetch failed'); });
  assert.equal(offline.connectionState, 'unavailable');
});

test('tool links exercise every permission and keep reasons in their supported fields', () => {
  for (const kind of ['connect', 'vault', 'share']) {
    const url = new URL(toolRequest(kind, 'http://localhost:4000', 'state', 'challenge'));
    assert.equal(url.host, kind === 'share' ? 'p' : 'connect');
    assert.equal(url.searchParams.get('redirect'), 'http://localhost:4000/playground/return');
    assert.equal(url.searchParams.get('state'), 'state');
    assert.equal(url.searchParams.get('vault'), kind === 'vault' ? 'read' : null);
    for (const [key, reason] of url.searchParams) {
      if (key.endsWith('_reason')) assert.ok(reason.length > 0 && reason.length <= 120);
    }
    if (kind !== 'share') {
      assert.equal(url.searchParams.get('section'), '1');
      assert.deepEqual(url.searchParams.get('permissions').split(','), [
        'shares:read', 'shares:manage', 'requests:manage', 'attestations:issue', 'vault:read', 'vault:write',
      ]);
    }
  }
  assert.throws(() => toolRequest('unknown', 'http://localhost:4000', 's', 'c'));
});

test('callback server validation disallows credentials, paths and remote plaintext', () => {
  assert.equal(serverOrigin('http://localhost:3000'), 'http://localhost:3000');
  assert.equal(serverOrigin('https://vault.example'), 'https://vault.example');
  for (const input of ['http://vault.example', 'https://u:p@vault.example', 'https://vault.example/path', 'https://vault.example?x=1', 'file:///tmp/x']) {
    assert.throws(() => serverOrigin(input));
  }
});

test('sample writes reuse only writable demo records and sharing uses that record', async () => {
  const data = { connection: { server: 'http://localhost:3000', token: 'private' } };
  const calls = [];
  const call = async (_connection, path, method, body) => {
    calls.push({ path, method, body });
    if (path === '/api/vault') return { records: [
      { id: 'other', key: 'now_playing', writable: false },
      { id: 'demo', key: 'now_playing', writable: true },
    ] };
    if (path === '/api/vault/demo') return { id: 'demo', ...body };
    return { id: 'link1' };
  };
  await performAction(data, 'write', call);
  assert.equal(calls[1].path, '/api/vault/demo');
  assert.equal(calls[1].method, 'PATCH');
  await performAction(data, 'share', call);
  assert.deepEqual(calls[2].body.records, ['demo']);
  await performAction(data, 'disconnect', call);
  assert.equal(calls[3].method, 'DELETE');
  assert.equal(data.connection, undefined);
  await assert.rejects(() => performAction(data, 'status', call), /Connect the demo first/);
  await assert.rejects(() => performAction({ connection: {} }, 'arbitrary', call), /Unknown/);
});

async function listen(server) {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return server.address().port;
}

test('HTTP round trip binds answers to the starting session and redeems a code once', async t => {
  const reserve = createServer();
  const port = await listen(reserve);
  await new Promise(resolve => reserve.close(resolve));
  const origin = `http://127.0.0.1:${port}`;
  let expectedChallenge;
  let exchanges = 0;
  const provider = createServer(async (req, res) => {
    let raw = '';
    for await (const chunk of req) raw += chunk;
    res.setHeader('Content-Type', 'application/json');
    if (req.url === '/api/connect/token') {
      const body = JSON.parse(raw);
      assert.equal(body.redirectUri, `${origin}/playground/return`);
      assert.equal(createHash('sha256').update(body.verifier).digest('base64url'), expectedChallenge);
      exchanges++;
      res.end(JSON.stringify({ token: 'secret-demo-token' }));
    } else {
      assert.equal(req.headers['x-revoked-connection'], 'secret-demo-token');
      res.end(JSON.stringify({ id: 'c1', permissions: ['vault:write'] }));
    }
  });
  const providerPort = await listen(provider);
  t.after(() => { provider.closeAllConnections(); provider.close(); });
  const child = spawn(process.execPath, ['src/server.js'], {
    cwd: new URL('../', import.meta.url),
    env: { ...process.env, PORT: String(port), PUBLIC_URL: origin, REVOKED_SERVERS: '' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  t.after(() => child.kill());
  await Promise.race([
    once(child.stdout, 'data'),
    once(child, 'exit').then(([code]) => { throw new Error(`Demo exited: ${code}`); }),
    new Promise((_, reject) => { const timer = setTimeout(() => reject(new Error('Demo startup timed out')), 10000); timer.unref(); }),
  ]);
  const page = await fetch(`${origin}/playground`);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /Try every consent screen/);
  assert.match(page.headers.get('content-security-policy'), /script-src 'self'/);
  const alias = await fetch(`http://localhost:${port}/playground`, { redirect: 'manual' });
  assert.equal(alias.status, 303);
  assert.equal(alias.headers.get('location'), `${origin}/playground`);
  for (const path of ['/playground.js', '/playground.css', '/revoked/revoked-sign-in.js']) {
    assert.equal((await fetch(`${origin}${path}`)).status, 200);
  }
  const started = await fetch(`${origin}/playground/start`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ kind: 'vault' }),
  });
  const cookie = started.headers.get('set-cookie').split(';')[0];
  assert.match(cookie, /^revoked_demo_[a-f0-9]{16}=/);
  const request = new URL((await started.json()).app_link);
  expectedChallenge = request.searchParams.get('challenge');
  const callback = new URL(`${origin}/playground/return`);
  callback.search = new URLSearchParams({ state: request.searchParams.get('state'), status: 'connected', code: 'single-use', server: `http://127.0.0.1:${providerPort}` });
  // The callback may open another tab and carries no cookie from the starter.
  assert.equal((await fetch(callback, { redirect: 'manual' })).status, 303);
  const current = await fetch(`${origin}/playground/status`, { headers: { Cookie: cookie } });
  assert.equal((await current.json()).connected, true);
  const stranger = await fetch(`${origin}/playground/status`);
  assert.equal((await stranger.json()).connected, false);
  const replay = await fetch(callback, { redirect: 'manual' });
  assert.equal(replay.headers.get('location'), '/playground?result=expired');
  assert.equal(exchanges, 1);
  const result = await fetch(`${origin}/playground/action`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Cookie: cookie }, body: JSON.stringify({ action: 'status' }),
  });
  const text = await result.text();
  assert.match(text, /c1/);
  assert.ok(!text.includes('secret-demo-token'));
  for (const answer of [
    { status: 'created', code: 'proposal-code', message: /Link created and tool connected/ },
    { status: 'created', message: /Link created. No new connection token/ },
    { status: 'declined', message: /Declined or cancelled/ },
  ]) {
    const start = await fetch(`${origin}/playground/start`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Cookie: cookie },
      body: JSON.stringify({ kind: 'share' }),
    });
    const link = new URL((await start.json()).app_link);
    expectedChallenge = link.searchParams.get('challenge');
    callback.search = new URLSearchParams({
      state: link.searchParams.get('state'), status: answer.status,
      server: `http://127.0.0.1:${providerPort}`, ...(answer.code && { code: answer.code }),
    });
    await fetch(callback, { redirect: 'manual' });
    const response = await fetch(`${origin}/playground/status`, { headers: { Cookie: cookie } });
    assert.match((await response.json()).message, answer.message);
  }
  assert.equal(exchanges, 2, 'only answers with a new code are exchanged');
});
