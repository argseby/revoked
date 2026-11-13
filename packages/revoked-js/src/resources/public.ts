import { jsonBody } from '../core/body.js';
import type { ClientContext } from '../core/context.js';
import { path } from '../core/context.js';
import { RevokedError } from '../core/errors.js';
import type { CallOptions } from '../core/transport.js';
import { signChallenge, type IdentityKey } from '../identity/keys.js';
import type { AttestationVerdict, Download, OpenedShare, RequestPreview, SharePreview } from '../models.js';
import { download } from './shares.js';

/** An identity to prove, with an optional token from an earlier handshake with the same share. */
export interface ProvenIdentity {
  id: string;
  key: IdentityKey;
  handshakeToken?: string;
}

export interface OpenShareOptions extends CallOptions {
  password?: string;
  /** Required when the preview reports `requireHandshake`. */
  identity?: ProvenIdentity;
}

export interface SubmitAnswerOptions extends CallOptions {
  /** Answers keyed by template key. */
  data?: Record<string, unknown>;
  /** Answers given as references to the responder's own records, so the requester keeps reading their current value. */
  mappings?: Record<string, string>;
  senderName?: string;
  identifier?: string;
  password?: string;
  identity?: ProvenIdentity;
}

export interface SubmittedAnswer {
  [field: string]: unknown;
  handshakeToken?: string;
}

const NONCE = /^[A-Za-z0-9_-]{16,256}$/;
const HANDSHAKE_REFUSALS = new Set(['handshake_invalid', 'handshake_failed', 'challenge_invalid']);

type Scope = 'link' | 'request' | 'attestation' | 'reissue';

export async function proveIdentity(
  ctx: ClientContext,
  scope: Scope,
  slug: string,
  identity: { id: string; key: IdentityKey },
  options: CallOptions = {},
): Promise<{ identityId: string; challengeNonce: string; challengeSignature: string }> {
  const { nonce } = await ctx.transport.request<{ nonce: string }>(path`api/challenges/${scope}/${slug}`, {
    query: { identityId: identity.id },
    anonymous: true,
    signal: options.signal,
  });
  if (typeof nonce !== 'string' || !NONCE.test(nonce)) {
    throw new RevokedError({ status: 0, code: 'challenge_invalid', message: 'The server sent a malformed challenge.' });
  }
  return { identityId: identity.id, challengeNonce: nonce, challengeSignature: await signChallenge(identity.key, nonce) };
}

/** Calls where the slug or token in the address is the only key. */
export class Public {
  readonly links: PublicLinks;
  readonly requests: PublicRequests;
  readonly invites: PublicInvites;
  readonly attestations: PublicAttestations;

  constructor(ctx: ClientContext) {
    this.links = new PublicLinks(ctx);
    this.requests = new PublicRequests(ctx);
    this.invites = new PublicInvites(ctx);
    this.attestations = new PublicAttestations(ctx);
  }
}

export class PublicLinks {
  constructor(private readonly ctx: ClientContext) {}

  /** What stands between the caller and the share. Consumes no view. */
  preview(slug: string, options: CallOptions = {}): Promise<SharePreview> {
    return this.ctx.transport.request(path`api/public/links/${slug}`, { anonymous: true, signal: options.signal });
  }

  /**
   * The share's current values. **Consumes one view**, atomically, and is
   * never retried. With an identity, proves it first; a refused handshake
   * token is replaced by a fresh signature once.
   */
  async open(slug: string, options: OpenShareOptions = {}): Promise<OpenedShare> {
    const attempt = async (useToken: boolean) => {
      let proof: Record<string, string> = {};
      if (options.identity) {
        proof =
          useToken && options.identity.handshakeToken
            ? { identityId: options.identity.id, handshakeToken: options.identity.handshakeToken }
            : await proveIdentity(this.ctx, 'link', slug, options.identity, options);
      }
      const res = await this.ctx.transport.raw<OpenedShare>(path`api/public/links/${slug}`, {
        method: 'POST',
        body: jsonBody({ password: options.password, ...proof }),
        anonymous: true,
        idempotent: false,
        signal: options.signal,
      });
      const token = res.headers.get('X-Handshake-Token');
      return token ? { ...res.data, handshakeToken: token } : res.data;
    };
    try {
      return await attempt(true);
    } catch (error) {
      if (options.identity?.handshakeToken && error instanceof RevokedError && HANDSHAKE_REFUSALS.has(error.code)) {
        return attempt(false);
      }
      throw error;
    }
  }

  /** A shared file's bytes. The token is single use and lasts two minutes. */
  file(slug: string, recordId: string, downloadToken: string, options: CallOptions = {}): Promise<Download> {
    return download(this.ctx, path`api/public/links/${slug}/files/${recordId}`, {
      ...options,
      anonymous: true,
      query: { dl: downloadToken },
    });
  }

  /** Every shared file as one zip. The token is single use and lasts two minutes. */
  archive(slug: string, archiveToken: string, options: CallOptions = {}): Promise<Download> {
    return download(this.ctx, path`api/public/links/${slug}/archive`, {
      ...options,
      anonymous: true,
      query: { dl: archiveToken },
    });
  }

  /**
   * The share in a machine format. Consumes a view like `open`. A share that
   * requires a password or a handshake must be read with `open`.
   */
  async export(slug: string, format: 'json' | 'csv' | 'txt' | 'vcf' | 'ics', options: CallOptions = {}): Promise<string> {
    return this.ctx.transport.request<string>(`${path`s/${slug}`}.${format}`, {
      anonymous: true,
      responseType: 'text',
      idempotent: false,
      signal: options.signal,
    });
  }
}

