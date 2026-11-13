/** A string union that still accepts values a newer server introduces. */
export type Open<T extends string> = T | (string & {});

export interface BaseRecord {
  id: string;
  collectionId?: string;
  collectionName?: string;
  created: string;
  updated: string;
}

export type Audience = Open<'private' | 'workspace' | 'groups'>;

export interface AudienceFields {
  audienceKind?: Audience;
  audienceGroups?: string[];
  editing?: boolean;
}

// ---------------------------------------------------------------- server

export interface ServerInfo {
  domain: string;
  version: string;
  fingerprint: string;
  publicKey: string;
  /** Root-signed; verify with `verifyServerAssertion` from `@kiunke.dev/revoked/trust`. */
  assertion: {
    body: { domain: string; publicKey: string; fingerprint: string; issuedAt: number; expiresAt: number };
    signature: string;
  };
  txt: { host: string; value: string };
  mail?: { recipients: Open<'off' | 'same-domain' | 'trusted' | 'all'> };
  limits?: { maxFileSize?: number };
  attestations?: { issuing?: boolean };
  twoFactor?: { required?: boolean };
  signups?: { open?: boolean; verifyEmail?: boolean };
  sealing?: { records?: boolean };
}

export interface Permission {
  key: string;
  label: string;
  description: string;
  destructive: boolean;
  membersOnly: boolean;
  scopes: string[];
}

export interface Feature {
  key: string;
  label: string;
  description: string;
  permission: string;
  defaultOn: boolean;
}

export interface FeaturePreset {
  key: string;
  label: string;
  description: string;
  permissions: string[];
  features: string[];
}

export interface ServerCertificate {
  certificate: string;
  publicKey: string;
  domain: string;
}

export interface IdentityCertificate {
  id: string;
  name: string;
  certificate: string;
  fingerprint: string;
  parentSignature: string;
  domainAtIssue: string;
}

// ---------------------------------------------------------------- shares

export type LinkStatus = Open<'active' | 'paused' | 'revoked' | 'expired'>;

export interface Link extends BaseRecord, AudienceFields {
  slug: string;
  label: string;
  user: string;
  workspace: string;
  records: string[];
  sections: string[];
  status: LinkStatus;
  expiresAt: string;
  maxViews: number;
  viewCount: number;
  identity: string;
  requireHandshake: boolean;
  watermark: boolean;
  watermarkText: string;
  purpose: Open<'' | 'application'>;
  /** Set on an answer to a request. */
  request: string;
  connection: string;
  ref: string;
  handedOver: boolean;
  sealedEntries?: number;
}

export interface LinkInput extends AudienceFields {
  label: string;
  /** The address part after `/s/`. Default: 24 random characters; anything shorter is guessable. */
  slug?: string;
  status?: LinkStatus;
  records?: string[];
  sections?: string[];
  /** Stored hashed; never returned. */
  password?: string;
  expiresAt?: string | Date;
  maxViews?: number;
  /** An identity of the caller's own; the server refuses a foreign one. */
  identity?: string;
  requireHandshake?: boolean;
  watermark?: boolean;
  watermarkText?: string;
  purpose?: Open<'' | 'application'>;
}

// ---------------------------------------------------------------- requests

export type RequestStatus = Open<'active' | 'paused' | 'revoked' | 'expired' | 'completed'>;

export interface RevokedRequest extends BaseRecord, AudienceFields {
  slug: string;
  label: string;
  status: RequestStatus;
  identity: string;
  template: string;
  expiresAt: string;
  maxResponses: number;
  responseCount: number;
  identifier: string;
  callbackUrl: string;
  requireHandshake: boolean;
  identityScope: Open<'any' | 'from_root'>;
  allowExtraFields: boolean;
  user: string;
  workspace: string;
  connection: string;
  ref: string;
}

