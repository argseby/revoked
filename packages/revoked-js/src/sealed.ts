import type { PublicLinks, OpenShareOptions } from './resources/public.js';
import type { OpenedShare, SharedRecord } from './models.js';
import { linkKeyFrom, openSealedEntry, SealedError, type OpenedEntry } from './sealed/index.js';

export { linkKeyFrom, openSealedEntry, sealContext, sealedFilePadded, SealedError, SEALED_FILE_MAX } from './sealed/index.js';
export type { OpenedEntry, SealedFile } from './sealed/index.js';

export interface OpenedSealedShare extends OpenedShare {
  /** Every encrypted entry the link key opened. */
  opened: OpenedEntry[];
  /** Encrypted entries the share has not caught up with yet, or that did not open. */
  failed: { entry: SharedRecord; error: SealedError }[];
}

/**
 * Opens a share from its full address, `https://<server>/s/<slug>#k=…`, and
 * decrypts its encrypted entries with the key after `#`, which never reaches
 * the server. Consumes one view.
 */
export async function openSealedShare(
  links: PublicLinks,
  address: string,
  options: OpenShareOptions = {},
): Promise<OpenedSealedShare> {
  const url = new URL(address);
  const slug = /\/s\/([^/]+)$/.exec(url.pathname)?.[1];
  if (!slug) throw new TypeError('Not a share address.');
  const key = linkKeyFrom(url.hash);
  const share = await links.open(decodeURIComponent(slug), options);
  const opened: OpenedEntry[] = [];
  const failed: OpenedSealedShare['failed'] = [];
  for (const entry of share.records) {
    if (!entry.sealed) continue;
    try {
      opened.push(await openSealedEntry(entry, key));
    } catch (error) {
      if (!(error instanceof SealedError)) throw error;
      failed.push({ entry, error });
    }
  }
  return { ...share, opened, failed };
}
