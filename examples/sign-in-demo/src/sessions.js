// Sessions kept in memory. A browser's is named by a random cookie; an app,
// which has no cookie jar, holds the name itself and sends it back as a bearer
// token. The two kinds never stand in for each other. A restart signs everyone
// out, which is all a demo needs; a real service would use its own store.

import { randomBytes } from 'node:crypto';
import { config } from './config.js';

const COOKIE = 'sid';
const TTL_MS = 8 * 60 * 60 * 1000;
const sessions = new Map();

function parseCookies(header = '') {
  const out = {};
  for (const part of header.split(';')) {
    const at = part.indexOf('=');
    if (at > 0) out[part.slice(0, at).trim()] = decodeURIComponent(part.slice(at + 1).trim());
  }
  return out;
}

function cookie(value, maxAgeSeconds) {
  return [
    `${COOKIE}=${value}`,
    'Path=/',
    'HttpOnly',
    'SameSite=Lax',
    `Max-Age=${maxAgeSeconds}`,
    config.secureCookies ? 'Secure' : '',
  ]
    .filter(Boolean)
    .join('; ');
}

function create(kind) {
  const id = randomBytes(32).toString('base64url');
  const data = { grantCache: new Map() };
  sessions.set(id, { kind, data, expires: Date.now() + TTL_MS });
  return { id, data };
}

function find(id, kind) {
  const existing = id && sessions.get(id);
  return existing && existing.kind === kind && existing.expires > Date.now() ? existing.data : null;
}

function bearer(req) {
  const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(req.headers.authorization ?? '');
  return match?.[1];
}

// Returns the browser's session, creating one when there is none.
export function session(req, res) {
  const existing = find(parseCookies(req.headers.cookie)[COOKIE], 'browser');
  if (existing) return existing;
  const { id, data } = create('browser');
  res.setHeader('Set-Cookie', cookie(id, TTL_MS / 1000));
  return data;
}

export function endSession(req, res) {
  const id = parseCookies(req.headers.cookie)[COOKIE];
  if (id && sessions.get(id)?.kind === 'browser') sessions.delete(id);
  res.setHeader('Set-Cookie', cookie('', 0));
}

// A new session for an app. The app keeps `token` and sends it as
// `Authorization: Bearer <token>`.
export function startAppSession() {
  const { id, data } = create('app');
  return { token: id, expiresIn: TTL_MS / 1000, data };
}

// The app's session, or null without a valid bearer token.
export function appSession(req) {
  return find(bearer(req), 'app');
}

export function endAppSession(req) {
  const id = bearer(req);
  if (id && sessions.get(id)?.kind === 'app') sessions.delete(id);
}

// Expired sessions are dropped now and then rather than on every request.
setInterval(() => {
  const now = Date.now();
  for (const [id, s] of sessions) if (s.expires <= now) sessions.delete(id);
}, 10 * 60 * 1000).unref();
