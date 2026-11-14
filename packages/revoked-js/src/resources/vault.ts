import { bodyFor } from '../core/body.js';
import { Collection } from '../core/collection.js';
import type { ClientContext } from '../core/context.js';
import { path } from '../core/context.js';
import type { CallOptions } from '../core/transport.js';
import type {
  Download,
  Section,
  SectionInput,
  VaultEntry,
  VaultEntryInput,
  VaultEntryUpdate,
  VaultRecord,
  VaultRecordInput,
} from '../models.js';
import { download } from './shares.js';

/**
 * The vault as a signed-in person sees it, through the `records` collection.
 * API keys and connected tools use `vault` instead: the collection is out of
 * their reach.
 */
export class Records extends Collection<VaultRecord, VaultRecordInput> {
  constructor(ctx: ClientContext) {
    super(ctx, 'records');
  }

  override create(input: VaultRecordInput, options?: CallOptions): Promise<VaultRecord> {
    return super.create(
      { ...input, type: input.type ?? (input.file === undefined ? 'text' : 'file'), format: input.format ?? 'default' },
      options,
    );
  }

  /** Sections and records other members shared with the signed-in person. Session only. */
  shared(options: CallOptions = {}): Promise<{ sections: (Section & Record<string, unknown>)[]; records: VaultRecord[] }> {
    return this.ctx.transport.request('api/shared/vault', { signal: options.signal });
  }

  /** The bytes of a file record. */
  async file(record: Pick<VaultRecord, 'id' | 'file'>, options: CallOptions = {}): Promise<Download> {
    const { token } = await this.ctx.transport.request<{ token: string }>('api/files/token', {
      method: 'POST',
      signal: options.signal,
    });
    return download(this.ctx, path`api/files/records/${record.id}/${record.file}`, { ...options, query: { token } });
  }
}

export class Sections extends Collection<Section, SectionInput> {
  constructor(ctx: ClientContext) {
    super(ctx, 'sections');
  }
}

/**
 * The vault as an API key or connected tool reaches it: only the sections it
 * was given, and changes only to records it wrote itself.
 */
export class Vault {
  constructor(private readonly ctx: ClientContext) {}

  /** The records within reach, without values. Encrypted records are left out. */
  async list(options: CallOptions = {}): Promise<VaultEntry[]> {
    const res = await this.ctx.transport.request<{ records: VaultEntry[] }>('api/vault', { signal: options.signal });
    return res.records;
  }

  /** One record with its current value. Each read is in the owner's audit log. */
  get(id: string, options: CallOptions = {}): Promise<VaultEntry> {
    return this.ctx.transport.request(path`api/vault/${id}`, { signal: options.signal });
  }

  /** The record whose key matches, or undefined. */
  async find(key: string, options: CallOptions = {}): Promise<VaultEntry | undefined> {
    const entry = (await this.list(options)).find((e) => e.key === key);
    return entry ? this.get(entry.id, options) : undefined;
  }

  create(input: VaultEntryInput, options: CallOptions = {}): Promise<VaultEntry> {
    return this.ctx.transport.request('api/vault', {
      method: 'POST',
      ...bodyFor(input),
      signal: options.signal,
    });
  }

  update(id: string, input: VaultEntryUpdate, options: CallOptions = {}): Promise<VaultEntry> {
    return this.ctx.transport.request(path`api/vault/${id}`, {
      method: 'PATCH',
      ...bodyFor(input),
      signal: options.signal,
      idempotent: true,
    });
  }

  async delete(id: string, options: CallOptions = {}): Promise<void> {
    await this.ctx.transport.request(path`api/vault/${id}`, {
      method: 'DELETE',
      responseType: 'none',
      signal: options.signal,
    });
  }

  file(id: string, options: CallOptions = {}): Promise<Download> {
    return download(this.ctx, path`api/vault/${id}/file`, options);
  }
}