export interface RequestInput extends AudienceFields {
  label: string;
  /** Default: 24 random characters; anything shorter is guessable. */
  slug?: string;
  status?: RequestStatus;
  /** A template id. */
  template?: string;
  /** The identity the request asks as. Default: the workspace's primary identity. */
  identity?: string;
  password?: string;
  expiresAt?: string | Date;
  maxResponses?: number;
  /** A label for the identifier the responder must give, e.g. "Order number". */
  identifier?: string;
  callbackUrl?: string;
  requireHandshake?: boolean;
  identityScope?: Open<'any' | 'from_root'>;
  allowExtraFields?: boolean;
}

/** One answer to a request, as `GET /api/requests/{id}/links` reports it. */
export interface RequestResponse {
  id: string;
  slug: string;
  status: LinkStatus;
  data: Record<string, unknown>;
  senderName: string;
  identifier: string;
  identity: string;
  identityName: string;
  identityDomain: string;
  /** Kept on the responder's own server and fetched from there. */
  remote: boolean;
  live: boolean;
  created: string;
  [field: string]: unknown;
}

export interface TemplateItem {
  key: string;
  label?: string;
  type?: string;
  format?: string;
  required?: boolean;
  reason?: string;
  records?: TemplateItem[];
}

export interface Template extends BaseRecord, AudienceFields {
  name: string;
  description: string;
  schema: TemplateItem[];
  workspace: string;
  user: string;
}

export interface TemplateInput extends AudienceFields {
  name?: string;
  description?: string;
  schema?: TemplateItem[];
}

// ---------------------------------------------------------------- vault

export type RecordType = Open<'text' | 'number' | 'url' | 'boolean' | 'datetime' | 'file'>;
export type RecordFormat = Open<'default' | 'hidden'>;

/** A vault record as a signed-in person sees it through the `records` collection. */
export interface VaultRecord extends BaseRecord, AudienceFields {
  key: string;
  value: string;
  label: string;
  type: RecordType;
  format: RecordFormat;
  user: string;
  workspace: string;
  aliasOf: string;
  file: string;
  filename: string;
  mime: string;
  size: number;
  contentHash: string;
  /** End-to-end encrypted: `value` is always empty. */
  sealed: boolean;
  writtenBy: string;
  writtenByName: string;
}

export interface VaultRecordInput extends AudienceFields {
  key: string;
  label: string;
  value?: string;
  /** Default `text`, or `file` with an upload. */
  type?: RecordType;
  /** Default `default`. */
  format?: RecordFormat;
  aliasOf?: string;
  filename?: string;
  file?: FileInput;
}

/** A record as an API key or connected tool sees it through `/api/vault`. */
export interface VaultEntry {
  id: string;
  key: string;
  label: string;
  type: RecordType;
  format: RecordFormat;
  updated: string;
  sections: string[];
  /** Written by this key or tool, so it may change it. */
  writable: boolean;
  writtenByName: string;
  value?: string;
  filename?: string;
  mime?: string;
  size?: number;
}

export interface VaultEntryInput {
  key: string;
  label?: string;
  type?: RecordType;
  format?: RecordFormat;
  value?: string;
  /** Section to write to: a tool's own section, or one of a key's sections. */
  section?: string;
  filename?: string;
  file?: FileInput;
}

export interface VaultEntryUpdate {
  label?: string;
  format?: RecordFormat;
  value?: string;
  filename?: string;
  file?: FileInput;
}

/** Bytes for an upload. A `File` keeps its own name unless `filename` is given. */
export type FileInput = Blob | Uint8Array<ArrayBuffer> | ArrayBuffer;

export interface Section extends BaseRecord, AudienceFields {
  key: string;
  name: string;
  records: string[];
  user: string;
  workspace: string;
  view: unknown;
}

export interface SectionInput extends AudienceFields {
  key?: string;
  name?: string;
  records?: string[];
  view?: unknown;
}

// ---------------------------------------------------------------- identities

export type IdentityStatus = Open<'active' | 'revoked'>;

export interface Identity extends BaseRecord {
  name: string;
  certificate: string;
  publicKey: string;
  fingerprint: string;
  parentSignature: string;
  domainAtIssue: string;
  isPrimary: boolean;
  status: IdentityStatus;
  revokedAt: string;
  revokedReason: string;
  user: string;
  workspace: string;
}

