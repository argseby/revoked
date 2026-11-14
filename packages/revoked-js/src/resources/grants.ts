import type { ClientContext } from '../core/context.js';
import { RevokedError } from '../core/errors.js';
import type { CallOptions } from '../core/transport.js';

/** A grant a service received, e.g. in the `revoked_links` userinfo claim after a sign-in. */
export interface GrantRef {
  id: string;
  token: string;
}

export type GrantStatus = 'active' | 'paused' | 'revoked' | 'expired' | 'not_found' | (string & {});

export interface GrantValue {
  id: string;
  status: GrantStatus;
  /** Current values while the grant is active. */
  values?: Record<string, unknown>;
  etag?: string;
  /** Seconds the answer may be reused without asking again. */
  maxAge?: number;
}

interface ResolvedItem extends GrantValue {
  notModified?: boolean;
}

/** Where `grants.resolve` keeps answers between calls. A `Map` works. */
export interface GrantCache {
  get(id: string): { value: GrantValue; expiresAt: number } | undefined;
  set(id: string, entry: { value: GrantValue; expiresAt: number }): void;
  delete(id: string): void;
}

const MAX_BATCH = 100;

export class Grants {
  private readonly cache: GrantCache;

  constructor(
    private readonly ctx: ClientContext,
    cache?: GrantCache,
  ) {
    this.cache = cache ?? new Map();
  }

  /**
   * The current values behind grants this server issued. Answers inside their
   * `maxAge` come from the cache; older ones are asked again with their ETag,
   * so an unchanged grant costs no values on the wire. A revoked grant stops
   * answering at once.
   */
  async resolve(grants: GrantRef[], options: CallOptions & { now?: () => number } = {}): Promise<GrantValue[]> {
    const now = options.now ?? Date.now;
    const results = new Map<string, GrantValue>();
    const stale: (GrantRef & { etag?: string })[] = [];
    for (const grant of grants) {
      const cached = this.cache.get(grant.id);
      if (cached && cached.expiresAt > now()) results.set(grant.id, cached.value);
      else stale.push(cached?.value.etag ? { ...grant, etag: cached.value.etag } : grant);
    }

    for (let i = 0; i < stale.length; i += MAX_BATCH) {
      const batch = stale.slice(i, i + MAX_BATCH);
      const res = await this.ctx.transport.request<{ items: ResolvedItem[] }>('api/grants/resolve', {
        method: 'POST',
        body: { grants: batch },
        anonymous: true,
        idempotent: true,
        signal: options.signal,
      });
      for (const item of res.items) {
        let value: GrantValue = item;
        if (item.notModified) {
          const previous = this.cache.get(item.id)?.value;
          if (!previous) {
            throw new RevokedError({ status: 0, code: 'grant_cache_miss', message: 'The server answered not modified for an uncached grant.' });
          }
          value = { ...previous, status: item.status, ...(item.etag ? { etag: item.etag } : {}), ...(item.maxAge === undefined ? {} : { maxAge: item.maxAge }) };
        }
        const { notModified: _, ...clean } = value as ResolvedItem;
        if (clean.status === 'active') this.cache.set(item.id, { value: clean, expiresAt: now() + (clean.maxAge ?? 0) * 1000 });
        else this.cache.delete(item.id);
        results.set(item.id, clean);
      }
    }

    return grants.map((g) => results.get(g.id) ?? { id: g.id, status: 'not_found' });
  }

  /** Drops cached answers, e.g. after a `grant.revoked` event. */
  forget(id: string): void {
    this.cache.delete(id);
  }
}
