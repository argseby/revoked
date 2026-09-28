// The applicant file, keyed by the built-in "Tenant application" template
// (templates/tenant_application.json). Keeping the same keys means a landlord
// who sends a revoked request gets the same records, and the landlord page
// lays them out as an applicant card. Labels live in the locale catalogues.

export type FieldType = 'text' | 'number' | 'datetime';

export interface ProfileField {
  key: string;
  type: FieldType;
}

export interface DocumentSlot {
  key: string;
  redact?: boolean;
}

export const profileFields: ProfileField[] = [
  { key: 'full_name', type: 'text' },
  { key: 'email', type: 'text' },
  { key: 'phone', type: 'text' },
  { key: 'current_address', type: 'text' },
  { key: 'employer', type: 'text' },
  { key: 'occupation', type: 'text' },
  { key: 'net_income', type: 'number' },
  { key: 'move_in_date', type: 'datetime' },
  { key: 'household_size', type: 'number' },
  { key: 'pets', type: 'text' },
];

export const documentSlots: DocumentSlot[] = [
  { key: 'id_document', redact: true },
  { key: 'proof_of_income' },
  { key: 'credit_report' },
  { key: 'rent_debt_certificate' },
];

export const tenantKeys = new Set([...profileFields.map((f) => f.key), ...documentSlots.map((d) => d.key)]);

// The vault section new records are filed under. The name is the product's,
// so it reads the same in every language.
export const sectionKey = 'mietunterlagen';
export const sectionName = 'Mietunterlagen';

// Fields the applicant adds on "About you" carry this prefix. It is what marks
// a vault record as part of the application: without it, an unrelated record
// (a password kept in the same vault) would be offered to landlords.
export const customPrefix = 'profile_';

export function isProfileRecord(key: string): boolean {
  return tenantKeys.has(key) || key.startsWith(customPrefix);
}

const keyPattern = /^[a-z0-9_-]+$/;

// Extra documents and fields get a key derived from their label, suffixed
// until it is free, so "Payslip August" and a second "Payslip August" both fit.
export function keyForLabel(label: string, taken: ReadonlySet<string>, prefix = ''): string {
  const base =
    prefix +
    (label
      .toLowerCase()
      .normalize('NFKD')
      .replace(/[̀-ͯ]/g, '')
      .replace(/ß/g, 'ss')
      .replace(/[^a-z0-9]+/g, '_')
      .replace(/^_+|_+$/g, '')
      .slice(0, 40) || 'document');
  let key = base;
  for (let n = 2; taken.has(key); n++) key = `${base}_${n}`;
  if (!keyPattern.test(key)) throw new Error(`invalid key ${key}`);
  return key;
}
