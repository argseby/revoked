import { RevokedError } from '../core/errors.js';
import { randomBytes, sha256, toBase64Url, toHex } from '../core/encoding.js';
import { Transport } from '../core/transport.js';

export interface Pkce {
  /** Keep secret; sent only to `/api/connect/token`. */
  verifier: string;
  /** base64url(SHA-256(verifier)); goes in the link. */
  challenge: string;
}

export async function createPkce(): Promise<Pkce> {
  const verifier = toBase64Url(randomBytes(32));
  return { verifier, challenge: toBase64Url(await sha256(verifier)) };
}

export function createState(): string {
  return toBase64Url(randomBytes(24));
}

/**
 * The code both the tool's page and the owner's app show for a polled
 * connection, so the owner can tell the answer goes to the page they see:
 * the first three bytes of SHA-256(challenge), upper-case hex, `ABC-DEF`.
 */
export async function checkCode(challenge: string): Promise<string> {
  const hex = toHex((await sha256(challenge)).subarray(0, 3)).toUpperCase();
  return `${hex.slice(0, 3)}-${hex.slice(3)}`;
}

const KEY = /^[a-z0-9_-]{1,64}$/;
const STATE = /^[A-Za-z0-9._~-]{1,128}$/;

function invalid(message: string): never {
  throw new TypeError(message);
}

function maxLength(name: string, value: string | undefined, max: number): void {
  if (value !== undefined && [...value].length > max) invalid(`${name} is longer than ${max} characters.`);
}

function clientOrigin(client: string): string {
  const url = new URL(client);
  if (url.origin !== client.replace(/\/$/, '')) invalid('`client` is an origin only, without a path.');
  const local = url.hostname === 'localhost' || url.hostname === '127.0.0.1';
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && local)) {
    invalid('`client` must be https, or http on localhost.');
  }
  return url.origin;
}

function build(kind: string, params: Record<string, string | number | boolean | undefined>): string {
  const parts: string[] = [];
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === false || value === '') continue;
    parts.push(`${key}=${encodeURIComponent(value === true ? '1' : String(value))}`);
  }
  return `revoked://${kind}${parts.length ? `?${parts.join('&')}` : ''}`;
}

/** Where the owner's app sends its answer: back to the tool's page, or held for the page to poll. */
export type Answer =
  | { redirect: string; state: string; challenge?: string }
  | { poll: string; challenge: string; state?: string };

export interface ConnectRequest {
  /** The tool's origin. */
  client: string;
  /** The tool's name, shown as a claim. */
  name?: string;
  answer: Answer;
  /** Ask to read the whole vault. Never granted with polling. */
  vault?: { reason?: string };
  /** Ask for a section of the vault of the tool's own. */
  section?: { reason?: string };
  /** e.g. `shares:manage`, `requests:manage`, `vault:write`. */
  permissions?: { keys: string[]; reason?: string };
  revokeReason?: string;
  linksReason?: string;
}

function answerParams(client: string, answer: Answer | undefined): Record<string, string | undefined> {
  if (!answer) return {};
  if ('redirect' in answer) {
    if (new URL(answer.redirect).origin !== client) invalid('`redirect` must be on the `client` origin.');
    if (!STATE.test(answer.state)) invalid('`state` must match [A-Za-z0-9._~-]{1,128}.');
    return { redirect: answer.redirect, state: answer.state, challenge: answer.challenge };
  }
  if (answer.state !== undefined && !STATE.test(answer.state)) invalid('`state` must match [A-Za-z0-9._~-]{1,128}.');
  return { poll: new URL(answer.poll).origin, challenge: answer.challenge, state: answer.state };
}

/** A `revoked://connect` link asking the owner to connect the tool. */
export function connectLink(request: ConnectRequest): string {
  const client = clientOrigin(request.client);
  if (!request.answer.challenge) invalid('Connecting needs a PKCE `challenge`.');
  if (request.vault && 'poll' in request.answer) invalid('The whole vault is never granted to a polled answer.');
  for (const [name, reason] of [
    ['vault reason', request.vault?.reason],
    ['section reason', request.section?.reason],
    ['permissions reason', request.permissions?.reason],
    ['revoke reason', request.revokeReason],
    ['links reason', request.linksReason],
  ] as const) {
    maxLength(name, reason, 120);
  }
  return build('connect', {
    client,
    name: request.name,
    ...answerParams(client, request.answer),
    vault: request.vault ? 'read' : undefined,
    vault_reason: request.vault?.reason,
    section: request.section ? true : undefined,
    section_reason: request.section?.reason,
    permissions: request.permissions?.keys.join(','),
    permissions_reason: request.permissions?.reason,
    revoke_reason: request.revokeReason,
    links_reason: request.linksReason,
  });
}

