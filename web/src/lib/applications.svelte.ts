import { ApiError, describeError } from './api';
import { confirm, toast } from './confirm.svelte';
import { t } from './i18n.svelte';
import { session } from './session.svelte';
import { recordName } from './record-name';
import { saveBlob } from './save';
import { randomSlug } from './slug';
import { isStampable, vault, type VaultRecord } from './vault.svelte';
import { isProfileRecord } from './tenant';
import {
  addressOf,
  applicationBody,
  applicationUpdate,
  cleanAddress,
  extendedExpiry,
  landlordUrl,
  type Link,
} from './application-spec';

export * from './application-spec';

export interface Identity {
  id: string;
  name: string;
  fingerprint: string;
}

interface ListResponse<T> {
  items: T[];
}

const path = '/api/collections/links/records';

class Applications {
  links = $state<Link[]>([]);
  loaded = $state(false);
  loading = $state(false);
  error = $state<string | null>(null);
  busyIds = $state<Set<string>>(new Set());

  domain = $state('');
  identity = $state<Identity | null>(null);

  // Draft for the apply sheet; `editing` is the link being edited, null for a new one.
  address = $state('');
  selected = $state<Set<string>>(new Set());
  expiryDays = $state<number>(14);
  signed = $state(true);
  editing = $state<Link | null>(null);
  submitting = $state(false);
  draftError = $state<string | null>(null);

  live = $derived(this.links.filter((l) => l.status === 'active' || l.status === 'paused'));

  canSubmit = $derived(cleanAddress(this.address).length > 0 && this.selected.size > 0 && !this.submitting);
  unstampable = $derived(vault.records.filter((r) => this.selected.has(r.id) && !isStampable(r)));

  async load() {
    this.loading = true;
    this.error = null;
    try {
      const [links, server, identities] = await Promise.all([
        session.api.get<ListResponse<Link>>(path, {
          perPage: 200,
          sort: '-created',
          filter: `workspace = "${session.workspace}" && purpose = "application"`,
        }),
        this.domain ? Promise.resolve({ domain: this.domain }) : session.api.get<{ domain: string }>('/api/server'),
        session.api
          .get<ListResponse<Identity>>('/api/collections/identities/records', {
            perPage: 1,
            filter: `workspace = "${session.workspace}" && isPrimary = true`,
          })
          .catch(() => ({ items: [] as Identity[] })),
      ]);
      this.links = links.items;
      this.domain = server.domain;
      this.identity = identities.items[0] ?? null;
      this.loaded = true;
    } catch (e) {
      // PocketBase answers a filter on a field it doesn't have with a bare 400,
      // which is what a server without migration 000056 does here.
      this.error =
        e instanceof ApiError && e.status === 400
          ? t('error.serverOutdated')
          : describeError(e);
    } finally {
      this.loading = false;
    }
  }

  reset() {
    this.links = [];
    this.loaded = false;
    this.domain = '';
    this.identity = null;
  }

  urlFor(link: Pick<Link, 'slug'>) {
    return landlordUrl(this.domain, session.api.base, link.slug);
  }

  startDraft() {
    this.editing = null;
    this.address = '';
    this.expiryDays = 14;
    this.signed = true;
    this.draftError = null;
    this.selected = new Set(
      vault.records
        .filter((r) => (r.type === 'file' ? isStampable(r) : isProfileRecord(r.key)))
        .map((r) => r.id),
    );
  }

  startEdit(link: Link) {
    this.editing = link;
    this.address = addressOf(link);
    this.expiryDays = 0;
    this.signed = !!link.identity;
    this.draftError = null;
    this.selected = new Set(link.records);
  }

  save(): Promise<Link | null> {
    return this.editing ? this.#update(this.editing) : this.create();
  }

