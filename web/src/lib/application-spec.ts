export interface Link {
  id: string;
  slug: string;
  label: string;
  status: 'active' | 'paused' | 'revoked' | 'expired';
  expiresAt: string;
  viewCount: number;
  records: string[];
  watermarkText: string;
  purpose: string;
  identity: string;
  created: string;
}

// Links labelled by the spec's first draft carry this prefix; the landlord page
// already heads an application "Bewerbung · {label}", so new ones do not.
export const labelPrefix = 'Wohnungsbewerbung ';
export const stampPrefix = 'Nur für Wohnungsbewerbung ';
export const expiryChoices = [7, 14, 30] as const;
export const extendDays = 14;

// links.watermarkText holds at most 120 characters and a single line.
const maxStamp = 120;
export const maxAddress = maxStamp - stampPrefix.length;

const day = 86_400_000;

export function cleanAddress(input: string): string {
  return input.replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, maxAddress);
}

export function stampText(address: string): string {
  return stampPrefix + cleanAddress(address);
}

export function addressOf(link: Pick<Link, 'label'>): string {
  return link.label.startsWith(labelPrefix) ? link.label.slice(labelPrefix.length) : link.label;
}

// The tag the server prints after '#' in every stamp line.
export function watermarkTag(link: Pick<Link, 'id'>): string {
  return link.id.slice(0, 6);
}

export interface ApplicationDraft {
  address: string;
  recordIds: string[];
  expiryDays: number;
  identityId?: string;
  user: string;
  workspace: string;
  slug: string;
  now: Date;
}

// The exact body `create` posts. An application is always watermarked: the
// server refuses one that is not (application_needs_watermark).
export function applicationBody(d: ApplicationDraft): Record<string, unknown> {
  const address = cleanAddress(d.address);
  return {
    slug: d.slug,
    label: address,
    user: d.user,
    workspace: d.workspace,
    sections: [],
    records: d.recordIds,
    status: 'active',
    watermark: true,
    watermarkText: stampText(address),
    expiresAt: new Date(d.now.getTime() + d.expiryDays * day).toISOString(),
    requireHandshake: false,
    purpose: 'application',
    ...(d.identityId ? { identity: d.identityId } : {}),
  };
}

export interface ApplicationEdit {
  address: string;
  recordIds: string[];
  // 0 keeps the current expiry.
  expiryDays: number;
  identityId?: string;
  status: Link['status'];
  now: Date;
}

// The PATCH an edit sends. The watermark and purpose are never touched: an
// application stays stamped. A new expiry revives an expired link, as
// extending it would.
export function applicationUpdate(e: ApplicationEdit): Record<string, unknown> {
  const address = cleanAddress(e.address);
  return {
    label: address,
    watermarkText: stampText(address),
    records: e.recordIds,
    identity: e.identityId ?? '',
    ...(e.expiryDays > 0
      ? {
          expiresAt: new Date(e.now.getTime() + e.expiryDays * day).toISOString(),
          ...(e.status === 'expired' ? { status: 'active' } : {}),
        }
      : {}),
  };
}

export function extendedExpiry(current: string, now: Date, days = extendDays): string {
  const from = Math.max(now.getTime(), current ? new Date(current.replace(' ', 'T')).getTime() : 0);
  return new Date(from + days * day).toISOString();
}

function isLocalDomain(d: string): boolean {
  return (
    d === '' ||
    d === 'localhost' ||
    !d.includes('.') ||
    d.includes(':') ||
    /^\d+\.\d+\.\d+\.\d+$/.test(d) ||
    /\.(localhost|local|test|internal|lan)$/i.test(d)
  );
}

// The landlord gets a web link on the server's advertised domain, never the
// app's base URL or a revoked:// link (spec §8.1). A server on localhost or a
// LAN name is unreachable for them, which the UI says out loud.
export function landlordUrl(domain: string, apiBase: string, slug: string): { url: string; reachable: boolean } {
  const s = encodeURIComponent(slug);
  if (isLocalDomain(domain)) return { url: `${apiBase.replace(/\/+$/, '')}/s/${s}`, reachable: false };
  return { url: `https://${domain}/s/${s}`, reachable: true };
}
