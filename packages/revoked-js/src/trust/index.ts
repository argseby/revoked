import { fromBase64, fromHex, fromUtf8, pemToDer, sha256, toHex, utf8 } from '../core/encoding.js';
import type { IdentityStatusAssertion, ServerInfo, Sharer } from '../models.js';

/** Resolves a DNS name to its TXT records, each as its string chunks. */
export type ResolveTxt = (name: string) => Promise<string[][]>;

export interface TrustOptions {
  /**
   * DNS lookup for the `_revoked.<domain>` pin. Required: the SDK sends no
   * name to any resolver it was not given. On Node, Bun and Deno:
   * `(name) => import('node:dns').then((dns) => dns.promises.resolveTxt(name))`.
   * In a browser, `dohResolver('https://<a resolver you trust>/dns-query')`.
   */
  resolveTxt: ResolveTxt;
  fetch?: typeof fetch;
  /** Unix seconds; for tests. */
  now?: number;
  /** Where to read `/api/server`; default `https://<domain>/`. For development servers. */
  serverUrl?: (domain: string) => string;
}

export type TrustState = 'verified' | 'dnsMissing' | 'unverified' | 'spoofed' | 'revoked';

export interface TrustVerdict {
  state: TrustState;
  domain: string;
  reason: string;
  rootFingerprint?: string;
  rootPublicKey?: string;
  identityStatus?: IdentityStatusBody;
}

export interface ServerAssertionBody {
  domain: string;
  publicKey: string;
  fingerprint: string;
  issuedAt: number;
  expiresAt: number;
}

export interface IdentityStatusBody {
  type: 'identity-status-v1';
  domain: string;
  fingerprint: string;
  /** `unknown` means the issuer has no information; it never means revoked. */
  status: 'active' | 'revoked' | 'unknown';
  reason?: string;
  revokedAt?: number;
  issuedAt: number;
  expiresAt: number;
}

export class TrustError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TrustError';
  }
}

const TXT_PIN = /v=revoked1;\s*k=sha256\/([0-9a-f]{64})/i;
const STATUS_TYPE = 'identity-status-v1';
const CLOCK_SKEW_SEC = 60;

/** Lowercase hex SHA-256 of a PEM string, as the server fingerprints keys and certificates. */
export async function fingerprintPem(pem: string): Promise<string> {
  return toHex(await sha256(pem));
}

