import { concatBytes, fromBase64, fromUtf8, utf8 } from '../core/encoding.js';
import type { SharedRecord } from '../models.js';

const KEY_LENGTH = 32;
const FORMAT = 1;
const FILE_SEGMENT = 65536;
const TAG = 16;
/** The largest encrypted file a share carries. */
export const SEALED_FILE_MAX = 50 * 1024 * 1024;

export class SealedError extends Error {
  constructor(readonly reason: 'key' | 'format' | 'wrap' | 'padding' | 'content' | 'length' | 'unavailable') {
    super(`The encrypted entry could not be opened (${reason}).`);
    this.name = 'SealedError';
  }
}

type Part = string | number | Uint8Array;

/** What a ciphertext is bound to: each string length-prefixed in 4 bytes, each number 8 bytes, big-endian. */
export function sealContext(label: string, parts: Part[]): Uint8Array<ArrayBuffer> {
  const chunks: Uint8Array[] = [];
  const addBytes = (bytes: Uint8Array) => {
    const length = new Uint8Array(4);
    new DataView(length.buffer).setUint32(0, bytes.length);
    chunks.push(length, bytes);
  };
  addBytes(utf8(label));
  for (const part of parts) {
    if (part instanceof Uint8Array) addBytes(part);
    else if (typeof part === 'number') {
      if (!Number.isSafeInteger(part) || part < 0) throw new SealedError('format');
      const n = new Uint8Array(8);
      const view = new DataView(n.buffer);
      view.setUint32(0, Math.floor(part / 2 ** 32));
      view.setUint32(4, part % 2 ** 32);
      chunks.push(n);
    } else addBytes(utf8(part));
  }
  return concatBytes(...chunks);
}

function unpad(padded: Uint8Array): Uint8Array {
  for (let i = padded.length - 1; i >= 0; i--) {
    if (padded[i] === 0x80) return padded.subarray(0, i);
    if (padded[i] !== 0) break;
  }
  throw new SealedError('padding');
}

async function open(key: Uint8Array<ArrayBuffer>, aad: Uint8Array, sealed: Uint8Array<ArrayBuffer>): Promise<Uint8Array> {
  if (sealed.length < 1 + 12 + TAG || sealed[0] !== FORMAT) throw new SealedError('format');
  const aesKey = await crypto.subtle.importKey('raw', key, { name: 'AES-GCM' }, false, ['decrypt']);
  try {
    return new Uint8Array(
      await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: sealed.subarray(1, 13), additionalData: concatBytes(sealed.subarray(0, 1), aad), tagLength: 128 },
        aesKey,
        sealed.subarray(13),
      ),
    );
  } catch {
    throw new SealedError('format');
  }
}

async function hkdf(ikm: Uint8Array<ArrayBuffer>, info: Uint8Array<ArrayBuffer>): Promise<Uint8Array<ArrayBuffer>> {
  const key = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  return new Uint8Array(
    await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt: new Uint8Array(0), info }, key, KEY_LENGTH * 8),
  );
}

/** The link key from a share address's `#k=` fragment, or from the fragment alone. */
export function linkKeyFrom(addressOrFragment: string): Uint8Array<ArrayBuffer> {
  const hashAt = addressOrFragment.indexOf('#');
  const fragment = hashAt >= 0 ? addressOrFragment.slice(hashAt + 1) : addressOrFragment;
  for (const part of fragment.split('&')) {
    if (!part.startsWith('k=')) continue;
    let text = part.slice(2);
    try {
      text = decodeURIComponent(text);
    } catch {
      // Use it as it stands.
    }
    let key: Uint8Array<ArrayBuffer>;
    try {
      key = fromBase64(text);
    } catch {
      throw new SealedError('key');
    }
    if (key.length !== KEY_LENGTH) throw new SealedError('key');
    return key;
  }
  throw new SealedError('key');
}

export interface SealedFile {
  name: string;
  mime: string;
  size: number;
  /** Opens the blob `public.links.file` returned for this entry. */
  open(blob: Blob | Uint8Array<ArrayBuffer>): Promise<Uint8Array>;
}

export interface OpenedEntry {
  id: string;
  key: string;
  /** Empty for a file. */
  value: string;
  /** The label, type and format sealed with the value, not the copies the server states beside it. */
  label: string;
  type: string;
  format: string;
  file?: SealedFile;
}

function isSize(n: unknown): n is number {
  return typeof n === 'number' && Number.isSafeInteger(n) && n >= 0;
}

/**
 * Opens one encrypted entry of an opened share with the link key from its
 * address. The key stays on this device; the server never had it.
 */
