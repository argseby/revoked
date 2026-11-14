import { RevokedError } from '../core/errors.js';
import { constantTimeEqual, fromHex, fromUtf8, utf8 } from '../core/encoding.js';
import { WEBHOOK_EVENT_TYPES, WEBHOOK_SECRET_PREFIX } from '../generated/events.js';
import type { UnknownWebhookEvent, WebhookEvent } from './events.js';

const KNOWN = new Set<string>(WEBHOOK_EVENT_TYPES.map((e) => e.type));

/** Whether this SDK version knows the event's type, and so its `data`. */
export function isKnownWebhookEvent(event: WebhookEvent | UnknownWebhookEvent): event is WebhookEvent {
  return KNOWN.has(event.type);
}

export interface VerifyWebhookOptions {
  /** The raw body exactly as received. A re-serialized object will not verify. */
  body: string | Uint8Array<ArrayBuffer>;
  /** The `Revoked-Signature` header: `t=<unix>,v1=<hex>[,v1=<hex>]`. */
  signature: string | null | undefined;
  /** The endpoint's `whsec_…` secret, or several during a rotation. */
  secret: string | string[];
  /** Largest accepted age, in seconds. Default 300. */
  toleranceSec?: number;
  /** Unix seconds; for tests. */
  now?: number;
}

export class WebhookVerificationError extends RevokedError {}

function refuse(code: string, message: string): never {
  throw new WebhookVerificationError({ status: 0, code, message });
}

function parseHeader(header: string): { timestamp: number; signatures: string[] } {
  let timestamp = Number.NaN;
  const signatures: string[] = [];
  for (const part of header.split(',')) {
    const eq = part.indexOf('=');
    if (eq < 0) continue;
    const key = part.slice(0, eq).trim();
    const value = part.slice(eq + 1).trim();
    if (key === 't') timestamp = Number(value);
    else if (key === 'v1') signatures.push(value);
  }
  return { timestamp, signatures };
}

async function hmac(secret: string, message: Uint8Array<ArrayBuffer>): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', utf8(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, message));
}

/**
 * Checks a webhook delivery's signature and age and returns the event.
 * Throws `WebhookVerificationError` on anything else. Deliveries repeat:
 * drop ones whose `id` was already handled.
 */
export async function verifyWebhook(options: VerifyWebhookOptions): Promise<WebhookEvent> {
  if (!options.signature) refuse('webhook_signature_missing', 'The delivery carries no Revoked-Signature header.');
  const { timestamp, signatures } = parseHeader(options.signature);
  if (!Number.isInteger(timestamp) || signatures.length === 0) {
    refuse('webhook_signature_malformed', 'The Revoked-Signature header is malformed.');
  }

  const tolerance = options.toleranceSec ?? 300;
  const now = options.now ?? Math.floor(Date.now() / 1000);
  if (Math.abs(now - timestamp) > tolerance) refuse('webhook_timestamp_out_of_range', 'The delivery is too old or from the future.');

  const secrets = Array.isArray(options.secret) ? options.secret : [options.secret];
  if (secrets.length === 0 || secrets.some((s) => !s.startsWith(WEBHOOK_SECRET_PREFIX))) {
    throw new TypeError(`A webhook secret starts with ${WEBHOOK_SECRET_PREFIX}.`);
  }

  const body = typeof options.body === 'string' ? utf8(options.body) : options.body;
  const signed = new Uint8Array([...utf8(`${timestamp}.`), ...body]);
  const expected = await Promise.all(secrets.map((s) => hmac(s, signed)));

  const valid = signatures.some((candidate) => {
    if (!/^[0-9a-f]{64}$/i.test(candidate)) return false;
    const given = fromHex(candidate);
    return expected.some((e) => constantTimeEqual(e, given));
  });
  if (!valid) refuse('webhook_signature_invalid', 'The signature does not match.');

  return JSON.parse(typeof options.body === 'string' ? options.body : fromUtf8(options.body)) as WebhookEvent;
}