/** A DNS-over-HTTPS lookup against a JSON-API resolver of the caller's choice. */
export function dohResolver(endpoint: string, fetchImpl: typeof fetch = globalThis.fetch): ResolveTxt {
  return async (name) => {
    const url = new URL(endpoint);
    url.searchParams.set('name', name);
    url.searchParams.set('type', 'TXT');
    const res = await fetchImpl(url, { headers: { Accept: 'application/dns-json' } });
    if (!res.ok) throw new TrustError(`The resolver answered ${res.status}.`);
    const json = (await res.json()) as { Answer?: { type: number; data: string }[] };
    return (json.Answer ?? [])
      .filter((a) => a.type === 16)
      .map((a) => [...a.data.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((m) => (m[1] ?? '').replace(/\\(.)/g, '$1')));
  };
}

/** The root fingerprint a domain pins in DNS, or undefined when it publishes none. */
export async function dnsPin(domain: string, resolveTxt: ResolveTxt): Promise<string | undefined> {
  let records: string[][];
  try {
    records = await resolveTxt(`_revoked.${domain}`);
  } catch {
    return undefined;
  }
  for (const chunks of records) {
    const match = TXT_PIN.exec(chunks.join(''));
    if (match?.[1]) return match[1].toLowerCase();
  }
  return undefined;
}

async function importRsa(pem: string): Promise<CryptoKey> {
  return crypto.subtle.importKey('spki', pemToDer(pem), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
}

async function rsaVerify(pem: string, signatureHex: string, message: Uint8Array<ArrayBuffer>): Promise<boolean> {
  let signature: Uint8Array<ArrayBuffer>;
  try {
    signature = fromHex(signatureHex);
  } catch {
    return false;
  }
  return crypto.subtle.verify('RSASSA-PKCS1-v1_5', await importRsa(pem), signature, message);
}

/** Go's `json.Marshal` escaping, which the signed bytes were produced with. */
function goJson(value: unknown): string {
  return JSON.stringify(value)
    .replace(/</g, '\\u003c')
    .replace(/>/g, '\\u003e')
    .replace(/&/g, '\\u0026')
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');
}

/**
 * Checks the signed assertion in `/api/server`: the root key signed it, it
 * is current, and its fingerprint is the key's. Says nothing about whether the
 * key belongs to the domain; that is the DNS pin's job.
 */
export async function verifyServerAssertion(
  assertion: { body: ServerAssertionBody; signature: string },
  now = Math.floor(Date.now() / 1000),
): Promise<ServerAssertionBody> {
  const b = assertion.body;
  if (!b?.domain) throw new TrustError('The assertion names no domain.');
  if (b.issuedAt > now) throw new TrustError('The assertion was issued in the future.');
  if (b.expiresAt < now) throw new TrustError('The assertion has expired.');
  if ((await fingerprintPem(b.publicKey)) !== b.fingerprint) {
    throw new TrustError('The fingerprint does not match the embedded key.');
  }
  const payload = goJson({
    domain: b.domain,
    publicKey: b.publicKey,
    fingerprint: b.fingerprint,
    issuedAt: b.issuedAt,
    expiresAt: b.expiresAt,
  });
  if (!(await rsaVerify(b.publicKey, assertion.signature, utf8(payload)))) {
    throw new TrustError('The assertion signature does not verify.');
  }
  return b;
}

/** Whether the root key signed this identity's fingerprint. */
export function verifyParentSignature(rootPublicKey: string, fingerprint: string, parentSignature: string): Promise<boolean> {
  return rsaVerify(rootPublicKey, parentSignature, utf8(fingerprint));
}

/**
 * Checks an `identity-status-v1` statement and returns what it says. The root
 * key must already be tied to `domain` through the DNS pin.
 */
export async function verifyIdentityStatus(
  assertion: IdentityStatusAssertion,
  rootPublicKey: string,
  domain: string,
  fingerprint: string,
  now = Math.floor(Date.now() / 1000),
): Promise<IdentityStatusBody> {
  const payload = fromBase64(assertion.payload);
  if (!(await rsaVerify(rootPublicKey, assertion.signature, payload))) {
    throw new TrustError('The status signature does not verify.');
  }
  const body = JSON.parse(fromUtf8(payload)) as IdentityStatusBody;
  if (body.type !== STATUS_TYPE) throw new TrustError('The statement is not an identity status.');
  if (body.domain.toLowerCase() !== domain.toLowerCase()) throw new TrustError('The statement is for another domain.');
  if (body.fingerprint.toLowerCase() !== fingerprint.toLowerCase()) throw new TrustError('The statement is about another identity.');
  if (body.issuedAt > now + CLOCK_SKEW_SEC) throw new TrustError('The statement was issued in the future.');
  if (body.expiresAt < now) throw new TrustError('The statement has expired.');
  return body;
}

async function fetchServerInfo(domain: string, options: TrustOptions): Promise<ServerInfo> {
  const base = options.serverUrl?.(domain) ?? `https://${domain}/`;
  const res = await (options.fetch ?? globalThis.fetch)(new URL('api/server', base), { redirect: 'error' });
  if (!res.ok) throw new TrustError(`https://${domain}/api/server answered ${res.status}.`);
  return (await res.json()) as ServerInfo;
}

/**
 * Walks a domain's chain: its DNS pin, its served root key and signed
 * assertion. `verified` means the key that signs for the domain is the one
 * its DNS names.
 */
export async function verifyServer(domain: string, options: TrustOptions): Promise<TrustVerdict> {
  const now = options.now ?? Math.floor(Date.now() / 1000);
  const host = domain.trim().toLowerCase();
  const pin = await dnsPin(host, options.resolveTxt);
  if (!pin) return { state: 'dnsMissing', domain: host, reason: `No _revoked.${host} TXT record was found.` };

  let info: ServerInfo;
  try {
    info = await fetchServerInfo(host, options);
  } catch (error) {
    return { state: 'unverified', domain: host, reason: error instanceof Error ? error.message : 'The server could not be reached.' };
  }

  let body: ServerAssertionBody;
  try {
    body = await verifyServerAssertion(info.assertion, now);
  } catch (error) {
    return { state: 'spoofed', domain: host, reason: (error as Error).message };
  }
  if (body.domain.toLowerCase() !== host) {
    return { state: 'spoofed', domain: host, reason: `The assertion is for ${body.domain}, not ${host}.` };
  }
  if (body.fingerprint.toLowerCase() !== pin) {
    return { state: 'spoofed', domain: host, reason: 'DNS pins a different root key than the server serves.' };
  }
  return { state: 'verified', domain: host, reason: '', rootFingerprint: pin, rootPublicKey: body.publicKey };
}

/**
 * Walks the chain for the identity behind a share or request: the issuing
 * domain's DNS pin and root key, the root's signature over the identity, and
 * the issuer's current status statement (the stapled one when present).
 */
export async function verifySharer(sharer: Sharer, options: TrustOptions): Promise<TrustVerdict> {
  const now = options.now ?? Math.floor(Date.now() / 1000);
  const domain = sharer.domainAtIssue ?? '';
  if (!domain || !sharer.fingerprint || !sharer.parentSignature) {
    return { state: 'unverified', domain, reason: 'The identity carries no claim to verify.' };
  }
  const server = await verifyServer(domain, options);
  if (server.state !== 'verified' || !server.rootPublicKey) return server;

  if (!(await verifyParentSignature(server.rootPublicKey, sharer.fingerprint, sharer.parentSignature))) {
    return { ...server, state: 'spoofed', reason: `The identity was not signed by ${domain}'s root key.` };
  }

  let statement = sharer.statusAssertion;
  if (!statement) {
    const base = options.serverUrl?.(domain) ?? `https://${domain}/`;
    try {
      const res = await (options.fetch ?? globalThis.fetch)(new URL(`api/identities/${sharer.fingerprint}/status`, base));
      if (res.ok) statement = (await res.json()) as IdentityStatusAssertion;
    } catch {
      statement = undefined;
    }
  }
  if (!statement) return { ...server, state: 'unverified', reason: 'The issuer gave no current status.' };

  let status: IdentityStatusBody;
  try {
    status = await verifyIdentityStatus(statement, server.rootPublicKey, domain, sharer.fingerprint, now);
  } catch (error) {
    return { ...server, state: 'unverified', reason: (error as Error).message };
  }
  if (status.status === 'revoked') return { ...server, state: 'revoked', reason: 'The issuer revoked this identity.', identityStatus: status };
  if (status.status !== 'active') return { ...server, state: 'unverified', reason: 'The issuer has no information on this identity.', identityStatus: status };
  return { ...server, identityStatus: status };
}