export async function openSealedEntry(entry: SharedRecord, linkKey: Uint8Array<ArrayBuffer>): Promise<OpenedEntry> {
  if (entry.unavailable) throw new SealedError('unavailable');
  if (!entry.sealed || !entry.viewerWrap || !entry.sealedValue || entry.sealedVersion === undefined || !entry.key) {
    throw new SealedError('format');
  }
  if (linkKey.length !== KEY_LENGTH) throw new SealedError('key');

  const copyKey = await hkdf(linkKey, sealContext('revoked-link-copy-v1', [entry.id]));
  const wrap = await open(copyKey, sealContext('revoked-link-viewer-v1', [entry.id, entry.sealedVersion]), fromBase64(entry.viewerWrap));
  if (wrap.length <= KEY_LENGTH) throw new SealedError('wrap');
  const valueKey = wrap.slice(0, KEY_LENGTH);
  let workspace: string;
  try {
    workspace = fromUtf8(wrap.subarray(KEY_LENGTH));
  } catch {
    throw new SealedError('wrap');
  }

  const padded = await open(
    valueKey,
    sealContext('revoked-record-v1', [workspace, entry.id, entry.key, entry.sealedVersion]),
    fromBase64(entry.sealedValue),
  );
  let content: { v?: unknown; l?: unknown; t?: unknown; f?: unknown; x?: unknown };
  try {
    content = JSON.parse(fromUtf8(unpad(padded))) as typeof content;
  } catch (error) {
    if (error instanceof SealedError) throw error;
    throw new SealedError('content');
  }
  const { v, l, t, f, x } = content;
  if (typeof v !== 'string' || typeof l !== 'string' || typeof t !== 'string' || typeof f !== 'string') {
    throw new SealedError('content');
  }
  const opened: OpenedEntry = { id: entry.id, key: entry.key, value: v, label: l, type: t, format: f };

  if (t === 'file' || x !== undefined) {
    const file = x as { n?: unknown; m?: unknown; s?: unknown; k?: unknown } | undefined;
    let fileKey: Uint8Array<ArrayBuffer> | undefined;
    try {
      fileKey = typeof file?.k === 'string' ? fromBase64(file.k) : undefined;
    } catch {
      fileKey = undefined;
    }
    if (
      t !== 'file' ||
      v !== '' ||
      !file ||
      typeof file.n !== 'string' ||
      file.n === '' ||
      typeof file.m !== 'string' ||
      !isSize(file.s) ||
      file.s > SEALED_FILE_MAX ||
      !fileKey ||
      fileKey.length !== KEY_LENGTH
    ) {
      throw new SealedError('content');
    }
    const meta = { name: file.n, mime: file.m, size: file.s };
    const key = fileKey;
    opened.file = {
      ...meta,
      open: async (blob) => openSealedFile(blob instanceof Uint8Array ? blob : new Uint8Array(await blob.arrayBuffer()), key, meta.size, workspace, entry.id),
    };
  }
  return opened;
}

function bitLength(n: number): number {
  return n <= 0 ? 0 : 32 - Math.clz32(n);
}

export function sealedFilePadded(size: number): number {
  if (size <= 1024) return 1024;
  const e = bitLength(size) - 1;
  const s = bitLength(e);
  const step = 2 ** (e - s);
  return Math.ceil(size / step) * step;
}

function blobLength(size: number): number {
  const padded = sealedFilePadded(size);
  return 1 + 16 + padded + Math.ceil(padded / FILE_SEGMENT) * TAG;
}

export async function openSealedFile(
  blob: Uint8Array<ArrayBuffer>,
  fileKey: Uint8Array<ArrayBuffer>,
  size: number,
  workspace: string,
  record: string,
): Promise<Uint8Array> {
  if (blob.length !== blobLength(size) || blob[0] !== FORMAT) throw new SealedError('format');
  const salt = blob.subarray(1, 17);
  const segmentKey = await hkdf(fileKey, sealContext('revoked-file-v1', [workspace, record, salt]));
  const key = await crypto.subtle.importKey('raw', segmentKey, { name: 'AES-GCM' }, false, ['decrypt']);
  const out = new Uint8Array(sealedFilePadded(size));
  const sealedSegment = FILE_SEGMENT + TAG;
  let at = 17;
  let written = 0;
  for (let index = 0; ; index++) {
    const last = blob.length - at <= sealedSegment;
    const end = last ? blob.length : at + sealedSegment;
    const nonce = new Uint8Array(12);
    const view = new DataView(nonce.buffer);
    view.setUint32(3, Math.floor(index / 2 ** 32));
    view.setUint32(7, index % 2 ** 32);
    nonce[11] = last ? 1 : 0;
    let plain: Uint8Array;
    try {
      plain = new Uint8Array(
        await crypto.subtle.decrypt(
          { name: 'AES-GCM', iv: nonce, additionalData: new Uint8Array([FORMAT]), tagLength: 128 },
          key,
          blob.subarray(at, end),
        ),
      );
    } catch {
      throw new SealedError('format');
    }
    if (written + plain.length > out.length) throw new SealedError('length');
    out.set(plain, written);
    written += plain.length;
    if (last) break;
    at = end;
  }
  if (written !== out.length) throw new SealedError('length');
  for (let i = size; i < out.length; i++) if (out[i] !== 0) throw new SealedError('padding');
  return out.subarray(0, size);
}
