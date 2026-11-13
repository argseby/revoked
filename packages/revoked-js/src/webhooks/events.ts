import type { KnownWebhookEventType } from '../generated/events.js';

export type WebhookEventType = KnownWebhookEventType | (string & {});

interface Data<O extends string> {
  object: O;
  id: string;
}

export interface LinkEventData extends Data<'link'> {
  status: string;
  /** `answer` for a grant given in answer to a request. */
  kind: 'share' | 'answer' | (string & {});
  request?: string;
  views?: number;
  deleted?: boolean;
  reason?: string;
}

export interface RequestEventData extends Data<'request'> {
  status: string;
  deleted?: boolean;
}

export interface ResponseEventData extends Data<'response'> {
  request: string;
  status: string;
  /** Set when the answer is kept on the responder's own server. */
  server?: string;
}

export interface RecordEventData extends Data<'record'> {
  key: string;
}

export interface AttestationEventData extends Data<'attestation'> {
  type: string;
  status: string;
}

export interface IdentityEventData extends Data<'identity'> {
  fingerprint: string;
  status: string;
}

export interface MemberEventData extends Data<'member'> {
  user: string;
  permissions: string[];
}

export interface ApiKeyEventData extends Data<'apikey'> {
  user: string;
}

export interface ConnectionEventData extends Data<'connection'> {
  clientId: string;
}

interface DataByPrefix {
  link: LinkEventData;
  request: RequestEventData;
  response: ResponseEventData;
  record: RecordEventData;
  attestation: AttestationEventData;
  identity: IdentityEventData;
  member: MemberEventData;
  apikey: ApiKeyEventData;
  connection: ConnectionEventData;
}

type DataFor<T extends string> = T extends `${infer P}.${string}` ? (P extends keyof DataByPrefix ? DataByPrefix[P] : never) : never;

interface Envelope<T extends string, D> {
  /** The same on every delivery and resend of this event: drop repeats by it. */
  id: string;
  type: T;
  /** RFC 3339. Deliveries can arrive out of order; order by this. */
  created: string;
  workspace: string;
  data: D;
  test?: boolean;
}

export type KnownWebhookEvent = { [T in KnownWebhookEventType]: Envelope<T, DataFor<T>> }[KnownWebhookEventType];

/** An event of a type this SDK version does not know yet. */
export type UnknownWebhookEvent = Envelope<string, { object: string; id: string; [field: string]: unknown }>;

/**
 * A webhook delivery's body; narrow on `type`. A newer server can send a type
 * this SDK version does not list: handle it in a `default` branch, where
 * `isKnownWebhookEvent` tells the two apart.
 */
export type WebhookEvent = KnownWebhookEvent;

/** A request callback's submission body. Callbacks are unsigned and sent at most once. */
export interface RequestCallbackSubmission {
  requestId: string;
  slug: string;
  responseId: string;
  linkId: string;
  identity: string;
  identifier: string;
  senderName: string;
  data: Record<string, unknown>;
  server?: string;
}

/** A request callback's later event. Retried until delivered. */
export interface RequestCallbackEvent {
  event: 'grant.changed' | 'grant.revoked' | 'grant.expired' | (string & {});
  requestId: string;
  slug: string;
  responseId: string;
  linkId: string;
  status: string;
  at: string;
  server?: string;
}