// ---------------------------------------------------------------- workspaces

export interface Workspace extends BaseRecord {
  name: string;
  slug: string;
  defaultAudience: Record<string, Audience>;
}

export interface WorkspaceMember extends BaseRecord {
  user: string;
  workspace: string;
  role: Open<'admin' | 'member'>;
  permissions: string[];
}

export interface Member {
  id: string;
  user: string;
  email: string;
  features: string[];
  role: Open<'admin' | 'member'>;
  permissions: Permission[];
  isSelf: boolean;
  isLastAdmin: boolean;
  joined: string;
}

export interface MemberList {
  members: Member[];
  grantable: Permission[];
  canManage: boolean;
}

export interface Invite extends BaseRecord {
  workspace: string;
  permissions: string[];
  features: string[];
  role: string;
  email: string;
  label: string;
  status: Open<'active' | 'revoked' | 'exhausted' | 'expired'>;
  expiresAt: string;
  maxUses: number;
  useCount: number;
}

export interface InviteInput {
  status?: Invite['status'];
  /** Permission keys from `server.permissions()`. */
  permissions?: string[];
  features?: string[];
  email?: string;
  label?: string;
  expiresAt?: string | Date;
  maxUses?: number;
}

export interface Group {
  id: string;
  key: string;
  name: string;
  members: { id: string; email: string }[];
}

// ---------------------------------------------------------------- contacts

export interface Contact extends BaseRecord, AudienceFields {
  name: string;
  user: string;
  email: string;
  peerDomain: string;
  peerFingerprint: string;
  trustState: string;
  verifiedAt: string;
  createdBy: string;
}

export interface ContactInput extends AudienceFields {
  name?: string;
  email?: string;
  peerDomain?: string;
  peerFingerprint?: string;
}

export interface ContactDelivery {
  ok: boolean;
  id: string;
  slug: string;
  kind: Open<'share' | 'request'>;
  channel: Open<'account' | 'email' | 'manual' | 'handed_over'>;
  delivered: boolean;
  emailed: boolean;
}

// ---------------------------------------------------------------- attestations

export interface Attestation extends BaseRecord, AudienceFields {
  type: string;
  label: string;
  claims: Record<string, unknown>;
  status: Open<'offered' | 'active' | 'revoked'>;
  expiresAt: string;
  offerExpiresAt: string;
  subjectFingerprint: string;
  subjectDomain: string;
  subjectName: string;
  issuedAt: string;
  revokedAt: string;
  revokedReason: string;
}

export interface AttestationInput extends AudienceFields {
  type?: string;
  label?: string;
  claims?: Record<string, unknown>;
  expiresAt?: string | Date;
  offerExpiresAt?: string | Date;
  subjectFingerprint?: string;
  subjectDomain?: string;
  subjectName?: string;
}

export interface Credential extends BaseRecord {
  identity: string;
  issuer: string;
  type: string;
  credential: string;
  claims: Record<string, unknown>;
  issuedAt: string;
  expiresAt: string;
}

export interface AttestationVerdict {
  [field: string]: unknown;
}

// ---------------------------------------------------------------- keys, tools, sign-ins

export interface ApiKey extends BaseRecord {
  label: string;
  user: string;
  workspace: string;
  scopes: string[];
  vaultAccess: Open<'' | 'read' | 'write'>;
  sections: string[];
  lastUsedAt: string;
  expiresAt: string;
}

export interface ApiKeyInput {
  label: string;
  /** Permission keys from `server.permissions()`; expanded to scopes by the server. */
  permissions?: string[];
  vaultAccess?: Open<'' | 'read' | 'write'>;
  /** The sections a vault permission reaches. */
  sections?: string[];
  expiresAt?: string | Date;
}

export interface Connection extends BaseRecord {
  user: string;
  workspace: string;
  clientId: string;
  clientName: string;
  allowVaultRead: boolean;
  scopes: string[];
  vaultAccess: Open<'' | 'read' | 'write'>;
  section: string;
  sections: string[];
  paused: boolean;
  expiresAt: string;
  lastUsedAt: string;
}

