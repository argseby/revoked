// Sessions kept in memory, named by a random cookie. A restart signs everyone
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
    // Lax, not Strict: the browser comes back from the Revoked server with a
    // top-level navigation, and the pending sign-in has to be found then.
    'SameSite=Lax',
    `Max-Age=${maxAgeSeconds}`,
    config.secureCookies ? 'Secure' : '',
  ]
    .filter(Boolean)
    .join('; ');
}

// Returns the request's session, creating one when there is none.
export function session(req, res) {
  const id = parseCookies(req.headers.cookie)[COOKIE];
  const existing = id && sessions.get(id);
  if (existing && existing.expires > Date.now()) return existing.data;

  const fresh = randomBytes(32).toString('base64url');
  const data = { grantCache: new Map() };
  sessions.set(fresh, { data, expires: Date.now() + TTL_MS });
  res.setHeader('Set-Cookie', cookie(fresh, TTL_MS / 1000));
  return data;
}

export function endSession(req, res) {
  const id = parseCookies(req.headers.cookie)[COOKIE];
  if (id) sessions.delete(id);
  res.setHeader('Set-Cookie', cookie('', 0));
}

// Expired sessions are dropped now and then rather than on every request.
setInterval(() => {
  const now = Date.now();
  for (const [id, s] of sessions) if (s.expires <= now) sessions.delete(id);
}, 10 * 60 * 1000).unref();
