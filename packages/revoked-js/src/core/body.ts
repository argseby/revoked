import type { FileInput } from '../models.js';

type Input = object;

function normalize(value: unknown): unknown {
  return value instanceof Date ? value.toISOString() : value;
}

/** Drops undefined fields and turns dates into ISO strings. */
export function jsonBody(input: Input): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input)) {
    if (value !== undefined) out[key] = normalize(value);
  }
  return out;
}

export function isFileInput(value: unknown): value is FileInput {
  return (
    (typeof Blob !== 'undefined' && value instanceof Blob) || value instanceof Uint8Array || value instanceof ArrayBuffer
  );
}

/** Multipart for a body carrying bytes; arrays become repeated fields, objects JSON. */
export function formBody(input: Input, fileField = 'file'): FormData {
  const form = new FormData();
  for (const [key, raw] of Object.entries(input)) {
    const value = normalize(raw);
    if (value === undefined) continue;
    if (key === fileField && isFileInput(value)) {
      const named = (input as { filename?: unknown }).filename;
      const filename = typeof named === 'string' && named ? named : nameOf(value);
      form.append(key, toBlob(value), filename);
    } else if (Array.isArray(value)) {
      for (const item of value) form.append(key, String(item));
    } else if (typeof value === 'object' && value !== null) {
      form.append(key, JSON.stringify(value));
    } else {
      form.append(key, String(value));
    }
  }
  return form;
}

function toBlob(value: FileInput): Blob {
  return value instanceof Blob ? value : new Blob([value]);
}

function nameOf(value: FileInput): string {
  return typeof File !== 'undefined' && value instanceof File && value.name ? value.name : 'file';
}

/** JSON or multipart, depending on whether the input carries bytes. */
export function bodyFor(input: Input, fileField = 'file'): { body?: unknown; form?: FormData } {
  return isFileInput((input as Record<string, unknown>)[fileField]) ? { form: formBody(input, fileField) } : { body: jsonBody(input) };
}

/** The file name from a Content-Disposition header, preferring the RFC 6266 UTF-8 form. */
export function dispositionName(header: string | null): string | undefined {
  const value = header ?? '';
  const extended = /filename\*=UTF-8''([^;]+)/i.exec(value);
  if (extended?.[1]) {
    try {
      return decodeURIComponent(extended[1]);
    } catch {
      // Malformed: fall back to the quoted name.
    }
  }
  return /filename="([^"]+)"/i.exec(value)?.[1] ?? /filename=([^;]+)/i.exec(value)?.[1]?.trim();
}