export class PublicRequests {
  constructor(private readonly ctx: ClientContext) {}

  /** What the request asks for, and who is asking. */
  preview(slug: string, options: CallOptions = {}): Promise<RequestPreview> {
    return this.ctx.transport.request(path`api/public/requests/${slug}`, { anonymous: true, signal: options.signal });
  }

  /**
   * Answers a request. Takes a session: the answer becomes a grant in the
   * responder's own workspace, which they can update or revoke. Answering
   * again from the same account updates the earlier answer.
   */
  async submit(slug: string, options: SubmitAnswerOptions = {}): Promise<SubmittedAnswer> {
    if (this.ctx.transport.credentialKind !== 'session') {
      throw new RevokedError({
        status: 0,
        code: 'request_account_required',
        message: 'Answering a request takes a session credential.',
      });
    }
    const { identity, signal, ...fields } = options;
    const attempt = async (useToken: boolean) => {
      let proof: Record<string, string> = {};
      if (identity) {
        proof =
          useToken && identity.handshakeToken
            ? { identityId: identity.id, handshakeToken: identity.handshakeToken }
            : await proveIdentity(this.ctx, 'request', slug, identity, { signal });
      }
      const res = await this.ctx.transport.raw<SubmittedAnswer>(path`api/public/requests/${slug}`, {
        method: 'POST',
        body: jsonBody({ ...fields, ...proof }),
        signal,
      });
      const token = res.headers.get('X-Handshake-Token');
      return token ? { ...res.data, handshakeToken: token } : res.data;
    };
    try {
      return await attempt(true);
    } catch (error) {
      if (identity?.handshakeToken && error instanceof RevokedError && HANDSHAKE_REFUSALS.has(error.code)) {
        return attempt(false);
      }
      throw error;
    }
  }

  /**
   * Answers a request held on another server through the responder's own
   * server, where the answer stays.
   */
  async submitRemote(
    input: { origin: string; slug: string } & Omit<SubmitAnswerOptions, 'identity'> & { identity?: { id: string; key: IdentityKey } },
  ): Promise<{ ok: boolean; linkId: string; responseId: string; server: string; completed: boolean; updated: boolean }> {
    const { identity, signal, origin, slug, ...fields } = input;
    let proof: Record<string, string> = {};
    if (identity) {
      const { nonce } = await this.ctx.transport.request<{ nonce: string }>(
        new URL(path`api/challenges/request/${slug}`, origin.endsWith('/') ? origin : `${origin}/`).toString(),
        { query: { identityId: identity.id }, anonymous: true, signal },
      );
      if (!NONCE.test(nonce)) {
        throw new RevokedError({ status: 0, code: 'challenge_invalid', message: 'The server sent a malformed challenge.' });
      }
      proof = { identityId: identity.id, challengeNonce: nonce, challengeSignature: await signChallenge(identity.key, nonce) };
    }
    return this.ctx.transport.request('api/requests/remote', {
      method: 'POST',
      body: jsonBody({ origin, slug, ...fields, ...proof }),
      signal,
    });
  }
}

export class PublicInvites {
  constructor(private readonly ctx: ClientContext) {}

  get(token: string, options: CallOptions = {}): Promise<Record<string, unknown>> {
    return this.ctx.transport.request(path`api/public/invites/${token}`, { anonymous: true, signal: options.signal });
  }

  /** Joins the workspace. Takes a session. */
  accept(
    token: string,
    options: CallOptions = {},
  ): Promise<{ ok: boolean; workspace: string; membership: string; permissions: string[]; features: string[] }> {
    return this.ctx.transport.request(path`api/public/invites/${token}`, { method: 'POST', signal: options.signal });
  }
}

export class PublicAttestations {
  constructor(private readonly ctx: ClientContext) {}

  /** An attestation offer, before it is claimed. */
  offer(token: string, options: CallOptions = {}): Promise<Record<string, unknown>> {
    return this.ctx.transport.request(path`api/attestations/offers/${token}`, { anonymous: true, signal: options.signal });
  }

  /** Checks a presentation for the given audience and nonce. Always answers; read the verdict. */
  verify(input: { presentation: string; audience: string; nonce: string }, options: CallOptions = {}): Promise<AttestationVerdict> {
    return this.ctx.transport.request('api/attestations/verify', {
      method: 'POST',
      body: input,
      anonymous: true,
      signal: options.signal,
    });
  }

  /** The issuer's status list, as `application/statuslist+jwt`. */
  statusList(options: CallOptions = {}): Promise<string> {
    return this.ctx.transport.request('api/attestations/status', { anonymous: true, responseType: 'text', signal: options.signal });
  }

  /** A shared credential, as whoever holds its link sees it. */
  share(token: string, options: CallOptions = {}): Promise<AttestationVerdict> {
    return this.ctx.transport.request(path`api/public/attestation-shares/${token}`, { anonymous: true, signal: options.signal });
  }

  /** Who is asking for a credential, before it is presented. */
  check(id: string, options: CallOptions = {}): Promise<{ asker: unknown; expiresAt: string; server: unknown }> {
    return this.ctx.transport.request(path`api/public/attestation-checks/${id}`, { anonymous: true, signal: options.signal });
  }

  answerCheck(input: { presentation: string; state: string }, options: CallOptions = {}): Promise<{ state: string }> {
    return this.ctx.transport.request('api/public/attestation-checks/answer', {
      method: 'POST',
      body: input,
      anonymous: true,
      signal: options.signal,
    });
  }
}
