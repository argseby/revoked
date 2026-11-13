import { createHash, createHmac, createPublicKey, createVerify, generateKeyPairSync, sign as nodeSign } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { checkCode, connectLink, createPkce, proposeShare, readAnswer } from '../src/connect.js';
import { exportPublicKeyPem, generateIdentityKey, importIdentityKey, exportPrivateKeyPem, signChallenge } from '../src/identity.js';
import { Revoked } from '../src/index.js';
import { linkKeyFrom, openSealedEntry, SealedError } from '../src/sealed.js';
import { openSealedFile } from '../src/sealed/index.js';
import { fromBase64 } from '../src/core/encoding.js';
import {
  dnsPin,
  fingerprintPem,
  verifyIdentityStatus,
  verifyParentSignature,
  verifyServer,
  verifyServerAssertion,
} from '../src/trust.js';
import { verifyWebhook, WebhookVerificationError } from '../src/webhooks.js';
import { SERVER, fixture, json, mockFetch } from './helpers.js';

describe('identity keys', () => {
  it('signs a challenge as DER that an independent verifier accepts', async () => {
    const key = await generateIdentityKey();
    const pem = await exportPublicKeyPem(key);
    for (let i = 0; i < 20; i++) {
      const nonce = `nonce-${i}-${'a'.repeat(40)}`;
      const signature = await signChallenge(key, nonce);
      const ok = createVerify('SHA256').update(nonce).verify({ key: createPublicKey(pem), dsaEncoding: 'der' }, Buffer.from(signature, 'base64'));
      expect(ok).toBe(true);
    }
  });

  it('round-trips a saved key', async () => {
    const key = await generateIdentityKey({ extractable: true });
    const loaded = await importIdentityKey(await exportPrivateKeyPem(key), await exportPublicKeyPem(key));
    const signature = await signChallenge(loaded, 'abcdefabcdefabcdef');
    const ok = createVerify('SHA256')
      .update('abcdefabcdefabcdef')
      .verify({ key: createPublicKey(await exportPublicKeyPem(key)), dsaEncoding: 'der' }, Buffer.from(signature, 'base64'));
    expect(ok).toBe(true);
  });

  it('keeps a generated private key non-extractable by default', async () => {
    const key = await generateIdentityKey();
    await expect(exportPrivateKeyPem(key)).rejects.toThrow();
  });

  it('proves an identity when opening a gated share, and keeps the handshake token', async () => {
    const key = await generateIdentityKey();
    const nonce = 'f'.repeat(64);
    const { fetch, calls } = mockFetch(
      () => json({ nonce, expiresAt: '2026-11-13T00:00:00Z', algorithm: 'ECDSA-SHA256' }),
      () => json({ slug: 's1', records: [], sections: [], viewCount: 1 }, 200, { 'X-Handshake-Token': 'hs-1' }),
    );
    const revoked = new Revoked({ server: SERVER, apiKey: 'never-sent', fetch });
    const share = await revoked.public.links.open('s1', { identity: { id: 'id1', key }, password: 'pw' });
    expect(share.handshakeToken).toBe('hs-1');
    expect(calls[0]!.url.pathname).toBe('/api/challenges/link/s1');
    expect(calls[0]!.url.searchParams.get('identityId')).toBe('id1');
    const body = calls[1]!.body as Record<string, string>;
    expect(body.password).toBe('pw');
    expect(body.challengeNonce).toBe(nonce);
    const ok = createVerify('SHA256')
      .update(nonce)
      .verify({ key: createPublicKey(await exportPublicKeyPem(key)), dsaEncoding: 'der' }, Buffer.from(body.challengeSignature!, 'base64'));
    expect(ok).toBe(true);
    for (const c of calls) expect(c.headers.get('X-API-Key')).toBeNull();
  });

  it('replaces a refused handshake token with a fresh signature once', async () => {
    const key = await generateIdentityKey();
    const { fetch, calls } = mockFetch(
      () => json({ code: 'handshake_invalid', message: 'x', status: 403 }, 403),
      () => json({ nonce: 'a'.repeat(64) }),
      () => json({ slug: 's1', records: [], sections: [], viewCount: 1 }),
    );
    const revoked = new Revoked({ server: SERVER, fetch });
    await revoked.public.links.open('s1', { identity: { id: 'id1', key, handshakeToken: 'stale' } });
    expect((calls[0]!.body as Record<string, string>).handshakeToken).toBe('stale');
    expect((calls[2]!.body as Record<string, string>).challengeSignature).toBeTruthy();
  });

  it('refuses a malformed challenge before signing it', async () => {
    const key = await generateIdentityKey();
    const { fetch } = mockFetch(() => json({ nonce: 'short' }));
    const revoked = new Revoked({ server: SERVER, fetch });
    await expect(revoked.public.links.open('s1', { identity: { id: 'id1', key } })).rejects.toMatchObject({ code: 'challenge_invalid' });
  });

  it('answers a request only with a session', async () => {
    const revoked = new Revoked({ server: SERVER, apiKey: 'k', fetch: mockFetch().fetch });
    await expect(revoked.public.requests.submit('slug', { data: { a: 1 } })).rejects.toMatchObject({ code: 'request_account_required' });
  });
});

