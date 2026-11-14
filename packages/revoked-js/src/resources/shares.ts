import { dispositionName, jsonBody } from '../core/body.js';
import { randomSlug } from '../core/encoding.js';
import { RevokedError } from '../core/errors.js';
import { f } from '../core/filter.js';
import { Collection } from '../core/collection.js';
import type { ClientContext } from '../core/context.js';
import { path } from '../core/context.js';
import type { CallOptions } from '../core/transport.js';
import type {
  Download,
  Identity,
  Link,
  LinkInput,
  RequestInput,
  RequestResponse,
  RevokedRequest,
  Template,
  TemplateInput,
} from '../models.js';

export async function download(
  ctx: ClientContext,
  url: string,
  options: CallOptions & { query?: Record<string, string>; anonymous?: boolean; method?: 'GET' | 'POST'; body?: unknown } = {},
): Promise<Download> {
  const res = await ctx.transport.raw<Blob>(url, {
    method: options.method ?? 'GET',
    query: options.query,
    body: options.body,
    anonymous: options.anonymous,
    responseType: 'blob',
    signal: options.signal,
    idempotent: false,
  });
  return {
    blob: res.data,
    filename: dispositionName(res.headers.get('Content-Disposition')),
    contentType: res.headers.get('Content-Type') ?? undefined,
  };
}

/** Shares: living grants over vault records, resolved at read time. */
export class Links extends Collection<Link, LinkInput> {
  constructor(ctx: ClientContext) {
    super(ctx, 'links');
  }

  override create(input: LinkInput, options?: CallOptions): Promise<Link> {
    return super.create({ ...input, slug: input.slug ?? randomSlug() }, options);
  }

  /** The browser address of a share: `https://<server>/s/<slug>`. */
  url(link: Pick<Link, 'slug'>): string {
    return this.ctx.transport.url(path`s/${link.slug}`).toString();
  }

  /** The app address of a share, which opens it in the Revoked app. */
  appLink(link: Pick<Link, 'slug'>): string {
    return `revoked://s/${encodeURIComponent(this.ctx.transport.baseUrl.origin)}/${encodeURIComponent(link.slug)}`;
  }

  pause(id: string, options?: CallOptions): Promise<Link> {
    return this.update(id, { status: 'paused' }, options);
  }

  resume(id: string, options?: CallOptions): Promise<Link> {
    return this.update(id, { status: 'active' }, options);
  }

  /** Ends the share for good. Readers are refused from the next request on. */
  revoke(id: string, options?: CallOptions): Promise<Link> {
    return this.update(id, { status: 'revoked' }, options);
  }

  /** Every file the share grants as one zip. Claims no view. */
  archive(id: string, options?: CallOptions): Promise<Download> {
    return download(this.ctx, path`api/links/${id}/archive`, options);
  }

  /** A watermarked rendering of a file record, as a share with that stamp would serve it. */
  stampPreview(input: { record: string; text?: string; link?: string }, options?: CallOptions): Promise<Download> {
    return download(this.ctx, 'api/stamp-preview', { ...options, method: 'POST', body: jsonBody(input) });
  }
}

/** Requests: forms that collect answers as living grants in the responder's workspace. */
export class Requests extends Collection<RevokedRequest, RequestInput> {
  constructor(ctx: ClientContext) {
    super(ctx, 'requests');
  }

  override async create(input: RequestInput, options: CallOptions = {}): Promise<RevokedRequest> {
    const identity = input.identity ?? (await this.primaryIdentity(options));
    return super.create({ ...input, identity, slug: input.slug ?? randomSlug() }, options);
  }

  private async primaryIdentity(options: CallOptions): Promise<string> {
    const list = await this.ctx.transport.request<{ items: Identity[] }>('api/collections/identities/records', {
      query: { filter: f`isPrimary = true && status = ${'active'}`.expression, perPage: 1, skipTotal: true },
      signal: options.signal,
    });
    const id = list.items[0]?.id;
    if (!id) {
      throw new RevokedError({ status: 0, code: 'identity_required', message: 'The workspace has no primary identity. Pass `identity`.' });
    }
    return id;
  }

  /** The app address to hand to whoever should answer. Answering takes an account. */
  appLink(request: Pick<RevokedRequest, 'slug'>): string {
    return `revoked://r/${encodeURIComponent(this.ctx.transport.baseUrl.origin)}/${encodeURIComponent(request.slug)}`;
  }

  pause(id: string, options?: CallOptions): Promise<RevokedRequest> {
    return this.update(id, { status: 'paused' }, options);
  }

  resume(id: string, options?: CallOptions): Promise<RevokedRequest> {
    return this.update(id, { status: 'active' }, options);
  }

  /** Stops new answers. Answers already given stay their responders' grants. */
  close(id: string, options?: CallOptions): Promise<RevokedRequest> {
    return this.update(id, { status: 'revoked' }, options);
  }

  /** The answers, each resolved to its current values. At most 200, newest first. */
  async responses(id: string, options: CallOptions = {}): Promise<RequestResponse[]> {
    const res = await this.ctx.transport.request<{ items: RequestResponse[] }>(path`api/requests/${id}/links`, {
      signal: options.signal,
    });
    return res.items;
  }

  /** Sends a sample submission to a callback address and reports how it answered. */
  testCallback(
    input: { url: string; requestId?: string },
    options: CallOptions = {},
  ): Promise<{ ok: boolean; status: number; code: 'ok' | 'blocked' | 'unreachable' | 'status' | (string & {}); detail: string }> {
    return this.ctx.transport.request('api/requests/callback-test', {
      method: 'POST',
      body: jsonBody(input),
      signal: options.signal,
    });
  }
}

export class Templates extends Collection<Template, TemplateInput> {
  constructor(ctx: ClientContext) {
    super(ctx, 'templates');
  }
}
