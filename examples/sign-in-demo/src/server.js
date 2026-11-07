// The demo's web server, on node:http alone.
//
//   GET  /            the sign-in page, or the account once signed in
//   POST /login/start prepares a sign-in for the button to show
//   POST /login/wait  the page asks here until the sign-in is finished
//   GET  /callback    where the Revoked app delivers its answer
//   POST /logout      ends the session here (there is none at the provider)

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { config } from './config.js';
import { beginAppSignIn, completeSignIn } from './auth.js';
import { readGrants, GrantError } from './grants.js';
import { session, endSession, startAppSession, appSession, endAppSession } from './sessions.js';
import { remember, takeForAnswer, finish, collect } from './signins.js';
import { signInPage, accountPage, errorPage } from './views.js';

const assets = new Map(
  await Promise.all(
    [
      ['/style.css', '../public/style.css', 'text/css'],
      ['/revoked/revoked-sign-in.js', '../../sign-in-button/revoked-sign-in.js', 'text/javascript'],
    ].map(async ([path, file, type]) => [
      path,
      { type: `${type}; charset=utf-8`, body: await readFile(new URL(file, import.meta.url)) },
    ]),
  ),
);

function send(res, status, html) {
  res.writeHead(status, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Security-Policy': "default-src 'none'; script-src 'self'; connect-src 'self'; style-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
  });
  res.end(html);
}

function redirect(res, location) {
  res.writeHead(303, { Location: location, 'Cache-Control': 'no-store' });
  res.end();
}

async function home(req, res) {
  const s = session(req, res);
  if (!s.user) {
    return send(res, 200, signInPage({ requestedKeys: config.requestedKeys }));
  }
  let grants = [];
  let grantError = null;
  try {
    grants = await readGrants(s.user, s.grantCache);
  } catch (err) {
    grantError =
      err instanceof GrantError ? err.message : `Your Revoked server could not be reached (${err.message}).`;
  }
  send(res, 200, accountPage({ user: s.user, grants, grantError }));
}

function sendJson(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body));
}

const MAX_BODY = 4096;

async function readJson(req) {
  // The content type keeps a cross-site form from reaching these routes. Its
  // parameters are ignored: some clients add `; charset=utf-8`.
  const type = (req.headers['content-type'] ?? '').split(';')[0].trim().toLowerCase();
  if (type !== 'application/json') return null;
  let raw = '';
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > MAX_BODY) return null;
  }
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

// Prepares a sign-in. Nothing here says whether the Revoked app is on this
// device, so the button offers both: a QR code and a link.
async function loginStart(req, res) {
  if (!(await readJson(req))) return sendJson(res, 400, { error: 'bad_request' });
  const { url, checkCode, pending } = await beginAppSignIn();
  sendJson(res, 200, { app_link: url, check_code: checkCode, wait: remember(pending) });
}

// The answer usually comes from a phone, so there is no session or cookie to
// find here: `state` alone says which sign-in it belongs to. The app does not
// follow this redirect; a browser only lands here if the app had to hand the
// answer to one.
async function callback(req, res, url) {
  const entry = takeForAnswer(url.searchParams.get('state'));
  if (!entry) return redirect(res, '/');

  const error = url.searchParams.get('error');
  if (error) {
    finish(entry, { error });
    return redirect(res, '/');
  }

  // The library checks state, iss and the code against what was remembered,
  // redeems the code with the PKCE verifier, and verifies the ID token.
  const callbackUrl = new URL(config.redirectUri);
  callbackUrl.search = url.search;
  try {
    finish(entry, { user: await completeSignIn(entry.pending, callbackUrl) });
  } catch (err) {
    console.error('Sign-in failed:', err);
    finish(entry, { error: 'failed' });
  }
  redirect(res, '/');
}

// This is what ties the sign-in to a browser or an app: only the one that
// started it knows the key, and the session goes to whoever collects with it.
// A browser gets a cookie. An app says `"client": "app"` and gets the session
// in the answer, since it has no cookie jar.
async function loginWait(req, res) {
  const body = await readJson(req);
  const entry = body && typeof body.wait === 'string' ? collect(body.wait) : null;
  if (!entry) return sendJson(res, 401, { error: 'expired' });
  if (!entry.done) return sendJson(res, 200, { done: false });
  if (entry.result.error) return sendJson(res, 200, { done: true, error: entry.result.error });
  if (body.client === 'app') {
    const { token, expiresIn, data } = startAppSession();
    data.user = entry.result.user;
    return sendJson(res, 200, { done: true, session: token, expires_in: expiresIn });
  }
  const s = session(req, res);
  s.user = entry.result.user;
  s.grantCache = new Map();
  sendJson(res, 200, { done: true });
}

// What an app signed in with a session token sees: the person, and the
// entries they share, read fresh from their server like the account page.
async function apiMe(req, res) {
  const s = appSession(req);
  if (!s?.user) return sendJson(res, 401, { error: 'unauthorized' });
  const { issuer, subject, name, email, emailVerified } = s.user;
  let entries = [];
  let entriesError = null;
  try {
    entries = await readGrants(s.user, s.grantCache);
  } catch (err) {
    entriesError = err instanceof GrantError ? err.message : `Your Revoked server could not be reached (${err.message}).`;
  }
  sendJson(res, 200, {
    user: { issuer, subject, name, email, email_verified: emailVerified },
    entries,
    ...(entriesError && { entries_error: entriesError }),
  });
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, config.clientId);
  try {
    if (req.method === 'GET' && url.pathname === '/') return await home(req, res);
    if (req.method === 'POST' && url.pathname === '/login/start') return await loginStart(req, res);
    if (req.method === 'POST' && url.pathname === '/login/wait') return await loginWait(req, res);
    if (req.method === 'GET' && url.pathname === '/callback') return await callback(req, res, url);
    if (req.method === 'GET' && url.pathname === '/api/me') return await apiMe(req, res);
    if (req.method === 'POST' && url.pathname === '/api/logout') {
      endAppSession(req);
      res.writeHead(204, { 'Cache-Control': 'no-store' });
      return res.end();
    }
    if (req.method === 'POST' && url.pathname === '/logout') {
      endSession(req, res);
      return redirect(res, '/');
    }
    const asset = req.method === 'GET' && assets.get(url.pathname);
    if (asset) {
      res.writeHead(200, { 'Content-Type': asset.type });
      return res.end(asset.body);
    }
    send(res, 404, errorPage('There is nothing at this address.'));
  } catch (err) {
    console.error(err);
    if (!res.headersSent) send(res, 500, errorPage('Something went wrong on the shop’s side.'));
  }
});

server.listen(config.port, () => {
  console.log(`Corner Shop at ${config.clientId}`);
  console.log(`  client_id     ${config.clientId}`);
  console.log(`  redirect_uri  ${config.redirectUri}`);
});
