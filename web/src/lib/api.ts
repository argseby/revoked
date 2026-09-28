import { t } from './i18n.svelte';
import type { MessageKey } from './locales/en';

// A thin client over the revoked HTTP API. Every request goes through `send`,
// so authentication, error decoding and the 401 hand-off live in one place.

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly fields: Record<string, { code: string; message: string }> = {},
  ) {
    super(message);
  }
}

export interface ApiClientOptions {
  base: string;
  token: () => string | null;
  onUnauthorized: () => void;
}

type Query = Record<string, string | number | undefined>;

export class ApiClient {
  constructor(private readonly opts: ApiClientOptions) {}

  get base(): string {
    return this.opts.base;
  }

  url(path: string, query?: Query): string {
    const u = new URL(path, this.opts.base);
    for (const [k, v] of Object.entries(query ?? {})) {
      if (v !== undefined) u.searchParams.set(k, String(v));
    }
    return u.toString();
  }

  get<T>(path: string, query?: Query): Promise<T> {
    return this.send<T>('GET', path, { query });
  }

  post<T>(path: string, body?: unknown): Promise<T> {
    return this.send<T>('POST', path, { body });
  }

  patch<T>(path: string, body: unknown): Promise<T> {
    return this.send<T>('PATCH', path, { body });
  }

  delete(path: string): Promise<void> {
    return this.send<void>('DELETE', path, {});
  }

  multipart<T>(method: 'POST' | 'PATCH', path: string, form: FormData): Promise<T> {
    return this.send<T>(method, path, { form });
  }

  async bytes(path: string, query?: Query): Promise<Blob> {
    const res = await fetch(this.url(path, query), { headers: this.headers() });
    if (!res.ok) throw await decodeError(res);
    return res.blob();
  }

  // A file the server names itself, as a Content-Disposition attachment.
  async download(path: string, fallbackName: string): Promise<{ blob: Blob; filename: string }> {
    const res = await fetch(this.url(path), { headers: this.headers() });
    if (res.status === 401 && this.opts.token()) this.opts.onUnauthorized();
    if (!res.ok) throw await decodeError(res);
    return { blob: await res.blob(), filename: dispositionName(res.headers.get('Content-Disposition')) ?? fallbackName };
  }

  async postForBlob(path: string, body: unknown): Promise<Blob> {
    const res = await fetch(this.url(path), {
      method: 'POST',
      headers: { ...this.headers(), 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (res.status === 401 && this.opts.token()) this.opts.onUnauthorized();
    if (!res.ok) throw await decodeError(res);
    return res.blob();
  }

  private headers(): Record<string, string> {
    const token = this.opts.token();
    return token ? { Authorization: `Bearer ${token}` } : {};
  }

  private async send<T>(
    method: string,
    path: string,
    { query, body, form }: { query?: Query; body?: unknown; form?: FormData },
  ): Promise<T> {
    const headers = this.headers();
    let payload: BodyInit | undefined;
    if (form) {
      payload = form;
    } else if (body !== undefined) {
      headers['Content-Type'] = 'application/json';
      payload = JSON.stringify(body);
    }

    let res: Response;
    try {
      res = await fetch(this.url(path, query), { method, headers, body: payload });
    } catch {
      throw new ApiError(0, 'network', 'The server could not be reached.');
    }

    if (res.status === 401 && headers.Authorization) this.opts.onUnauthorized();
    if (!res.ok) throw await decodeError(res);
    if (res.status === 204) return undefined as T;
    return (await res.json()) as T;
  }
}

// Prefers the RFC 6266 UTF-8 name: the quoted one is only an ASCII fallback.
export function dispositionName(header: string | null): string | null {
  const cd = header ?? '';
  const ext = /filename\*=UTF-8''([^;]+)/i.exec(cd);
  if (ext) {
    try {
      return decodeURIComponent(ext[1]);
    } catch {
      /* malformed: use the fallback */
    }
  }
  return /filename="([^"]+)"/i.exec(cd)?.[1] ?? null;
}

// The server answers in two shapes: its own envelope ({code, message, status})
// and PocketBase's ({status, message, data: {field: {code, message}}}). A field
// error is where hook refusals such as `application_needs_watermark` land.
async function decodeError(res: Response): Promise<ApiError> {
  let body: Record<string, unknown> = {};
  try {
    body = await res.json();
  } catch {
    /* not JSON */
  }
  const fields = (body.data ?? {}) as Record<string, { code: string; message: string }>;
  const firstField = Object.values(fields).find((f) => f && typeof f.code === 'string');
  const code = String(body.code ?? firstField?.code ?? `http_${res.status}`);
  const message = String(firstField?.message ?? body.message ?? res.statusText ?? 'Request failed');
  return new ApiError(res.status, code, message, fields);
}

const friendly: Record<string, MessageKey> = {
  network: 'error.network',
  application_needs_watermark: 'error.needsWatermark',
  file_not_watermarkable: 'error.notWatermarkable',
  archive_empty: 'error.archiveEmpty',
  http_413: 'error.tooLarge',
  http_429: 'error.rateLimited',
};

export function describeError(e: unknown): string {
  if (e instanceof ApiError) return friendly[e.code] ? t(friendly[e.code]) : e.message;
  if (e instanceof Error) return e.message;
  return t('error.generic');
}
