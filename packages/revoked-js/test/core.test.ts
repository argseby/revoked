import { describe, expect, it } from 'vitest';
import {
  AuthenticationError,
  GoneError,
  NetworkError,
  RateLimitedError,
  Revoked,
  RevokedError,
  ServerError,
  ValidationError,
  and,
  f,
} from '../src/index.js';
import { decodeError } from '../src/core/errors.js';
import { Transport } from '../src/core/transport.js';
import { SERVER, json, mockFetch, sessionToken } from './helpers.js';

describe('decodeError', () => {
  it('reads the app envelope', () => {
    const e = decodeError(410, { code: 'link_revoked', message: 'This link has been revoked.', status: 410 });
    expect(e).toBeInstanceOf(GoneError);
    expect(e.code).toBe('link_revoked');
    expect(e.message).toBe('This link has been revoked.');
  });

  it('reads PocketBase field errors and names each field instead of the generic message', () => {
    const e = decodeError(400, {
      status: 400,
      message: 'Failed to create record.',
      data: { watermark: { code: 'application_needs_watermark', message: 'An application must be watermarked.' } },
    });
    expect(e).toBeInstanceOf(ValidationError);
    expect(e.code).toBe('application_needs_watermark');
    expect(e.message).toBe('watermark: An application must be watermarked.');
    expect(e.fields.watermark?.code).toBe('application_needs_watermark');
  });

  it('reads the OAuth envelope', () => {
    const e = decodeError(400, { error: 'invalid_grant', error_description: 'The code was used.' });
    expect(e.code).toBe('invalid_grant');
    expect(e.message).toBe('The code was used.');
  });

  it('falls back to the status when nothing names a code', () => {
    const e = decodeError(502, 'Bad Gateway', 'Bad Gateway');
    expect(e).toBeInstanceOf(ServerError);
    expect(e.code).toBe('http_502');
  });

  it('carries Retry-After on a 429', () => {
    const e = decodeError(429, { code: 'rate_limited', message: 'Too many requests.', status: 429 }, '', '60');
    expect(e).toBeInstanceOf(RateLimitedError);
    expect((e as RateLimitedError).retryAfter).toBe(60);
  });
});

describe('Transport', () => {
  it('sends each credential only in its own header', async () => {
    for (const [credential, header, value] of [
      [{ apiKey: 'k' }, 'X-API-Key', 'k'],
      [{ connection: 'c' }, 'X-Revoked-Connection', 'c'],
      [{ session: 's' }, 'Authorization', 'Bearer s'],
    ] as const) {
      const { fetch, calls } = mockFetch(() => json({}));
      await new Transport({ server: SERVER, credential, fetch }).request('api/x');
      const headers = calls[0]!.headers;
      expect(headers.get(header)).toBe(value);
      for (const other of ['X-API-Key', 'X-Revoked-Connection', 'Authorization']) {
        if (other !== header) expect(headers.get(other)).toBeNull();
      }
    }
  });

  it('leaves the credential off an anonymous request', async () => {
    const { fetch, calls } = mockFetch(() => json({}));
    await new Transport({ server: SERVER, credential: { apiKey: 'k' }, fetch }).request('api/x', { anonymous: true });
    expect(calls[0]!.headers.get('X-API-Key')).toBeNull();
  });

  it('keeps a path prefix of the server address', async () => {
    const { fetch, calls } = mockFetch(() => json({}));
    await new Transport({ server: 'https://example.com/revoked', fetch }).request('api/server');
    expect(calls[0]!.url.toString()).toBe('https://example.com/revoked/api/server');
  });

  it('retries a GET after a 503 but never a POST', async () => {
    const get = mockFetch(() => json({}, 503), () => json({ ok: true }));
    await expect(new Transport({ server: SERVER, fetch: get.fetch }).request('api/x')).resolves.toEqual({ ok: true });
    expect(get.calls).toHaveLength(2);

    const post = mockFetch(() => json({}, 503));
    await expect(
      new Transport({ server: SERVER, fetch: post.fetch }).request('api/x', { method: 'POST' }),
    ).rejects.toBeInstanceOf(ServerError);
    expect(post.calls).toHaveLength(1);
  });

  it('does not sit out a long Retry-After', async () => {
    const { fetch, calls } = mockFetch(() => json({ code: 'rate_limited', message: 'Slow down.', status: 429 }, 429, { 'Retry-After': '60' }));
    await expect(new Transport({ server: SERVER, fetch }).request('api/x')).rejects.toBeInstanceOf(RateLimitedError);
    expect(calls).toHaveLength(1);
  });

  it('turns a failed fetch into a NetworkError', async () => {
    const fetch = (async () => {
      throw new TypeError('fetch failed');
    }) as typeof globalThis.fetch;
    const error: unknown = await new Transport({ server: SERVER, fetch, retry: { max: 0 } }).request('api/x').catch((e: unknown) => e);
    expect(error).toBeInstanceOf(NetworkError);
    expect((error as NetworkError).status).toBe(0);
  });

  it('refreshes an expired session once and repeats the request', async () => {
    const refreshed: string[] = [];
    const { fetch, calls } = mockFetch(
      () => json({ code: 'not_authenticated', message: 'x', status: 401 }, 401),
      () => json({ token: 'new-token' }),
      () => json({ ok: true }),
    );
    const t = new Transport({
      server: SERVER,
      fetch,
      credential: { session: 'old', onSessionRefresh: (token) => void refreshed.push(token) },
    });
    await expect(t.request('api/x')).resolves.toEqual({ ok: true });
    expect(calls[1]!.url.pathname).toBe('/api/collections/users/auth-refresh');
    expect(calls[2]!.headers.get('Authorization')).toBe('Bearer new-token');
    expect(refreshed).toEqual(['new-token']);
    expect(t.sessionToken).toBe('new-token');
  });

  it('gives up when the refresh is refused', async () => {
    const { fetch, calls } = mockFetch(
      () => json({ code: 'not_authenticated', message: 'x', status: 401 }, 401),
      () => json({ message: 'no' }, 401),
    );
    await expect(new Transport({ server: SERVER, fetch, credential: { session: 'old' } }).request('api/x')).rejects.toBeInstanceOf(
      AuthenticationError,
    );
    expect(calls).toHaveLength(2);
  });

  it('refuses a non-http server address', () => {
    expect(() => new Transport({ server: 'ftp://x' })).toThrow(TypeError);
  });
});

