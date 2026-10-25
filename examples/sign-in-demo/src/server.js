// The demo's web server: four routes and a stylesheet, on node:http alone.
//
//   GET  /          the sign-in page, or the account once signed in
//   POST /login/app starts a sign-in through the person's Revoked app
//   GET  /callback  where the Revoked app sends the browser back
//   POST /logout    ends the session here (there is none at the provider)

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { config } from './config.js';
import { beginAppSignIn, completeSignIn } from './auth.js';
import { readGrants, GrantError } from './grants.js';
import { session, endSession } from './sessions.js';
import { signInPage, accountPage, errorPage } from './views.js';

const stylesheet = await readFile(new URL('../public/style.css', import.meta.url));

function send(res, status, html) {
  res.writeHead(status, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
    // form-action covers where a form's answer redirects to: the Revoked app.
    'Content-Security-Policy': "default-src 'none'; style-src 'self'; form-action 'self' revoked:; base-uri 'none'; frame-ancestors 'none'",
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

// Hands the sign-in to the Revoked app, where the person approves it. If the
// app is not installed, the browser has nowhere to go and stays on the
// sign-in page: signing in needs the app.
async function loginWithApp(req, res) {
  const s = session(req, res);
  const { url, pending } = await beginAppSignIn();
  s.pending = pending;
  redirect(res, url);
}

async function callback(req, res, url) {
  const s = session(req, res);
  const pending = s.pending;
  // Spent whatever happens next: a sign-in is finished once.
  delete s.pending;
  if (!pending) return send(res, 400, errorPage('No sign-in was in progress. Please start again.'));

  const error = url.searchParams.get('error');
  if (error === 'access_denied') return redirect(res, '/');
  if (error) {
    return send(res, 400, errorPage(url.searchParams.get('error_description') || error));
  }

  // The library checks state, iss and the code against what was remembered,
  // redeems the code with the PKCE verifier, and verifies the ID token.
  const callbackUrl = new URL(config.redirectUri);
  callbackUrl.search = url.search;
  try {
    s.user = await completeSignIn(pending, callbackUrl);
    s.grantCache = new Map();
  } catch (err) {
    console.error('Sign-in failed:', err);
    return send(res, 400, errorPage(err.message));
  }
  redirect(res, '/');
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, config.clientId);
  try {
    if (req.method === 'GET' && url.pathname === '/') return await home(req, res);
    if (req.method === 'POST' && url.pathname === '/login/app') return await loginWithApp(req, res);
    if (req.method === 'GET' && url.pathname === '/callback') return await callback(req, res, url);
    if (req.method === 'POST' && url.pathname === '/logout') {
      endSession(req, res);
      return redirect(res, '/');
    }
    if (req.method === 'GET' && url.pathname === '/style.css') {
      res.writeHead(200, { 'Content-Type': 'text/css; charset=utf-8' });
      return res.end(stylesheet);
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
