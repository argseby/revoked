import { t } from './i18n.svelte';
import type { MessageKey } from './locales/en';
import { customPrefix, keyForLabel, profileFields, type FieldType } from './tenant';
import { applications } from './applications.svelte';
import { vault, type VaultRecord } from './vault.svelte';

export type CustomType = FieldType | 'file';

export interface EditableField {
  key: string;
  label: string;
  type: FieldType;
  custom: boolean;
}

// The applicant card's fields — the template's and the applicant's own —
// edited as one form and saved as one vault record per key, so a revoked
// request for the tenant template finds them too.
class Profile {
  // Number inputs bind numbers (or null when empty), so read through `text`.
  values = $state<Record<string, string | number | null>>(
    Object.fromEntries(profileFields.map((f) => [f.key, ''])),
  );
  // Custom fields added in this session that have no value, hence no record, yet.
  pending = $state<EditableField[]>([]);
  saving = $state(false);
  error = $state<string | null>(null);

  // Adding a field
  dialogOpen = $state(false);
  newLabel = $state('');
  newType = $state<CustomType>('text');

  customRecords = $derived(vault.records.filter((r) => r.key.startsWith(customPrefix)));
  customFiles = $derived(this.customRecords.filter((r) => r.type === 'file'));

  custom = $derived<EditableField[]>([
    ...this.customRecords
      .filter((r) => r.type !== 'file')
      .map((r) => ({ key: r.key, label: r.label || r.key, type: asFieldType(r.type), custom: true })),
    ...this.pending.filter((p) => !vault.byKey.has(p.key)),
  ]);

  standard = $derived<EditableField[]>(
    profileFields.map((f) => ({ key: f.key, label: t(`field.${f.key}` as MessageKey), type: f.type, custom: false })),
  );

  dirty = $derived([...this.standard, ...this.custom].some((f) => this.text(f.key) !== this.#stored(f.key)));

  labelTaken = $derived.by(() => {
    const l = this.newLabel.trim().toLowerCase();
    return !!l && this.customRecords.some((r) => (r.label || '').toLowerCase() === l);
  });

  text(key: string): string {
    const v = this.values[key];
    return v == null ? '' : String(v).trim();
  }

  fromVault() {
    const next: Record<string, string | number | null> = {};
    for (const f of profileFields) next[f.key] = this.#stored(f.key);
    for (const r of this.customRecords) if (r.type !== 'file') next[r.key] = r.value ?? '';
    for (const p of this.pending) next[p.key] = this.values[p.key] ?? '';
    this.values = next;
  }

  async save() {
    this.saving = true;
    this.error = null;
    const added: VaultRecord[] = [];
    for (const f of [...this.standard, ...this.custom]) {
      const res = await vault.saveField(f.key, f.label, f.type, this.text(f.key));
      if (!res.ok) {
        this.error = `${f.label}: ${vault.error}`;
        break;
      }
      if (res.added && res.record) added.push(res.record);
    }
    this.pending = this.pending.filter((p) => !vault.byKey.has(p.key));
    this.saving = false;
    if (added.length) await applications.offer(added);
  }

  openDialog() {
    this.newLabel = '';
    this.newType = 'text';
    this.dialogOpen = true;
  }

  // Returns the new field's key; a document field is created by its upload,
  // so the caller opens the upload for it.
  addField(): { key: string; label: string; type: CustomType } | null {
    const label = this.newLabel.trim();
    if (!label || this.labelTaken) return null;
    const taken = new Set([...vault.records.map((r) => r.key), ...this.pending.map((p) => p.key)]);
    const key = keyForLabel(label, taken, customPrefix);
    const type = this.newType;
    this.dialogOpen = false;
    if (type !== 'file') {
      this.pending = [...this.pending, { key, label, type, custom: true }];
      this.values[key] = '';
    }
    return { key, label, type };
  }

  async remove(f: { key: string }) {
    const record = vault.byKey.get(f.key);
    this.pending = this.pending.filter((p) => p.key !== f.key);
    delete this.values[f.key];
    if (record) await vault.remove(record);
  }

  #stored(key: string): string {
    return vault.byKey.get(key)?.value ?? '';
  }
}

function asFieldType(type: VaultRecord['type']): FieldType {
  return type === 'number' || type === 'datetime' ? type : 'text';
}

export const profile = new Profile();