describe('webhooks', () => {
  const secret = `whsec_${'ab'.repeat(32)}`;
  const body = JSON.stringify({ id: 'e1', type: 'link.revoked', created: '2026-11-13T00:00:00Z', workspace: 'w', data: { object: 'link', id: 'l1', status: 'revoked', kind: 'share' } });
  const t = 1_800_000_000;
  const sig = (s: string, payload = body) => createHmac('sha256', s).update(`${t}.${payload}`).digest('hex');

  it('accepts a signed delivery and returns the event', async () => {
    const event = await verifyWebhook({ body, signature: `t=${t},v1=${sig(secret)}`, secret, now: t + 10 });
    expect(event.type).toBe('link.revoked');
    if (event.type === 'link.revoked') expect(event.data.kind).toBe('share');
  });

  it('accepts any v1 during a rotation', async () => {
    const old = `whsec_${'cd'.repeat(32)}`;
    await expect(
      verifyWebhook({ body, signature: `t=${t},v1=${sig(secret)},v1=${sig(old)}`, secret: old, now: t }),
    ).resolves.toBeTruthy();
  });

  it('refuses a wrong secret, an altered body and an old delivery', async () => {
    const other = `whsec_${'ef'.repeat(32)}`;
    await expect(verifyWebhook({ body, signature: `t=${t},v1=${sig(other)}`, secret, now: t })).rejects.toBeInstanceOf(WebhookVerificationError);
    await expect(verifyWebhook({ body: body + ' ', signature: `t=${t},v1=${sig(secret)}`, secret, now: t })).rejects.toMatchObject({
      code: 'webhook_signature_invalid',
    });
    await expect(verifyWebhook({ body, signature: `t=${t},v1=${sig(secret)}`, secret, now: t + 301 })).rejects.toMatchObject({
      code: 'webhook_timestamp_out_of_range',
    });
    await expect(verifyWebhook({ body, signature: null, secret, now: t })).rejects.toMatchObject({ code: 'webhook_signature_missing' });
  });
});

describe('connect', () => {
  it('derives the check code as the docs describe', async () => {
    const challenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';
    const hex = createHash('sha256').update(challenge).digest('hex').slice(0, 6).toUpperCase();
    expect(await checkCode(challenge)).toBe(`${hex.slice(0, 3)}-${hex.slice(3)}`);
  });

  it('makes a PKCE pair whose challenge is the verifier hash', async () => {
    const { verifier, challenge } = await createPkce();
    expect(challenge).toBe(createHash('sha256').update(verifier).digest('base64url'));
  });

  it('encodes a proposal with %20 and refuses bad keys', () => {
    expect(proposeShare({ label: 'Wi-Fi for guests', keys: ['network_name', 'wifi_password'], template: 'Wi-Fi access' })).toBe(
      'revoked://p?label=Wi-Fi%20for%20guests&keys=network_name%2Cwifi_password&template=Wi-Fi%20access',
    );
    expect(() => proposeShare({ label: 'x', keys: ['Bad Key'] })).toThrow(TypeError);
    expect(() => proposeShare({ label: 'x', keys: ['a'], ref: 'r' })).toThrow(TypeError);
  });

  it('refuses a vault request with a polled answer', () => {
    expect(() =>
      connectLink({ client: 'https://tool.example', answer: { poll: SERVER, challenge: 'c' }, vault: {} }),
    ).toThrow(TypeError);
    expect(connectLink({ client: 'https://tool.example', answer: { redirect: 'https://tool.example/cb', state: 's1', challenge: 'c' } })).toBe(
      'revoked://connect?client=https%3A%2F%2Ftool.example&redirect=https%3A%2F%2Ftool.example%2Fcb&state=s1&challenge=c',
    );
  });

  it('reads the answer and checks its state', () => {
    const a = readAnswer('https://tool.example/cb?state=s1&status=connected&server=https%3A%2F%2Fid.example.com%2F&code=c1#revoked_link=x', 's1');
    expect(a).toMatchObject({ status: 'connected', server: SERVER, code: 'c1', revokedLink: 'x' });
    expect(() => readAnswer('https://tool.example/cb?state=other', 's1')).toThrow();
  });
});

