import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const SERVER = 'https://id.example.com';

export function fixture<T = any>(name: string): T {
  const path = fileURLToPath(new URL(`../../../app/test/fixtures/${name}`, import.meta.url));
  return JSON.parse(readFileSync(path, 'utf8')) as T;
}

export interface Call {
  method: string;
  url: URL;
  headers: Headers;
  body: unknown;
  rawBody: BodyInit | null | undefined;
}

type Handler = (call: Call) => Response | Promise<Response>;

/** A fetch that records each call and answers from the queued handlers, in order. */
export function mockFetch(...handlers: Handler[]) {
  const calls: Call[] = [];
  const queue = [...handlers];
  const fetchImpl = (async (input: RequestInfo | URL, init: RequestInit = {}) => {
    const url = new URL(String(input instanceof Request ? input.url : input));
    let body: unknown = init.body;
    if (typeof init.body === 'string') {
      try {
        body = JSON.parse(init.body);
      } catch {
        body = init.body;
      }
    }
    const call: Call = { method: init.method ?? 'GET', url, headers: new Headers(init.headers), body, rawBody: init.body };
    calls.push(call);
    const handler = queue.shift();
    if (!handler) throw new Error(`Unexpected request: ${call.method} ${url}`);
    return handler(call);
  }) as typeof fetch;
  return { fetch: fetchImpl, calls };
}

export function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(status === 204 ? null : JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}

/** A session token whose payload names the user, as PocketBase issues them. */
export function sessionToken(userId: string): string {
  const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
  return `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ id: userId, type: 'auth' })}.sig`;
}
