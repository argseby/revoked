import { jsonBody } from '../core/body.js';
import { ReadableCollection } from '../core/collection.js';
import type { ClientContext } from '../core/context.js';
import { path } from '../core/context.js';
import type { CallOptions } from '../core/transport.js';
import type { Connection, LinkStatus, RequestStatus, SignIn } from '../models.js';

export interface ConnectionPermissions {
  allowRevoke?: boolean;
  allowHandOver?: boolean;
  allowVaultRead?: boolean;
  /** Permission keys from `server.permissions()`. */
  permissions?: string[];
  /** Give the tool a section of its own. */
  section?: boolean;
  /** Further sections the tool may reach. */
  sections?: string[];
}

/** Tools connected to the signed-in person's workspace, as the owner manages them. Session only. */
export class Connections extends ReadableCollection<Connection> {
  constructor(ctx: ClientContext) {
    super(ctx, 'connections');
  }

  setPermissions(id: string, input: ConnectionPermissions, options: CallOptions = {}): Promise<Connection> {
    return this.ctx.transport.request(path`api/connections/${id}/permissions`, {
      method: 'POST',
      body: jsonBody(input),
      signal: options.signal,
      idempotent: true,
    });
  }

  pause(id: string, options: CallOptions = {}): Promise<{ paused: boolean }> {
    return this.ctx.transport.request(path`api/connections/${id}/pause`, {
      method: 'POST',
      signal: options.signal,
      idempotent: true,
    });
  }

  resume(id: string, options: CallOptions = {}): Promise<{ paused: boolean }> {
    return this.ctx.transport.request(path`api/connections/${id}/resume`, {
      method: 'POST',
      signal: options.signal,
      idempotent: true,
    });
  }

  /** Ends the connection. `revokeLinks` also revokes the shares the tool created. */
  async disconnect(id: string, input: { revokeLinks?: boolean } = {}, options: CallOptions = {}): Promise<void> {
    await this.ctx.transport.request(path`api/connections/${id}/disconnect`, {
      method: 'POST',
      body: jsonBody(input),
      responseType: 'none',
      signal: options.signal,
      idempotent: true,
    });
  }

  /** A draft of values a tool prepared for a proposal. */
  draft(id: string, options: CallOptions = {}): Promise<{ id: string; values: Record<string, string>; expiresAt: string }> {
    return this.ctx.transport.request(path`api/connections/drafts/${id}`, { signal: options.signal });
  }

  async discardDraft(id: string, options: CallOptions = {}): Promise<void> {
    await this.ctx.transport.request(path`api/connections/drafts/${id}`, {
      method: 'DELETE',
      responseType: 'none',
      signal: options.signal,
    });
  }
}

/** Services the signed-in person signed in to with Revoked. Session only. */
export class SignIns extends ReadableCollection<SignIn> {
  constructor(ctx: ClientContext) {
    super(ctx, 'signIns');
  }

  pause(id: string, options: CallOptions = {}): Promise<SignIn> {
    return this.ctx.transport.request(path`api/sign-ins/${id}/pause`, { method: 'POST', signal: options.signal, idempotent: true });
  }

  resume(id: string, options: CallOptions = {}): Promise<SignIn> {
    return this.ctx.transport.request(path`api/sign-ins/${id}/resume`, { method: 'POST', signal: options.signal, idempotent: true });
  }

  /** `newId` makes the service see a different account id on the next sign-in. */
  disconnect(id: string, input: { newId?: boolean } = {}, options: CallOptions = {}): Promise<{ status: string; newIdOnReturn: boolean }> {
    return this.ctx.transport.request(path`api/sign-ins/${id}/disconnect`, {
      method: 'POST',
      body: jsonBody(input),
      signal: options.signal,
      idempotent: true,
    });
  }
}

// ---------------------------------------------------------------- the tool's own side

export interface ToolLink {
  id: string;
  ref: string;
  label: string;
  status: LinkStatus;
  viewCount: number;
  maxViews: number;
  expiresAt: string;
  created: string;
  handedOver: boolean;
  /** Only while handed over and active. */
  url?: string;
}

