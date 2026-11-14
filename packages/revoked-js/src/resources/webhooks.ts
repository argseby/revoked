import { jsonBody } from '../core/body.js';
import type { ClientContext } from '../core/context.js';
import { path } from '../core/context.js';
import { iterate, type Page } from '../core/pagination.js';
import type { CallOptions } from '../core/transport.js';
import type {
  WebhookDelivery,
  WebhookEndpoint,
  WebhookEndpointInput,
  WebhookEventTypeInfo,
  WebhookMetrics,
} from '../models.js';
import type { WebhookEvent } from '../webhooks/events.js';

export interface WebhookPageParams extends CallOptions {
  page?: number;
  /** At most 100. Default 50. */
  perPage?: number;
}

export interface WebhookEventListParams extends WebhookPageParams {
  type?: string;
}

export interface WebhookDeliveryListParams extends WebhookPageParams {
  endpoint?: string;
  status?: 'pending' | 'succeeded' | 'failed';
  type?: string;
  event?: string;
}

interface WebhookList<T> {
  items: T[];
  page: number;
  perPage: number;
}

function toPage<T>(list: WebhookList<T>): Page<T> {
  return { items: list.items, page: list.page, perPage: list.perPage, hasMore: list.items.length >= list.perPage };
}

/** Workspace webhooks. Needs the `webhooks:manage` permission. */
export class Webhooks {
  readonly endpoints: WebhookEndpoints;
  readonly events: {
    list: (params?: WebhookEventListParams) => Promise<Page<WebhookEvent>>;
    iterate: (params?: Omit<WebhookEventListParams, 'page'>) => AsyncGenerator<WebhookEvent, void, undefined>;
  };
  readonly deliveries: {
    list: (params?: WebhookDeliveryListParams) => Promise<Page<WebhookDelivery>>;
    iterate: (params?: Omit<WebhookDeliveryListParams, 'page'>) => AsyncGenerator<WebhookDelivery, void, undefined>;
    get: (id: string, options?: CallOptions) => Promise<WebhookDelivery>;
    resend: (id: string, options?: CallOptions) => Promise<WebhookDelivery>;
  };

  constructor(private readonly ctx: ClientContext) {
    this.endpoints = new WebhookEndpoints(ctx);
    const list = async <T>(url: string, params: WebhookPageParams & Record<string, unknown>): Promise<Page<T>> => {
      const { signal, ...query } = params;
      const res = await ctx.transport.request<WebhookList<T>>(url, {
        query: query as Record<string, string | number | undefined>,
        signal,
      });
      return toPage(res);
    };
    this.events = {
      list: (params = {}) => list<WebhookEvent>('api/webhooks/events', { ...params }),
      iterate: (params = {}) => iterate((page) => this.events.list({ perPage: 100, ...params, page })),
    };
    this.deliveries = {
      list: (params = {}) => list<WebhookDelivery>('api/webhooks/deliveries', { ...params }),
      iterate: (params = {}) => iterate((page) => this.deliveries.list({ perPage: 100, ...params, page })),
      get: (id, options = {}) => ctx.transport.request(path`api/webhooks/deliveries/${id}`, { signal: options.signal }),
      resend: (id, options = {}) =>
        ctx.transport.request(path`api/webhooks/deliveries/${id}/resend`, { method: 'POST', signal: options.signal }),
    };
  }

  /** The event catalogue, and whether this server delivers to private addresses. */
  eventTypes(options: CallOptions = {}): Promise<{ items: WebhookEventTypeInfo[]; privateCallbacks: boolean }> {
    return this.ctx.transport.request('api/webhooks/event-types', { signal: options.signal });
  }
}

export class WebhookEndpoints {
  constructor(private readonly ctx: ClientContext) {}

  async list(options: CallOptions = {}): Promise<WebhookEndpoint[]> {
    return (await this.ctx.transport.request<{ items: WebhookEndpoint[] }>('api/webhooks/endpoints', { signal: options.signal })).items;
  }

  get(id: string, options: CallOptions = {}): Promise<WebhookEndpoint> {
    return this.ctx.transport.request(path`api/webhooks/endpoints/${id}`, { signal: options.signal });
  }

  /** The answer carries the signing `secret`. */
  create(input: WebhookEndpointInput & { url: string }, options: CallOptions = {}): Promise<WebhookEndpoint & { secret: string }> {
    return this.ctx.transport.request('api/webhooks/endpoints', {
      method: 'POST',
      body: jsonBody(input),
      signal: options.signal,
    });
  }

  update(id: string, input: WebhookEndpointInput, options: CallOptions = {}): Promise<WebhookEndpoint> {
    return this.ctx.transport.request(path`api/webhooks/endpoints/${id}`, {
      method: 'PATCH',
      body: jsonBody(input),
      signal: options.signal,
      idempotent: true,
    });
  }

  async delete(id: string, options: CallOptions = {}): Promise<void> {
    await this.ctx.transport.request(path`api/webhooks/endpoints/${id}`, {
      method: 'DELETE',
      responseType: 'none',
      signal: options.signal,
    });
  }

  async secret(id: string, options: CallOptions = {}): Promise<string> {
    return (await this.ctx.transport.request<{ secret: string }>(path`api/webhooks/endpoints/${id}/secret`, { signal: options.signal })).secret;
  }

  /** A new secret. The old one keeps signing alongside it for 24 hours. */
  async rotateSecret(id: string, options: CallOptions = {}): Promise<string> {
    return (
      await this.ctx.transport.request<{ secret: string }>(path`api/webhooks/endpoints/${id}/rotate-secret`, {
        method: 'POST',
        signal: options.signal,
      })
    ).secret;
  }

  /** Sends a sample event of the given type through the real delivery path. */
  test(id: string, type: string, options: CallOptions = {}): Promise<WebhookDelivery> {
    return this.ctx.transport.request(path`api/webhooks/endpoints/${id}/test`, {
      method: 'POST',
      body: { type },
      signal: options.signal,
    });
  }

  /** Queues every event since the given time again. */
  async replay(id: string, since: string | Date, options: CallOptions = {}): Promise<number> {
    const res = await this.ctx.transport.request<{ queued: number }>(path`api/webhooks/endpoints/${id}/replay`, {
      method: 'POST',
      body: { since: since instanceof Date ? since.toISOString() : since },
      signal: options.signal,
    });
    return res.queued;
  }

  metrics(id: string, range: '1h' | '24h' | '7d' = '24h', options: CallOptions = {}): Promise<WebhookMetrics> {
    return this.ctx.transport.request(path`api/webhooks/endpoints/${id}/metrics`, { query: { range }, signal: options.signal });
  }
}
