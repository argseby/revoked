import { describeError } from './api';
import { session } from './session.svelte';
import { sectionKey, sectionName, type FieldType } from './tenant';

export interface VaultRecord {
  id: string;
  key: string;
  label: string;
  type: string;
  value: string;
  format: string;
  file?: string;
  filename?: string;
  mime?: string;
  size?: number;
  updated: string;
}

interface Section {
  id: string;
  key: string;
  records: string[];
}

interface ListResponse<T> {
  items: T[];
}

// A write that succeeded. `added` is set when the write created the record,
// which is when the open applications may want it too.
export type WriteResult = { ok: true; record: VaultRecord | null; added: boolean } | { ok: false };

const path = '/api/collections/records/records';
const sectionsPath = '/api/collections/sections/records';

export const stampableMimes = new Set(['image/png', 'image/jpeg', 'application/pdf']);

export function isStampable(r: VaultRecord): boolean {
  return r.type !== 'file' || stampableMimes.has(r.mime ?? '');
}

// New records this tool creates are filed under one vault section,
// "mietunterlagen", so they appear grouped in the app. Existing records are
// used where their key matches and are left where they are.
class Vault {
  records = $state<VaultRecord[]>([]);
  section = $state<Section | null>(null);
  loaded = $state(false);
  loading = $state(false);
  error = $state<string | null>(null);
  busyKeys = $state<Set<string>>(new Set());

  files = $derived(this.records.filter((r) => r.type === 'file'));
  byKey = $derived(new Map(this.records.map((r) => [r.key, r])));

  async load() {
    this.loading = true;
    this.error = null;
    try {
      const filter = `workspace = "${session.workspace}"`;
      const [records, sections] = await Promise.all([
        session.api.get<ListResponse<VaultRecord>>(path, { perPage: 500, sort: 'key', filter }),
        session.api.get<ListResponse<Section>>(sectionsPath, {
          perPage: 1,
          filter: `${filter} && key = "${sectionKey}"`,
        }),
      ]);
      this.records = records.items;
      this.section = sections.items[0] ?? null;
      this.loaded = true;
    } catch (e) {
      this.error = describeError(e);
    } finally {
      this.loading = false;
    }
  }

  reset() {
    this.records = [];
    this.section = null;
    this.loaded = false;
  }

  isBusy(key: string): boolean {
    return this.busyKeys.has(key);
  }

  async saveField(key: string, label: string, type: FieldType, value: string): Promise<WriteResult> {
    const existing = this.byKey.get(key);
    const trimmed = value.trim();
    if (existing?.value === trimmed || (!existing && !trimmed)) return { ok: true, record: existing ?? null, added: false };
    return this.#run(key, async () => {
      if (existing && !trimmed) {
        await session.api.delete(`${path}/${existing.id}`);
        this.#drop(existing.id);
        return { record: null, added: false };
      }
      if (existing) {
        this.#put(await session.api.patch<VaultRecord>(`${path}/${existing.id}`, { value: trimmed }));
        return { record: existing, added: false };
      }
      const record = await session.api.post<VaultRecord>(path, {
        key,
        label,
        type,
        value: trimmed,
        format: 'default',
        user: session.user?.id,
        workspace: session.workspace,
      });
      this.#put(record);
      await this.#file(record);
      return { record, added: true };
    });
  }

  // Creates the record, or replaces the file of the one already under `key` —
  // every open application then serves the new file on its next read.
  async uploadFile(key: string, label: string, file: Blob, filename: string): Promise<WriteResult> {
    const existing = this.byKey.get(key);
    return this.#run(key, async () => {
      const form = new FormData();
      form.set('filename', filename);
      form.set('file', file, filename);
      if (existing) {
        const record = await session.api.multipart<VaultRecord>('PATCH', `${path}/${existing.id}`, form);
        this.#put(record);
        return { record, added: false };
      }
      form.set('key', key);
      form.set('label', label);
      form.set('type', 'file');
      form.set('format', 'default');
      form.set('user', session.user?.id ?? '');
      form.set('workspace', session.workspace);
      const record = await session.api.multipart<VaultRecord>('POST', path, form);
      this.#put(record);
      await this.#file(record);
      return { record, added: true };
    });
  }

  async remove(r: VaultRecord): Promise<boolean> {
    const res = await this.#run(r.key, async () => {
      await session.api.delete(`${path}/${r.id}`);
      this.#drop(r.id);
      return { record: null, added: false };
    });
    return res.ok;
  }

  // The file field is protected, so the owner's own bytes need a short-lived
  // file token; a bare file URL serves nothing.
  async fetchBytes(r: VaultRecord): Promise<Blob | null> {
    const file = r.file;
    if (!file) return null;
    let blob: Blob | null = null;
    await this.#run(r.key, async () => {
      const { token } = await session.api.post<{ token: string }>('/api/files/token');
      blob = await session.api.bytes(`/api/files/records/${r.id}/${encodeURIComponent(file)}`, { token });
      return { record: null, added: false };
    });
    return blob;
  }

  // Files a new record under the section, creating the section on first use.
  // `records+` appends on the server, so a concurrent write from the app is
  // not overwritten by this tab's stale copy of the list. The record is saved
  // either way; a failure here only leaves it ungrouped, and says so.
  async #file(record: VaultRecord) {
    try {
      this.section = this.section
        ? await session.api.patch<Section>(`${sectionsPath}/${this.section.id}`, { 'records+': record.id })
        : await session.api.post<Section>(sectionsPath, {
            key: sectionKey,
            name: sectionName,
            records: [record.id],
            user: session.user?.id,
            workspace: session.workspace,
          });
    } catch (e) {
      this.error = describeError(e);
    }
  }

  async #run(
    key: string,
    fn: () => Promise<{ record: VaultRecord | null; added: boolean }>,
  ): Promise<WriteResult> {
    this.busyKeys = new Set(this.busyKeys).add(key);
    this.error = null;
    try {
      return { ok: true, ...(await fn()) };
    } catch (e) {
      this.error = describeError(e);
      return { ok: false };
    } finally {
      const next = new Set(this.busyKeys);
      next.delete(key);
      this.busyKeys = next;
    }
  }

  #put(r: VaultRecord) {
    const i = this.records.findIndex((x) => x.id === r.id);
    if (i === -1) this.records = [...this.records, r].sort((a, b) => a.key.localeCompare(b.key));
    else this.records[i] = r;
  }

  #drop(id: string) {
    this.records = this.records.filter((r) => r.id !== id);
  }
}

export const vault = new Vault();
