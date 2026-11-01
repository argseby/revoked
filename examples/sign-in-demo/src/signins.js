// Sign-ins that have been started and not yet collected, kept in memory.
//
// Two keys, on purpose. `state` travels through the QR code and the person's
// phone, and only answers. `wait` goes to the page that started and nowhere
// else, and is the only way to collect. Someone reading the QR code off a
// screen can therefore answer a sign-in but never take the session.

import { randomBytes } from 'node:crypto';

const LIFETIME_MS = 10 * 60 * 1000;
const byState = new Map();
const byWait = new Map();

export function remember(pending) {
  const entry = {
    pending,
    wait: randomBytes(32).toString('base64url'),
    expires: Date.now() + LIFETIME_MS,
    done: false,
  };
  byState.set(pending.state, entry);
  byWait.set(entry.wait, entry);
  return entry.wait;
}

// The sign-in an answer belongs to. An answer is taken once.
export function takeForAnswer(state) {
  const entry = byState.get(state);
  byState.delete(state);
  return entry && entry.expires > Date.now() ? entry : null;
}

export function finish(entry, result) {
  entry.done = true;
  entry.result = result;
}

// How a sign-in stands, for the page that started it. A finished one is
// handed over once.
export function collect(wait) {
  const entry = byWait.get(wait);
  if (!entry || entry.expires <= Date.now()) {
    byWait.delete(wait);
    return null;
  }
  if (entry.done) byWait.delete(wait);
  return entry;
}

setInterval(() => {
  const now = Date.now();
  for (const [k, e] of byState) if (e.expires <= now) byState.delete(k);
  for (const [k, e] of byWait) if (e.expires <= now) byWait.delete(k);
}, 60 * 1000).unref();
