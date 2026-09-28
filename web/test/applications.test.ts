import { describe, expect, it } from 'vitest';
import {
  addressOf,
  applicationBody,
  applicationUpdate,
  cleanAddress,
  extendedExpiry,
  landlordUrl,
  maxAddress,
  stampText,
} from '../src/lib/application-spec';

const now = new Date('2026-09-28T10:00:00Z');

describe('applicationBody', () => {
  const body = applicationBody({
    address: '  Musterstr. 5\n10115 Berlin ',
    recordIds: ['r1', 'r2'],
    expiryDays: 14,
    identityId: 'id1',
    user: 'u1',
    workspace: 'w1',
    slug: 'abcdefghijklmnopqrst',
    now,
  });

  it('is always a watermarked application', () => {
    expect(body).toMatchObject({ purpose: 'application', watermark: true, status: 'active', requireHandshake: false });
  });

  it('stamps the address', () => {
    expect(body.watermarkText).toBe('Nur für Wohnungsbewerbung Musterstr. 5 10115 Berlin');
    expect(body.label).toBe('Musterstr. 5 10115 Berlin');
  });

  it('expires after the chosen days', () => {
    expect(body.expiresAt).toBe('2026-10-12T10:00:00.000Z');
  });

  it('grants exactly the selected records and signs when asked', () => {
    expect(body).toMatchObject({ records: ['r1', 'r2'], sections: [], identity: 'id1', user: 'u1', workspace: 'w1' });
  });

  it('leaves identity out when unsigned', () => {
    const unsigned = applicationBody({ ...{ address: 'a', recordIds: [], expiryDays: 7, user: 'u', workspace: 'w', slug: 's', now } });
    expect(unsigned).not.toHaveProperty('identity');
  });
});

describe('stamp', () => {
  it('fits the 120-character single-line column', () => {
    const s = stampText('x'.repeat(500));
    expect(s.length).toBe(120);
    expect(cleanAddress('a\tb\r\nc')).toBe('a b c');
    expect(maxAddress).toBeGreaterThan(80);
  });
});

describe('addressOf', () => {
  it('drops the prefix older labels carry', () => {
    expect(addressOf({ label: 'Wohnungsbewerbung Musterstr. 5' })).toBe('Musterstr. 5');
    expect(addressOf({ label: 'Musterstr. 5' })).toBe('Musterstr. 5');
  });
});

describe('extendedExpiry', () => {
  it('extends from the current expiry when it is still ahead', () => {
    expect(extendedExpiry('2026-10-01 10:00:00.000Z', now)).toBe('2026-10-15T10:00:00.000Z');
  });

  it('extends from now once expired', () => {
    expect(extendedExpiry('2026-09-01 10:00:00.000Z', now)).toBe('2026-10-12T10:00:00.000Z');
    expect(extendedExpiry('', now)).toBe('2026-10-12T10:00:00.000Z');
  });
});

describe('landlordUrl', () => {
  it('uses the advertised public domain', () => {
    expect(landlordUrl('revoked.link', 'https://api.example', 'abc')).toEqual({
      url: 'https://revoked.link/s/abc',
      reachable: true,
    });
  });

  it('falls back to the API base, flagged unreachable, for a local server', () => {
    for (const d of ['localhost', '127.0.0.1', 'nas.local', 'box', 'localhost:3000']) {
      expect(landlordUrl(d, 'http://localhost:5173/', 'abc')).toEqual({
        url: 'http://localhost:5173/s/abc',
        reachable: false,
      });
    }
  });
});

describe('applicationUpdate', () => {
  const base = { address: ' Lindenallee 12 ', recordIds: ['a'], identityId: 'id1', status: 'active' as const, now };

  it('restamps with the new address and keeps the expiry by default', () => {
    const body = applicationUpdate({ ...base, expiryDays: 0 });
    expect(body).toEqual({
      label: 'Lindenallee 12',
      watermarkText: 'Nur für Wohnungsbewerbung Lindenallee 12',
      records: ['a'],
      identity: 'id1',
    });
    expect(body).not.toHaveProperty('watermark');
    expect(body).not.toHaveProperty('purpose');
  });

  it('sets a new expiry and revives an expired application', () => {
    expect(applicationUpdate({ ...base, expiryDays: 7, status: 'expired' })).toMatchObject({
      expiresAt: '2026-10-05T10:00:00.000Z',
      status: 'active',
    });
    expect(applicationUpdate({ ...base, expiryDays: 7 })).not.toHaveProperty('status');
  });

  it('clears the signature when unsigned', () => {
    expect(applicationUpdate({ ...base, identityId: undefined, expiryDays: 0 }).identity).toBe('');
  });
});