export interface ShareProposal {
  label: string;
  /** Record keys, 1–50, each `[a-z0-9_-]{1,64}`. */
  keys: string[];
  /** The tool's name, shown as a claim. Up to 40 characters. */
  from?: string;
  /** A template name describing the keys, so the app can ask for one the vault lacks. */
  template?: string;
  /** Expiry, 1–365 days. */
  days?: number;
  /** Watermark text for files. */
  stamp?: string;
  purpose?: 'application';
  /** The tool's own reference, returned with the link's status once connected. Needs `client`. */
  ref?: string;
  client?: string;
  /** Where the answer goes; with a `challenge`, the proposal also connects the tool. */
  answer?: Answer;
  /** A draft id from `connection.draft()`: suggested values. Needs `client`. */
  draft?: string;
  revokeReason?: string;
  linksReason?: string;
}

/** A `revoked://p` link proposing a share; the owner fills in the values and confirms. */
export function proposeShare(proposal: ShareProposal): string {
  maxLength('label', proposal.label, 120);
  if (!proposal.label.trim()) invalid('A proposal needs a label.');
  if (proposal.keys.length < 1 || proposal.keys.length > 50) invalid('A proposal names 1 to 50 keys.');
  for (const key of proposal.keys) if (!KEY.test(key)) invalid(`Key "${key}" must match [a-z0-9_-]{1,64}.`);
  maxLength('from', proposal.from, 40);
  maxLength('template', proposal.template, 80);
  maxLength('stamp', proposal.stamp, 120);
  maxLength('ref', proposal.ref, 80);
  if (proposal.days !== undefined && !(Number.isInteger(proposal.days) && proposal.days >= 1 && proposal.days <= 365)) {
    invalid('`days` is a whole number from 1 to 365.');
  }
  if (proposal.purpose === 'application' && !proposal.stamp) invalid('An application needs a `stamp`.');
  const client = proposal.client === undefined ? undefined : clientOrigin(proposal.client);
  if (!client && (proposal.ref || proposal.answer || proposal.draft)) invalid('`ref`, `answer` and `draft` need `client`.');
  if (proposal.draft !== undefined && !/^[a-z0-9]{24}$/.test(proposal.draft)) invalid('`draft` is a draft id.');
  return build('p', {
    label: proposal.label,
    keys: proposal.keys.join(','),
    from: proposal.from,
    template: proposal.template,
    days: proposal.days,
    stamp: proposal.stamp,
    purpose: proposal.purpose,
    client,
    ...answerParams(client ?? '', proposal.answer),
    ref: proposal.ref,
    draft: proposal.draft,
    revoke_reason: proposal.revokeReason,
    links_reason: proposal.linksReason,
  });
}

/** A `revoked://pr` link proposing a request from a template. */
export function proposeRequest(proposal: { template: string; label?: string; days?: number; from?: string; client?: string; ref?: string }): string {
  maxLength('template', proposal.template, 80);
  maxLength('label', proposal.label, 120);
  maxLength('ref', proposal.ref, 80);
  if (proposal.ref && !proposal.client) invalid('`ref` needs `client`.');
  return build('pr', {
    template: proposal.template,
    label: proposal.label,
    days: proposal.days,
    from: proposal.from,
    client: proposal.client === undefined ? undefined : clientOrigin(proposal.client),
    ref: proposal.ref,
  });
}

/** A `revoked://attest` link proposing an attestation about an identity. */
export function proposeAttestation(proposal: { type: string; for: string; claims?: string[]; name?: string; client?: string; ref?: string }): string {
  if (proposal.ref && !proposal.client) invalid('`ref` needs `client`.');
  return build('attest', {
    type: proposal.type,
    for: proposal.for,
    claims: proposal.claims?.join(','),
    name: proposal.name,
    client: proposal.client === undefined ? undefined : clientOrigin(proposal.client),
    ref: proposal.ref,
  });
}

