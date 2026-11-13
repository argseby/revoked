import { NetworkError, RevokedError, TimeoutError, decodeError } from './errors.js';

/**
 * The credential a client acts with. Each travels in its own header; the
 * server treats one sent in another's header as no credential at all.
 */
export type Credential =
  | { apiKey: string }
  | { connection: string }
  | {
      session: string;
      /** Called with the renewed token after the client refreshed an expired session. */
      onSessionRefresh?: (token: string) => void | Promise<void>;
    };

export interface RetryOptions {
  /** Further attempts after the first. Default 2. */
  max?: number;
  /** A 429 is retried only when the server asks for at most this wait. Default 10 000 ms. */
  maxWaitMs?: number;
}

export interface TransportOptions {
  /** The server's origin, e.g. `https://id.example.com`. A path prefix is kept. */
  server: string | URL;
  credential?: Credential | undefined;
  /** Defaults to the global `fetch`. */
  fetch?: typeof fetch;
  /** Per attempt. Default 30 000 ms; 0 disables it. */
  timeoutMs?: number;
  retry?: RetryOptions;
  /** Sent with every request. */
  headers?: Record<string, string>;
}

export type Query = Record<string, string | number | boolean | undefined | null>;

export type ResponseType = 'json' | 'text' | 'blob' | 'stream' | 'none';

export interface RequestOptions {
  method?: 'GET' | 'HEAD' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  query?: Query | undefined;
  /** Sent as JSON. */
  body?: unknown;
  form?: FormData | undefined;
  urlEncoded?: Record<string, string> | undefined;
  headers?: Record<string, string> | undefined;
  /** Leave the client's credential off this request. */
  anonymous?: boolean | undefined;
  /** Safe to send again after a lost answer. GET and HEAD are by default. */
  idempotent?: boolean | undefined;
  responseType?: ResponseType | undefined;
  signal?: AbortSignal | undefined;
  /** Statuses returned instead of thrown, e.g. 202 for a pending poll. */
  acceptStatus?: number[] | undefined;
}

export interface RawResponse<T> {
  data: T;
  status: number;
  headers: Headers;
}

/** Per-call options every SDK method accepts. */
export interface CallOptions {
  signal?: AbortSignal | undefined;
}

const RETRYABLE_STATUS = new Set([429, 502, 503, 504]);

export class Transport {
  readonly baseUrl: URL;
  private credential: Credential | undefined;
  private readonly fetchImpl: typeof fetch;
  private readonly timeoutMs: number;
  private readonly maxRetries: number;
  private readonly maxRetryWaitMs: number;
  private readonly extraHeaders: Record<string, string>;
  private refreshing: Promise<boolean> | undefined;

  constructor(options: TransportOptions) {
    const base = new URL(String(options.server));
    if (base.protocol !== 'https:' && base.protocol !== 'http:') {
      throw new TypeError('The server URL must use http or https.');
    }
    base.search = '';
    base.hash = '';
    if (!base.pathname.endsWith('/')) base.pathname += '/';
    this.baseUrl = base;
    this.credential = options.credential;
    const f = options.fetch ?? globalThis.fetch;
    if (typeof f !== 'function') throw new TypeError('No fetch implementation is available; pass one as `fetch`.');
    this.fetchImpl = (...args) => f(...args);
    this.timeoutMs = options.timeoutMs ?? 30_000;
    this.maxRetries = options.retry?.max ?? 2;
    this.maxRetryWaitMs = options.retry?.maxWaitMs ?? 10_000;
    this.extraHeaders = { ...options.headers };
  }

  get credentialKind(): 'apiKey' | 'connection' | 'session' | 'none' {
    const c = this.credential;
    if (!c) return 'none';
    if ('apiKey' in c) return 'apiKey';
    if ('connection' in c) return 'connection';
    return 'session';
  }

  /** The current session token, after any refresh. */
  get sessionToken(): string | undefined {
    const c = this.credential;
    return c && 'session' in c ? c.session : undefined;
  }

