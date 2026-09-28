import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { customPrefix, documentSlots, isProfileRecord, keyForLabel, profileFields } from '../src/lib/tenant';
import { randomSlug } from '../src/lib/slug';

interface TemplateRecord {
  key: string;
  type: string;
}

const template = JSON.parse(
  readFileSync(fileURLToPath(new URL('../../templates/tenant_application.json', import.meta.url)), 'utf8'),
) as { schema: { records: TemplateRecord[]; sections: { records: TemplateRecord[] }[] } };

const templateFields = new Map(
  [...template.schema.records, ...template.schema.sections.flatMap((s) => s.records)].map((r) => [r.key, r.type]),
);

describe('tenant keys', () => {
  it('match the built-in template, so a landlord request finds the same records', () => {
    for (const f of profileFields) expect(templateFields.get(f.key), f.key).toBe(f.type);
    for (const d of documentSlots) expect(templateFields.get(d.key), d.key).toBe('file');
  });
});

describe('keyForLabel', () => {
  it('derives a valid record key and avoids taken ones', () => {
    expect(keyForLabel('Gehaltsabrechnung März', new Set())).toBe('gehaltsabrechnung_marz');
    expect(keyForLabel('Straße', new Set())).toBe('strasse');
    expect(keyForLabel('Payslip', new Set(['payslip', 'payslip_2']))).toBe('payslip_3');
    expect(keyForLabel('!!!', new Set())).toBe('document');
  });

  it('prefixes own profile fields, so only they join an application', () => {
    const key = keyForLabel('Aktuelle Miete', new Set(), customPrefix);
    expect(key).toBe('profile_aktuelle_miete');
    expect(isProfileRecord(key)).toBe(true);
    expect(isProfileRecord('full_name')).toBe(true);
    expect(isProfileRecord('bank_password')).toBe(false);
  });
});

describe('randomSlug', () => {
  it('is long and drawn from the slug alphabet', () => {
    const s = randomSlug();
    expect(s).toMatch(/^[a-z0-9]{20}$/);
    expect(new Set(Array.from({ length: 50 }, () => randomSlug())).size).toBe(50);
  });
});