describe('client options', () => {
  it('refuses a credential that is named but empty', () => {
    expect(() => new Revoked({ server: SERVER, apiKey: undefined })).toThrow('`apiKey` is empty');
    expect(() => new Revoked({ server: SERVER, apiKey: '  ' })).toThrow(TypeError);
    expect(() => new Revoked({ server: SERVER, session: '' })).toThrow('`session` is empty');
    expect(() => new Revoked({ server: SERVER })).not.toThrow();
  });
});

describe('filters', () => {
  it('escapes quotes and backslashes so a value cannot end its literal', () => {
    expect(f`key = ${"a' || user != '"}`.expression).toBe("key = 'a\\' || user != \\''");
    expect(f`key = ${'trailing\\'}`.expression).toBe("key = 'trailing\\\\'");
  });

  it('renders numbers, booleans, null and dates', () => {
    const d = new Date('2026-11-13T10:00:00.000Z');
    expect(f`a = ${1} && b = ${true} && c = ${null} && d > ${d}`.expression).toBe(
      "a = 1 && b = true && c = null && d > '2026-11-13 10:00:00.000Z'",
    );
  });

  it('parenthesizes joined filters so an OR cannot widen the rest', () => {
    expect(and(f`a = 1 || b = 2`, f`c = 3`)?.expression).toBe('(a = 1 || b = 2) && (c = 3)');
  });
});