  url(path: string, query?: Query): URL {
    const url = new URL(path.replace(/^\//, ''), this.baseUrl);
    for (const [key, value] of Object.entries(query ?? {})) {
      if (value !== undefined && value !== null) url.searchParams.set(key, String(value));
    }
    return url;
  }

  async request<T>(path: string, options: RequestOptions = {}): Promise<T> {
    return (await this.raw<T>(path, options)).data;
  }

  async raw<T>(path: string, options: RequestOptions = {}): Promise<RawResponse<T>> {
    const method = options.method ?? 'GET';
    const idempotent = options.idempotent ?? (method === 'GET' || method === 'HEAD');
    let refreshed = false;

    for (let attempt = 0; ; attempt++) {
      let response: Response;
      try {
        response = await this.send(path, method, options);
      } catch (error) {
        if (error instanceof RevokedError && error instanceof NetworkError && idempotent && attempt < this.maxRetries) {
          await sleep(backoff(attempt), options.signal);
          continue;
        }
        throw error;
      }

      if (response.status === 401 && !refreshed && !options.anonymous && this.credentialKind === 'session') {
        refreshed = true;
        const unauthorized = await errorFrom(response);
        if (await this.refreshSession()) {
          attempt--;
          continue;
        }
        throw unauthorized;
      }

      if (!response.ok && !options.acceptStatus?.includes(response.status)) {
        if (RETRYABLE_STATUS.has(response.status) && attempt < this.maxRetries && (idempotent || response.status === 429)) {
          const wait = retryWait(response, attempt);
          if (wait <= this.maxRetryWaitMs) {
            await response.body?.cancel();
            await sleep(wait, options.signal);
            continue;
          }
        }
        throw await errorFrom(response);
      }

      const data = (await parseBody(response, options.responseType ?? 'json')) as T;
      return { data, status: response.status, headers: response.headers };
    }
  }

  private headers(options: RequestOptions): Headers {
    const headers = new Headers(this.extraHeaders);
    headers.set('Accept', 'application/json');
    const c = this.credential;
    if (c && !options.anonymous) {
      if ('apiKey' in c) headers.set('X-API-Key', c.apiKey);
      else if ('connection' in c) headers.set('X-Revoked-Connection', c.connection);
      else headers.set('Authorization', `Bearer ${c.session}`);
    }
    for (const [key, value] of Object.entries(options.headers ?? {})) headers.set(key, value);
    return headers;
  }

  private async send(path: string, method: string, options: RequestOptions): Promise<Response> {
    const headers = this.headers(options);
    let body: BodyInit | undefined;
    if (options.form) {
      body = options.form;
    } else if (options.urlEncoded) {
      headers.set('Content-Type', 'application/x-www-form-urlencoded');
      body = new URLSearchParams(options.urlEncoded).toString();
    } else if (options.body !== undefined) {
      headers.set('Content-Type', 'application/json');
      body = JSON.stringify(options.body);
    }

    const signals: AbortSignal[] = [];
    if (options.signal) signals.push(options.signal);
    let timeout: AbortSignal | undefined;
    if (this.timeoutMs > 0) {
      timeout = AbortSignal.timeout(this.timeoutMs);
      signals.push(timeout);
    }
    const signal = signals.length === 0 ? undefined : signals.length === 1 ? signals[0] : AbortSignal.any(signals);

    try {
      return await this.fetchImpl(this.url(path, options.query), {
        method,
        headers,
        redirect: 'manual',
        ...(body === undefined ? {} : { body }),
        ...(signal ? { signal } : {}),
      });
    } catch (error) {
      if (options.signal?.aborted) throw options.signal.reason ?? error;
      if (timeout?.aborted) {
        throw new TimeoutError({ status: 0, code: 'timeout', message: `No answer within ${this.timeoutMs} ms.`, cause: error });
      }
      throw new NetworkError({ status: 0, code: 'network', message: 'The server could not be reached.', cause: error });
    }
  }

  private refreshSession(): Promise<boolean> {
    this.refreshing ??= (async () => {
      try {
        const c = this.credential;
        if (!c || !('session' in c)) return false;
        const response = await this.send('api/collections/users/auth-refresh', 'POST', {});
        if (!response.ok) {
          await response.body?.cancel();
          return false;
        }
        const json = (await response.json()) as { token?: unknown };
        if (typeof json.token !== 'string' || json.token === '') return false;
        this.credential = { ...c, session: json.token };
        await c.onSessionRefresh?.(json.token);
        return true;
      } catch {
        return false;
      } finally {
        this.refreshing = undefined;
      }
    })();
    return this.refreshing;
  }
}

async function errorFrom(response: Response): Promise<RevokedError> {
  let body: unknown;
  const text = await response.text().catch(() => '');
  try {
    body = text ? JSON.parse(text) : undefined;
  } catch {
    body = text;
  }
  return decodeError(response.status, body, response.statusText, response.headers.get('Retry-After'));
}

async function parseBody(response: Response, type: ResponseType): Promise<unknown> {
  switch (type) {
    case 'none':
      await response.body?.cancel();
      return undefined;
    case 'text':
      return response.text();
    case 'blob':
      return response.blob();
    case 'stream':
      return response.body;
    case 'json': {
      if (response.status === 204) return undefined;
      const text = await response.text();
      return text === '' ? undefined : JSON.parse(text);
    }
  }
}

function backoff(attempt: number): number {
  const base = Math.min(8_000, 250 * 2 ** attempt);
  return base / 2 + Math.random() * (base / 2);
}

function retryWait(response: Response, attempt: number): number {
  const header = response.headers.get('Retry-After');
  if (header !== null) {
    const seconds = Number(header);
    if (Number.isFinite(seconds) && seconds >= 0) return seconds * 1000;
    const date = Date.parse(header);
    if (!Number.isNaN(date)) return Math.max(0, date - Date.now());
  }
  return backoff(attempt);
}

function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(signal.reason);
    const timer = setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(timer);
      reject(signal?.reason);
    };
    signal?.addEventListener('abort', onAbort, { once: true });
  });
}

/** Returns a value from an `X-…` header the server sends exactly once. */
export function onceHeader(headers: Headers, name: string): string {
  const value = headers.get(name);
  if (!value) {
    throw new RevokedError({ status: 0, code: 'missing_header', message: `The server answered without ${name}.` });
  }
  return value;
}
