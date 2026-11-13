import { jsonBody } from '../core/body.js';
import { Collection, ReadableCollection } from '../core/collection.js';
import type { ClientContext } from '../core/context.js';
import { path } from '../core/context.js';
import { onceHeader, type CallOptions } from '../core/transport.js';
import type {
  Attestation,
  AttestationInput,
  AttestationVerdict,
  Contact,
  ContactDelivery,
  ContactInput,
  Credential,
  Identity,
} from '../models.js';
import { exportPublicKeyPem, signChallenge, type IdentityKey } from '../identity/keys.js';

export interface IdentityInput {
  name?: string;
  /** SPKI PEM of a P-256 public key generated on this device. */
  publicKey: string;
}

/**
 * Identities: certificates the server issues over a public key. The private
 * key never leaves the device that generated it; only the public key is sent.
 */
export class Identities extends Collection<Identity, IdentityInput, { name?: string; isPrimary?: boolean }> {
  constructor(ctx: ClientContext) {
    super(ctx, 'identities');
  }

  /** Creates an identity over a key from `generateIdentityKey()`. */
  async createFromKey(key: IdentityKey, input: { name?: string } = {}, options?: CallOptions): Promise<Identity> {
    return this.create({ ...input, publicKey: await exportPublicKeyPem(key) }, options);
  }

  /** One-way: a revoked identity stays revoked, and its status endpoint keeps answering so. */
  revoke(id: string, reason?: string, options: CallOptions = {}): Promise<Identity> {
    return this.ctx.transport.request(`${this.base}/${encodeURIComponent(id)}`, {
      method: 'PATCH',
      body: jsonBody({ status: 'revoked', revokedReason: reason }),
      signal: options.signal,
      idempotent: true,
    });
  }
}

export interface CreatedAttestation {
  attestation: Attestation;
  /** The offer token for the subject. Shown once. */
  offerToken: string;
}

/** Statements this workspace signs about someone else's identity. */
export class Attestations extends Collection<Attestation, AttestationInput> {
  constructor(ctx: ClientContext) {
    super(ctx, 'attestations');
  }

  /** Use `createWithToken`: the offer token comes back once, in a header. */
  override async create(input: AttestationInput, options: CallOptions = {}): Promise<Attestation> {
    return (await this.createWithToken(input, options)).attestation;
  }

  async createWithToken(input: AttestationInput, options: CallOptions = {}): Promise<CreatedAttestation> {
    const res = await this.createRaw(input, options);
    return { attestation: res.data, offerToken: onceHeader(res.headers, 'X-Attestation-Token') };
  }

  /** The app address of an offer, which the subject opens to accept it. */
  offerLink(offerToken: string): string {
    return `revoked://a/${encodeURIComponent(this.ctx.transport.baseUrl.origin)}/${encodeURIComponent(offerToken)}`;
  }

  revoke(id: string, reason?: string, options: CallOptions = {}): Promise<Attestation> {
    return this.ctx.transport.request(`${this.base}/${encodeURIComponent(id)}`, {
      method: 'PATCH',
      body: jsonBody({ status: 'revoked', revokedReason: reason }),
      signal: options.signal,
      idempotent: true,
    });
  }
}

/** Credentials other servers issued to this account's identities. Session only. */
export class Credentials extends ReadableCollection<Credential> {
  constructor(ctx: ClientContext) {
    super(ctx, 'credentials');
  }

  /** Claims an attestation offer for one of the caller's identities, proving the key. */
  async claim(
    input: { token: string; identity: { id: string; key: IdentityKey }; origin?: string },
    options: CallOptions = {},
  ): Promise<Credential> {
    const { nonce } = await this.ctx.transport.request<{ nonce: string }>(path`api/challenges/attestation/${input.token}`, {
      query: { identityId: input.identity.id },
      signal: options.signal,
      anonymous: true,
    });
    return this.ctx.transport.request('api/credentials/claim', {
      method: 'POST',
      body: jsonBody({
        origin: input.origin,
        token: input.token,
        identityId: input.identity.id,
        challengeNonce: nonce,
        challengeSignature: await signChallenge(input.identity.key, nonce),
      }),
      signal: options.signal,
    });
  }

  status(id: string, options: CallOptions = {}): Promise<AttestationVerdict> {
    return this.ctx.transport.request(path`api/credentials/${id}/status`, { signal: options.signal });
  }