describe('collections', () => {
  it('binds a session write to the active workspace and the signed-in user', async () => {
    const { fetch, calls } = mockFetch(
      () => json({ id: 'u1', activeWorkspace: 'w1', activeRole: 'admin' }),
      () => json({ id: 'l1', slug: 'abc' }),
    );
    const revoked = new Revoked({ server: SERVER, session: sessionToken('u1'), fetch });
    await revoked.links.create({ label: 'Address', slug: 'fixed-slug', records: ['r1'], expiresAt: new Date('2027-01-01T00:00:00Z') });
    expect(calls[0]!.url.pathname).toBe('/api/collections/users/records/u1');
    expect(calls[1]!.body).toEqual({
      label: 'Address',
      slug: 'fixed-slug',
      records: ['r1'],
      expiresAt: '2027-01-01T00:00:00.000Z',
      workspace: 'w1',
      user: 'u1',
    });
  });

  it('asks an API key which workspace it belongs to, once', async () => {
    const { fetch, calls } = mockFetch(
      () => json({ kind: 'apiKey', id: 'k1', user: 'u1', workspace: 'w9' }),
      () => json({ id: 'l1' }),
      () => json({ id: 'l2' }),
    );
    const revoked = new Revoked({ server: SERVER, apiKey: 'key', fetch });
    await revoked.links.create({ label: 'a' });
    await revoked.links.create({ label: 'b' });
    expect(calls.map((c) => c.url.pathname)).toEqual([
      '/api/me',
      '/api/collections/links/records',
      '/api/collections/links/records',
    ]);
    expect(calls[2]!.body).toMatchObject({ workspace: 'w9' });
    expect((calls[2]!.body as { slug: string }).slug).toMatch(/^[a-z0-9]{24}$/);
    expect(calls[2]!.body).not.toHaveProperty('user');
  });

  it('uses a workspace given to the client without asking', async () => {
    const { fetch, calls } = mockFetch(() => json({ id: 'r1' }));
    const revoked = new Revoked({ server: SERVER, apiKey: 'key', workspace: 'w2', fetch });
    await revoked.records.create({ key: 'email', label: 'Email', value: 'a@b.c' });
    expect(calls).toHaveLength(1);
    expect(calls[0]!.body).toMatchObject({ workspace: 'w2', type: 'text', format: 'default' });
  });

  it('pages through a list and passes the filter expression', async () => {
    const { fetch, calls } = mockFetch(
      () => json({ page: 1, perPage: 2, totalItems: 3, totalPages: 2, items: [{ id: 'a' }, { id: 'b' }] }),
      () => json({ page: 2, perPage: 2, totalItems: 3, totalPages: 2, items: [{ id: 'c' }] }),
    );
    const revoked = new Revoked({ server: SERVER, apiKey: 'key', fetch });
    const ids: string[] = [];
    for await (const link of revoked.links.iterate({ perPage: 2, filter: f`status = ${'active'}` })) ids.push(link.id);
    expect(ids).toEqual(['a', 'b', 'c']);
    expect(calls[0]!.url.searchParams.get('filter')).toBe("status = 'active'");
    expect(calls[1]!.url.searchParams.get('page')).toBe('2');
  });

  it('uploads a file as multipart', async () => {
    const { fetch, calls } = mockFetch(() => json({ id: 'r1' }));
    const revoked = new Revoked({ server: SERVER, connection: 'tok', fetch });
    await revoked.vault.create({ key: 'contract', file: new Uint8Array([1, 2, 3]), filename: 'contract.pdf', section: 's1' });
    const form = calls[0]!.rawBody as FormData;
    expect(form).toBeInstanceOf(FormData);
    expect(form.get('key')).toBe('contract');
    expect((form.get('file') as File).name).toBe('contract.pdf');
    expect(calls[0]!.headers.get('X-Revoked-Connection')).toBe('tok');
  });

  it('returns a key that is shown once together with its record', async () => {
    const { fetch } = mockFetch(() => json({ id: 'k1', label: 'CI' }, 200, { 'X-Plain-Token': 'secret-token' }));
    const revoked = new Revoked({ server: SERVER, session: sessionToken('u1'), workspace: 'w1', fetch });
    const created = await revoked.apiKeys.create({ label: 'CI', permissions: ['shares:manage'] });
    expect(created.token).toBe('secret-token');
    expect(created.key.id).toBe('k1');
  });

  it('refuses when a token the server sends once is missing', async () => {
    const { fetch } = mockFetch(() => json({ id: 'i1' }));
    const revoked = new Revoked({ server: SERVER, session: sessionToken('u1'), workspace: 'w1', fetch });
    await expect(revoked.invites.createWithToken({ label: 'x' })).rejects.toBeInstanceOf(RevokedError);
  });

  it('builds share and request addresses', () => {
    const revoked = new Revoked({ server: SERVER });
    expect(revoked.links.url({ slug: 'a b' })).toBe('https://id.example.com/s/a%20b');
    expect(revoked.links.appLink({ slug: 'abc' })).toBe('revoked://s/https%3A%2F%2Fid.example.com/abc');
    expect(revoked.requests.appLink({ slug: 'xyz' })).toBe('revoked://r/https%3A%2F%2Fid.example.com/xyz');
  });
});