  async #update(link: Link): Promise<Link | null> {
    if (!this.canSubmit) return null;
    this.submitting = true;
    this.draftError = null;
    try {
      const body = applicationUpdate({
        address: this.address,
        recordIds: vault.records.filter((r) => this.selected.has(r.id)).map((r) => r.id),
        expiryDays: this.expiryDays,
        // An application signed by another identity keeps it.
        identityId: this.signed ? link.identity || this.identity?.id : undefined,
        status: link.status,
        now: new Date(),
      });
      const updated = await session.api.patch<Link>(`${path}/${link.id}`, body);
      this.links = this.links.map((l) => (l.id === updated.id ? updated : l));
      this.editing = null;
      return updated;
    } catch (e) {
      this.draftError = describeError(e);
      return null;
    } finally {
      this.submitting = false;
    }
  }

  toggle(id: string) {
    const next = new Set(this.selected);
    if (!next.delete(id)) next.add(id);
    this.selected = next;
  }

  async create(): Promise<Link | null> {
    if (!this.canSubmit || !session.user) return null;
    this.submitting = true;
    this.draftError = null;
    try {
      const body = applicationBody({
        address: this.address,
        recordIds: vault.records.filter((r) => this.selected.has(r.id)).map((r) => r.id),
        expiryDays: this.expiryDays,
        identityId: this.signed ? this.identity?.id : undefined,
        user: session.user.id,
        workspace: session.workspace,
        slug: randomSlug(),
        now: new Date(),
      });
      const link = await session.api.post<Link>(path, body);
      this.links = [link, ...this.links];
      return link;
    } catch (e) {
      this.draftError = describeError(e);
      return null;
    } finally {
      this.submitting = false;
    }
  }

  // Asked when records are created: applications are explicit grants, so a
  // new document reaches a landlord only if the applicant says so. Files that
  // cannot be stamped are left out, since a watermarked link refuses them.
  async offer(added: VaultRecord[]) {
    const records = added.filter(isStampable);
    const targets = this.live;
    if (!records.length || !targets.length) return;
    const ok = await confirm.ask({
      title: t('propagate.title', { n: targets.length }),
      message: t('propagate.message', { names: records.map(recordName).join(', '), n: targets.length }),
      action: t('propagate.action'),
      cancel: t('propagate.skip'),
    });
    if (!ok) return;
    const ids = records.map((r) => r.id);
    let done = 0;
    for (const link of targets) {
      const ok = await this.#run(link.id, async () => {
        const updated = await session.api.patch<Link>(`${path}/${link.id}`, { 'records+': ids });
        this.links = this.links.map((l) => (l.id === updated.id ? updated : l));
      });
      if (ok) done++;
    }
    toast.show(t('propagate.done', { n: done }));
  }

  isBusy(id: string) {
    return this.busyIds.has(id);
  }

  extend(link: Link) {
    return this.#patch(link, {
      expiresAt: extendedExpiry(link.expiresAt, new Date()),
      ...(link.status === 'expired' ? { status: 'active' } : {}),
    });
  }

  // Every file of the application, stamped by the server, as one zip.
  download(link: Link) {
    return this.#run(link.id, async () => {
      const { blob, filename } = await session.api.download(
        `/api/links/${encodeURIComponent(link.id)}/archive`,
        `${addressOf(link) || link.slug}.zip`,
      );
      saveBlob(blob, filename);
    });
  }

  filesOf(link: Link) {
    return vault.files.filter((r) => link.records.includes(r.id));
  }

  revoke(link: Link) {
    return this.#patch(link, { status: 'revoked' });
  }

  async remove(link: Link): Promise<boolean> {
    return this.#run(link.id, async () => {
      await session.api.delete(`${path}/${link.id}`);
      this.links = this.links.filter((l) => l.id !== link.id);
    });
  }

  #patch(link: Link, body: Record<string, unknown>) {
    return this.#run(link.id, async () => {
      const updated = await session.api.patch<Link>(`${path}/${link.id}`, body);
      this.links = this.links.map((l) => (l.id === updated.id ? updated : l));
    });
  }

  async #run(id: string, fn: () => Promise<unknown>): Promise<boolean> {
    this.busyIds = new Set(this.busyIds).add(id);
    this.error = null;
    try {
      await fn();
      return true;
    } catch (e) {
      this.error = describeError(e);
      return false;
    } finally {
      const next = new Set(this.busyIds);
      next.delete(id);
      this.busyIds = next;
    }
  }
}

export const applications = new Applications();