  /** Has the issuer sign the credential again for a new identity of the same holder. */
  async reissue(
    id: string,
    input: { identity: { id: string; key: IdentityKey }; voucher: { payload: string; signature: string } },
    options: CallOptions = {},
  ): Promise<Credential> {
    const { nonce } = await this.ctx.transport.request<{ nonce: string }>(path`api/credentials/${id}/reissue`, {
      query: { identityId: input.identity.id },
      signal: options.signal,
    });
    return this.ctx.transport.request(path`api/credentials/${id}/reissue`, {
      method: 'POST',
      body: {
        identityId: input.identity.id,
        challengeNonce: nonce,
        challengeSignature: await signChallenge(input.identity.key, nonce),
        voucher: input.voucher,
      },
      signal: options.signal,
    });
  }

  async delete(id: string, options: CallOptions = {}): Promise<void> {
    await this.ctx.transport.request(`${this.base}/${encodeURIComponent(id)}`, {
      method: 'DELETE',
      responseType: 'none',
      signal: options.signal,
    });
  }
}

export interface AttestationCheck {
  id: string;
  expiresAt: string;
  present: Record<string, string>;
}

/** Asks someone to present a credential; answered once within ten minutes. Session only. */
export class AttestationChecks extends ReadableCollection<Record<string, unknown> & { id: string }> {
  constructor(ctx: ClientContext) {
    super(ctx, 'attestationChecks');
  }

  start(
    input: { type: string; issuers?: string[]; claims?: string[]; identityId: string; ref?: string },
    options: CallOptions = {},
  ): Promise<AttestationCheck> {
    return this.ctx.transport.request('api/attestation-checks', {
      method: 'POST',
      body: jsonBody(input),
      signal: options.signal,
    });
  }
}

export interface AttestationShare {
  id: string;
  audience: string;
  nonce: string;
  expiresAt: string;
}

/** A credential shown to whoever holds a link, with chosen claims disclosed. Session only. */
export class AttestationShares {
  constructor(private readonly ctx: ClientContext) {}

  create(input: { credential: string; days: number }, options: CallOptions = {}): Promise<AttestationShare> {
    return this.ctx.transport.request('api/attestation-shares', { method: 'POST', body: input, signal: options.signal });
  }

  /** Activates with a presentation bound to the share's audience and nonce. The token is shown once. */
  activate(
    id: string,
    presentation: string,
    options: CallOptions = {},
  ): Promise<{ id: string; token: string; url: string; expiresAt: string; disclosed: string[] }> {
    return this.ctx.transport.request(path`api/attestation-shares/${id}/activate`, {
      method: 'POST',
      body: { presentation },
      signal: options.signal,
    });
  }

  revoke(id: string, options: CallOptions = {}): Promise<{ id: string; status: string }> {
    return this.ctx.transport.request(path`api/attestation-shares/${id}/revoke`, {
      method: 'POST',
      signal: options.signal,
      idempotent: true,
    });
  }
}

/** People and servers this workspace shares with. `send`, `ask` and `deliver` take a session. */
export class Contacts extends Collection<Contact, ContactInput> {
  constructor(ctx: ClientContext) {
    super(ctx, 'contacts', { bindUser: false });
  }

  /** Shares records with a contact, delivered by the best channel available. */
  send(
    id: string,
    input: { records?: string[]; sections?: string[]; label?: string; expiresAt?: string | Date; maxViews?: number },
    options: CallOptions = {},
  ): Promise<ContactDelivery> {
    return this.ctx.transport.request(path`api/contacts/${id}/send`, {
      method: 'POST',
      body: jsonBody(input),
      signal: options.signal,
    });
  }

  /** Asks a contact for data with a template. */
  ask(
    id: string,
    input: { label?: string; identity?: string; template?: string; expiresAt?: string | Date; maxResponses?: number },
    options: CallOptions = {},
  ): Promise<ContactDelivery> {
    return this.ctx.transport.request(path`api/contacts/${id}/ask`, {
      method: 'POST',
      body: jsonBody(input),
      signal: options.signal,
    });
  }

  /** Delivers an existing share or request to a contact. */
  deliver(
    id: string,
    input: { kind: 'share' | 'request'; id: string; locale?: string },
    options: CallOptions = {},
  ): Promise<ContactDelivery> {
    return this.ctx.transport.request(path`api/contacts/${id}/deliver`, {
      method: 'POST',
      body: jsonBody(input),
      signal: options.signal,
    });
  }
}
