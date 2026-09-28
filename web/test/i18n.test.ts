import { describe, expect, it } from 'vitest';
import { labelFromFilename, redactedName, stem } from '../src/lib/filename';
import { de } from '../src/lib/locales/de';
import { en } from '../src/lib/locales/en';
import { documentSlots, profileFields } from '../src/lib/tenant';

describe('catalogues', () => {
  it('translate exactly the same keys', () => {
    expect(Object.keys(de).sort()).toEqual(Object.keys(en).sort());
  });

  it('name every template field and slot in both languages', () => {
    for (const cat of [en, de] as Record<string, unknown>[]) {
      for (const f of profileFields) expect(cat[`field.${f.key}`], f.key).toBeTruthy();
      for (const s of documentSlots) {
        expect(cat[`slot.${s.key}`], s.key).toBeTruthy();
        expect(cat[`slot.${s.key}.hint`], s.key).toBeTruthy();
      }
    }
  });

  it('render parameters in both languages', () => {
    for (const [key, m] of Object.entries(en)) {
      const d = (de as Record<string, typeof m>)[key];
      if (typeof m !== 'function') {
        expect(typeof d, key).toBe('string');
        continue;
      }
      const params = { n: 2, total: 3, email: 'a@b', server: 's', host: 'h', address: 'A', label: 'L', name: 'N', names: 'X', url: 'u', date: 'd' };
      for (const out of [m(params), (d as typeof m)(params)]) {
        expect(out, key).not.toMatch(/undefined|\$\{/);
      }
    }
  });
});

describe('file names', () => {
  it('derive labels and redacted names', () => {
    expect(stem('scan.final.pdf')).toBe('scan.final');
    expect(labelFromFilename('gehaltsabrechnung_08-2026.pdf')).toBe('Gehaltsabrechnung 08-2026');
    expect(redactedName('ausweis.jpg', 'image/png')).toBe('ausweis-redacted.png');
    expect(redactedName('lohn.pdf', 'application/pdf')).toBe('lohn-redacted.pdf');
  });
});

describe('isRedacted', () => {
  it('recognises what the redactor produces, and nothing else', async () => {
    const { isRedacted } = await import('../src/lib/filename');
    expect(isRedacted('ausweis-redacted.png')).toBe(true);
    expect(isRedacted('lohn-redacted.PDF')).toBe(true);
    expect(isRedacted('ausweis.png')).toBe(false);
    expect(isRedacted('redacted-notes.png')).toBe(false);
    expect(isRedacted(undefined)).toBe(false);
  });
});