describe('trust', () => {
  it('verifies the frozen identity-status vectors', async () => {
    const v = fixture('identity_status.json');
    const now = v.issuedAtUnix + 10;
    const active = await verifyIdentityStatus(v.active, v.publicKeyPem, v.domain, v.fingerprint, now);
    expect(active.status).toBe('active');
    const revoked = await verifyIdentityStatus(v.revoked, v.publicKeyPem, v.domain, v.fingerprint, now);
    expect(revoked.status).toBe('revoked');
    await expect(verifyIdentityStatus(v.active, v.publicKeyPem, 'other.test', v.fingerprint, now)).rejects.toThrow();
    await expect(verifyIdentityStatus(v.active, v.publicKeyPem, v.domain, v.fingerprint, now + 7200)).rejects.toThrow('expired');
  });

  it('verifies the frozen RSA parent signature', async () => {
    const v = fixture('rsa_signature.json');
    expect(await verifyParentSignature(v.publicKeyPem, v.message, v.signatureHex)).toBe(true);
    expect(await verifyParentSignature(v.publicKeyPem, `${v.message}x`, v.signatureHex)).toBe(false);
  });

  const root = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const publicKey = root.publicKey.export({ type: 'spki', format: 'pem' }).toString();

  async function assertion(domain: string, now: number) {
    const body = { domain, publicKey, fingerprint: await fingerprintPem(publicKey), issuedAt: now - 5, expiresAt: now + 86400 };
    const signature = nodeSign('sha256', Buffer.from(JSON.stringify(body)), root.privateKey).toString('hex');
    return { body, signature };
  }

  it('walks a server chain from its DNS pin', async () => {
    const now = 1_800_000_000;
    const a = await assertion('id.example.com', now);
    const resolveTxt = async (name: string) => (name === '_revoked.id.example.com' ? [[`v=revoked1; k=sha256/${a.body.fingerprint}`]] : []);
    const { fetch } = mockFetch(() => json({ assertion: a }));
    const verdict = await verifyServer('id.example.com', { resolveTxt, fetch, now });
    expect(verdict.state).toBe('verified');
    expect(await verifyServerAssertion(a, now)).toEqual(a.body);

    const pinned = await dnsPin('id.example.com', async () => [['v=revoked1; k=sha256/', 'A'.repeat(64)]]);
    expect(pinned).toBe('a'.repeat(64));
  });

  it('calls a server that serves another key than DNS pins spoofed', async () => {
    const now = 1_800_000_000;
    const a = await assertion('id.example.com', now);
    const { fetch } = mockFetch(() => json({ assertion: a }));
    const verdict = await verifyServer('id.example.com', { resolveTxt: async () => [[`v=revoked1; k=sha256/${'0'.repeat(64)}`]], fetch, now });
    expect(verdict.state).toBe('spoofed');
    const missing = await verifyServer('id.example.com', { resolveTxt: async () => [], fetch: mockFetch().fetch, now });
    expect(missing.state).toBe('dnsMissing');
  });

  it('refuses an assertion whose body was altered', async () => {
    const now = 1_800_000_000;
    const a = await assertion('id.example.com', now);
    await expect(verifyServerAssertion({ ...a, body: { ...a.body, domain: 'evil.example' } }, now)).rejects.toThrow();
  });
});

describe('sealed shares', () => {
  it('opens the frozen link-read vector', async () => {
    const v = fixture('sealing_link_read_vectors.json');
    const opened = await openSealedEntry(v.entry, linkKeyFrom(`https://x/s/slug#k=${v.linkKey}`));
    expect(opened).toMatchObject({ value: v.content.v, label: v.content.l, type: v.content.t, format: v.content.f });
  });

  it('refuses the wrong key', async () => {
    const v = fixture('sealing_link_read_vectors.json');
    const wrong = new Uint8Array(32).fill(7);
    await expect(openSealedEntry(v.entry, wrong)).rejects.toBeInstanceOf(SealedError);
  });

  it('opens the frozen file vectors', async () => {
    const v = fixture('sealing_file_vectors.json');
    const opened = await openSealedEntry({ ...v.entry, sealed: true }, linkKeyFrom(`#k=${v.linkKey}`));
    expect(opened.file).toMatchObject({ name: v.content.x.n, mime: v.content.x.m, size: v.content.x.s });
    const bytes = await opened.file!.open(fromBase64(v.blob));
    expect(createHash('sha256').update(bytes).digest('hex')).toBe(v.plaintextSha256);

    const fileKey = fromBase64(v.content.x.k);
    const small = await openSealedFile(fromBase64(v.small.blob), fileKey, Buffer.byteLength(v.small.text), v.workspace, v.entry.id);
    expect(new TextDecoder().decode(small)).toBe(v.small.text);
  });

  it('refuses a cut blob', async () => {
    const v = fixture('sealing_file_vectors.json');
    const opened = await openSealedEntry({ ...v.entry, sealed: true }, linkKeyFrom(`#k=${v.linkKey}`));
    const blob = fromBase64(v.blob);
    await expect(opened.file!.open(blob.subarray(0, blob.length - 1))).rejects.toBeInstanceOf(SealedError);
  });
});
