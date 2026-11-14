import type { KnownErrorCode } from '../generated/codes.js';

/** A server error code. Known codes autocomplete; a newer server's codes pass through unchanged. */
export type ErrorCode = KnownErrorCode | 'network' | 'timeout' | `http_${number}` | (string & {});

export interface FieldError {
  code: string;
  message: string;
}

export interface RevokedErrorInit {
  status: number;
  code: ErrorCode;
  message: string;
  fields?: Record<string, FieldError>;
  retryAfter?: number;
  body?: unknown;
  cause?: unknown;
}

/** Every failure the SDK raises. `status` is 0 when no answer arrived. */
export class RevokedError extends Error {
  readonly status: number;
  readonly code: ErrorCode;
  readonly fields: Record<string, FieldError>;
  /** The undecoded error body, for codes this SDK version does not model. */
  readonly body: unknown;

  constructor(init: RevokedErrorInit) {
    super(init.message, init.cause === undefined ? undefined : { cause: init.cause });
    this.name = new.target.name;
    this.status = init.status;
    this.code = init.code;
    this.fields = init.fields ?? {};
    this.body = init.body;
  }
}

/** 400 or 422: the input was refused. `fields` names the offending fields when the server did. */
export class ValidationError extends RevokedError {}
/** 401: no credential, or one the server does not accept. */
export class AuthenticationError extends RevokedError {}
/** 403: the credential is valid but may not do this. Paused shares and requests also answer 403. */
export class PermissionError extends RevokedError {}
/** 404. */
export class NotFoundError extends RevokedError {}
/** 409: the write conflicts with the current state. */
export class ConflictError extends RevokedError {}
/** 410: revoked, expired, completed or already used. */
export class GoneError extends RevokedError {}
/** 413: a file or the storage allowance is too large. */
export class PayloadTooLargeError extends RevokedError {}
/** 429. `retryAfter` is in seconds. */
export class RateLimitedError extends RevokedError {
  readonly retryAfter: number | undefined;
  constructor(init: RevokedErrorInit) {
    super(init);
    this.retryAfter = init.retryAfter;
  }
}
/** 5xx. */
export class ServerError extends RevokedError {}
/** The server could not be reached, or the connection broke. */
export class NetworkError extends RevokedError {}
/** No answer within the configured timeout. */
export class TimeoutError extends RevokedError {}

function classFor(status: number): new (init: RevokedErrorInit) => RevokedError {
  switch (status) {
    case 400:
    case 422:
      return ValidationError;
    case 401:
      return AuthenticationError;
    case 403:
      return PermissionError;
    case 404:
      return NotFoundError;
    case 409:
      return ConflictError;
    case 410:
      return GoneError;
    case 413:
      return PayloadTooLargeError;
    case 429:
      return RateLimitedError;
    default:
      return status >= 500 ? ServerError : RevokedError;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * Decodes the three error shapes the server answers with: its own envelope
 * `{code, message, status}`, PocketBase's `{status, message, data: {field: {code, message}}}`,
 * and OAuth's `{error, error_description}`.
 */
export function decodeError(status: number, body: unknown, statusText = '', retryAfterHeader?: string | null): RevokedError {
  let code: string | undefined;
  let message: string | undefined;
  const fields: Record<string, FieldError> = {};

  if (isRecord(body)) {
    if (isRecord(body.data)) {
      for (const [name, value] of Object.entries(body.data)) {
        if (isRecord(value) && typeof value.code === 'string') {
          fields[name] = { code: value.code, message: typeof value.message === 'string' ? value.message : '' };
        }
      }
    }
    const firstField = Object.values(fields)[0];
    if (typeof body.code === 'string' && body.code !== '') code = body.code;
    else if (typeof body.error === 'string') code = body.error;
    else if (firstField) code = firstField.code;

    if (typeof body.message === 'string' && body.message !== '') message = body.message;
    else if (typeof body.error_description === 'string') message = body.error_description;
    const named = Object.entries(fields);
    if (named.length > 0 && (!message || /^Failed to (create|update) record\.?$/.test(message) || message.startsWith('Something went wrong'))) {
      message = named.map(([field, e]) => `${field}: ${e.message || e.code}`).join(' ');
    }
  }

  const retryAfter = parseRetryAfter(retryAfterHeader);
  const ErrorClass = classFor(status);
  return new ErrorClass({
    status,
    code: code ?? `http_${status}`,
    message: message ?? (statusText || `Request failed with status ${status}.`),
    fields,
    body,
    ...(retryAfter === undefined ? {} : { retryAfter }),
  });
}

export function parseRetryAfter(header: string | null | undefined): number | undefined {
  if (!header) return undefined;
  const seconds = Number(header);
  if (Number.isFinite(seconds) && seconds >= 0) return seconds;
  const date = Date.parse(header);
  if (Number.isNaN(date)) return undefined;
  return Math.max(0, Math.ceil((date - Date.now()) / 1000));
}