export interface ToolRequest {
  id: string;
  ref: string;
  label: string;
  status: RequestStatus;
  responseCount: number;
  maxResponses: number;
  expiresAt: string;
  created: string;
  /** The `revoked://r/…` address, in the answer that created it. */
  url?: string;
}

export interface ToolAttestation {
  id: string;
  ref: string;
  type: string;
  label: string;
  status: string;
  subjectName: string;
  subjectFingerprint: string;
  subjectDomain: string;
  expiresAt: string;
  issuedAt: string;
  created: string;
}

export interface ToolCheck {
  id: string;
  ref: string;
  type: string;
  status: string;
  expiresAt: string;
  answeredAt: string;
  created: string;
  [field: string]: unknown;
}

export interface ConnectionStatus {
  id: string;
  clientId: string;
  clientName: string;
  expiresAt: string;
  allowRevoke: boolean;
  allowHandOver: boolean;
  permissions: string[];
  vaultAccess: string;
  section: string;
  sections: string[];
  allowVaultRead: boolean;
  /** Whether this token reaches the whole vault; never one collected by polling. */
  vaultReadable: boolean;
  links: ToolLink[];
  requests: ToolRequest[];
  attestations: ToolAttestation[];
  checks: ToolCheck[];
}

/** What a connected tool does with its own token (`connection` credential). */
export class ToolConnection {
  readonly links: {
    create: (
      input: { label: string; records?: string[]; sections?: string[]; expiresAt?: string | Date; maxViews?: number; ref?: string },
      options?: CallOptions,
    ) => Promise<ToolLink>;
    revoke: (id: string, options?: CallOptions) => Promise<ToolLink>;
  };
  readonly requests: {
    create: (
      input: { label: string; template?: string; identity?: string; expiresAt?: string | Date; maxResponses?: number; ref?: string },
      options?: CallOptions,
    ) => Promise<ToolRequest>;
    close: (id: string, options?: CallOptions) => Promise<ToolRequest>;
  };
  readonly attestations: {
    revoke: (id: string, options?: CallOptions) => Promise<ToolAttestation>;
  };

  constructor(private readonly ctx: ClientContext) {
    const post = <T>(url: string, body: unknown, options: CallOptions = {}, idempotent = false) =>
      this.ctx.transport.request<T>(url, {
        method: 'POST',
        ...(body === undefined ? {} : { body }),
        signal: options.signal,
        idempotent,
      });
    this.links = {
      create: (input, options) => post('api/connection/links', jsonBody(input), options),
      revoke: (id, options) => post(path`api/connection/links/${id}/revoke`, undefined, options, true),
    };
    this.requests = {
      create: (input, options) => post('api/connection/requests', jsonBody(input), options),
      close: (id, options) => post(path`api/connection/requests/${id}/close`, undefined, options, true),
    };
    this.attestations = {
      revoke: (id, options) => post(path`api/connection/attestations/${id}/revoke`, undefined, options, true),
    };
  }

  /** The connection, its reach, and what became of everything it proposed. */
  status(options: CallOptions = {}): Promise<ConnectionStatus> {
    return this.ctx.transport.request('api/connection', { signal: options.signal });
  }

  /**
   * Holds values for a proposal for up to an hour, so a `revoked://p` link
   * can name them by id instead of carrying them in the address.
   */
  draft(values: Record<string, string>, options: CallOptions = {}): Promise<{ id: string; expiresAt: string }> {
    return this.ctx.transport.request('api/connection/drafts', {
      method: 'POST',
      body: { values },
      signal: options.signal,
    });
  }

  /** Ends the connection from the tool's side. The token stops working at once. */
  async disconnect(options: CallOptions = {}): Promise<void> {
    await this.ctx.transport.request('api/connection', {
      method: 'DELETE',
      responseType: 'none',
      signal: options.signal,
      idempotent: true,
    });
  }
}