/** A `revoked://check` link proposing an attestation check. */
export function proposeCheck(proposal: { type?: string; issuers?: string[]; claims?: string[]; from?: string; client?: string; ref?: string }): string {
  if ((proposal.issuers?.length ?? 0) > 20) invalid('A check names up to 20 issuers.');
  if ((proposal.claims?.length ?? 0) > 50) invalid('A check names up to 50 claims.');
  if (proposal.ref && !proposal.client) invalid('`ref` needs `client`.');
  return build('check', {
    type: proposal.type,
    issuers: proposal.issuers?.join(','),
    claims: proposal.claims?.join(','),
    from: proposal.from,
    client: proposal.client === undefined ? undefined : clientOrigin(proposal.client),
    ref: proposal.ref,
  });
}

export interface ConnectAnswer {
  state: string;
  status: 'connected' | 'created' | 'declined' | (string & {});
  /** The owner's server origin; the one trustworthy source for it. */
  server: string;
  code?: string;
  link?: string;
  /** The full share address of an explicitly handed-over encrypted link, from the fragment. */
  revokedLink?: string;
}

/** Reads the app's answer from the return address. Throws when `state` differs from the one sent. */
export function readAnswer(url: string | URL, expectedState: string): ConnectAnswer {
  const u = new URL(String(url));
  const q = u.searchParams;
  const state = q.get('state') ?? '';
  if (state !== expectedState) {
    throw new RevokedError({ status: 0, code: 'connect_state_mismatch', message: 'The answer is not for this page.' });
  }
  const server = q.get('server') ?? '';
  const fragment = new URLSearchParams(u.hash.slice(1));
  return {
    state,
    status: q.get('status') ?? '',
    server: server ? new URL(server).origin : '',
    ...(q.get('code') ? { code: q.get('code')! } : {}),
    ...(q.get('link') ? { link: q.get('link')! } : {}),
    ...(fragment.get('revoked_link') ? { revokedLink: fragment.get('revoked_link')! } : {}),
  };
}

export interface ConnectionToken {
  token: string;
  connection: { id: string; clientName: string; expiresAt: string; allowRevoke?: boolean; allowHandOver?: boolean };
}

export interface ExchangeOptions {
  /** The owner's server origin, from the answer's `server`. */
  server: string;
  verifier: string;
  redirectUri: string;
  fetch?: typeof fetch;
  signal?: AbortSignal;
}

/** Trades the one-time code from the return address for a connection token. A code is spent on first use. */
export async function exchangeCode(options: ExchangeOptions & { code: string }): Promise<ConnectionToken> {
  const transport = new Transport({ server: options.server, retry: { max: 0 }, ...(options.fetch ? { fetch: options.fetch } : {}) });
  return transport.request<ConnectionToken>('api/connect/token', {
    method: 'POST',
    body: { code: options.code, verifier: options.verifier, redirectUri: options.redirectUri },
    signal: options.signal,
  });
}

/**
 * Asks for a polled answer until the owner decides, at most five minutes.
 * Works only from a page on the tool's own origin: the server checks `Origin`.
 */
export async function pollForToken(options: ExchangeOptions & { intervalMs?: number; timeoutMs?: number }): Promise<ConnectionToken> {
  const transport = new Transport({ server: options.server, retry: { max: 0 }, ...(options.fetch ? { fetch: options.fetch } : {}) });
  const deadline = Date.now() + (options.timeoutMs ?? 5 * 60_000);
  const interval = options.intervalMs ?? 2_000;
  for (;;) {
    const res = await transport.raw<ConnectionToken | { pending: true }>('api/connect/token', {
      method: 'POST',
      body: { verifier: options.verifier, redirectUri: options.redirectUri },
      signal: options.signal,
      acceptStatus: [202],
      idempotent: true,
    });
    if (res.status !== 202 && 'token' in res.data) return res.data;
    if (Date.now() + interval > deadline) {
      throw new RevokedError({ status: 0, code: 'connect_timeout', message: 'The owner did not answer in time.' });
    }
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(resolve, interval);
      options.signal?.addEventListener(
        'abort',
        () => {
          clearTimeout(timer);
          reject(options.signal?.reason);
        },
        { once: true },
      );
    });
  }
}