export interface SignIn extends BaseRecord {
  clientId: string;
  scopes: string[];
  link: string;
  status: Open<'active' | 'paused' | 'disconnected'>;
  lastSignInAt: string;
  newIdOnReturn: boolean;
}

export interface Notification extends BaseRecord {
  user: string;
  workspace: string;
  type: string;
  title: string;
  message: string;
  refCollection: string;
  refId: string;
  read: boolean;
}

// ---------------------------------------------------------------- webhooks

export interface WebhookEventTypeInfo {
  type: string;
  group: string;
  description: string;
  noisy?: boolean;
}

export interface WebhookEndpoint {
  id: string;
  url: string;
  description: string;
  events: string[];
  enabled: boolean;
  disabledReason: string;
  failingSince: string;
  created: string;
  stats?: Record<string, unknown>;
  series?: unknown[];
  /** Present only in the answer that created the endpoint. */
  secret?: string;
}

export interface WebhookEndpointInput {
  url?: string;
  description?: string;
  /** Event types, or `["*"]` for every type except the noisy ones. */
  events?: string[];
  enabled?: boolean;
}

export interface WebhookDelivery {
  id: string;
  endpoint: string;
  event: string;
  status: Open<'pending' | 'succeeded' | 'failed'>;
  attempts: number;
  lastStatus: number;
  lastError: string;
  nextAttemptAt: string;
  deliveredAt: string;
  created: string;
  type?: string;
  payload?: unknown;
  attemptLog?: unknown[];
}

export interface WebhookMetrics {
  range: string;
  [field: string]: unknown;
}

// ---------------------------------------------------------------- public side

export interface ServerClaim {
  domain: string;
  rootFingerprint: string;
}

export interface IdentityStatusAssertion {
  payload: string;
  signature: string;
}

/** The identity behind a share or request. Every field is a claim until verified with `trust`. */
export interface Sharer {
  identityId?: string;
  name?: string;
  fingerprint?: string;
  parentSignature?: string;
  domainAtIssue?: string;
  status?: IdentityStatus;
  statusAssertion?: IdentityStatusAssertion;
}

export interface SharePreview {
  slug: string;
  label: string;
  status: LinkStatus;
  requiresPassword: boolean;
  requireHandshake: boolean;
  watermarked: boolean;
  purpose: string;
  identity: string;
  sharer: Sharer;
  server: ServerClaim;
}

export interface SharedRecord {
  id: string;
  key?: string;
  value?: string;
  label?: string;
  name?: string;
  type?: RecordType;
  format?: RecordFormat;
  records?: string[];
  filename?: string;
  mime?: string;
  size?: number;
  contentHash?: string;
  created?: string;
  updated?: string;
  /** Single use, two minutes: pass to `public.links.file`. */
  downloadToken?: string;
  sealed?: boolean;
  unavailable?: boolean;
  sealedValue?: string;
  sealedVersion?: number;
  viewerWrap?: string;
}

export interface SharedSection {
  id: string;
  key: string;
  name: string;
  records: string[];
}

export interface OpenedShare {
  slug: string;
  label: string;
  purpose: string;
  identity: string;
  sections: SharedSection[];
  records: SharedRecord[];
  viewCount: number;
  watermark?: string;
  /** Single use, two minutes: pass to `public.links.archive`. */
  archiveToken?: string;
  /** Present after a handshake; reuse it to skip the next signature. */
  handshakeToken?: string;
}

export interface RequestPreview {
  label: string;
  status: RequestStatus;
  requiresPassword: boolean;
  requiresIdentifier: boolean;
  requireHandshake: boolean;
  allowExtraFields: boolean;
  identityScope: Open<'any' | 'from_root'>;
  template: TemplateItem[];
  requester: Sharer;
  server: ServerClaim;
}

export interface Download {
  blob: Blob;
  filename: string | undefined;
  contentType: string | undefined;
}
