import { ClientContext, type Me } from './core/context.js';
import { Transport, type CallOptions, type Credential, type RetryOptions } from './core/transport.js';
import { Grants, type GrantCache } from './resources/grants.js';
import { AttestationChecks, AttestationShares, Attestations, Contacts, Credentials, Identities } from './resources/identity.js';
import { Public } from './resources/public.js';
import { Server } from './resources/server.js';
import { Links, Requests, Templates } from './resources/shares.js';
import { Connections, SignIns, ToolConnection } from './resources/tools.js';
import { Records, Sections, Vault } from './resources/vault.js';
import { Webhooks } from './resources/webhooks.js';
import { ApiKeys, Groups, Invites, Members, Notifications, Workspaces } from './resources/workspace.js';

interface CommonOptions {
  /** The server's origin, e.g. `https://id.example.com`. */
  server: string | URL;
  /**
   * The workspace collection writes are bound to. Looked up from the
   * credential when left out.
   */
  workspace?: string;
  /** Defaults to the global `fetch`. */
  fetch?: typeof fetch;
  /** Per attempt. Default 30 000 ms; 0 disables it. */
  timeoutMs?: number;
  retry?: RetryOptions;
  headers?: Record<string, string>;
  /** Where `grants.resolve` keeps answers. Default: in memory, per client. */
  grantCache?: GrantCache;
}

/** Exactly one credential, or none for public calls only. */
export type RevokedOptions = CommonOptions &
  (
    | { apiKey: string; connection?: never; session?: never }
    | { connection: string; apiKey?: never; session?: never }
    | {
        /** A session token for a signed-in person. Refreshed automatically when it expires. */
        session: string;
        onSessionRefresh?: (token: string) => void | Promise<void>;
        apiKey?: never;
        connection?: never;
      }
    | { apiKey?: undefined; connection?: undefined; session?: undefined }
  );

function credentialOf(options: RevokedOptions): Credential | undefined {
  if (options.apiKey !== undefined) return { apiKey: options.apiKey };
  if (options.connection !== undefined) return { connection: options.connection };
  if (options.session !== undefined) {
    return 'onSessionRefresh' in options && options.onSessionRefresh
      ? { session: options.session, onSessionRefresh: options.onSessionRefresh }
      : { session: options.session };
  }
  return undefined;
}

/**
 * A client for one Revoked server.
 *
 * ```ts
 * const revoked = new Revoked({ server: 'https://id.example.com', apiKey: process.env.REVOKED_API_KEY });
 * const link = await revoked.links.create({ label: 'Delivery address', records: [recordId] });
 * console.log(revoked.links.url(link));
 * ```
 */
export class Revoked {
  readonly server: Server;
  readonly links: Links;
  readonly requests: Requests;
  readonly templates: Templates;
  /** The vault through the `records` collection, for a session. */
  readonly records: Records;
  readonly sections: Sections;
  /** The vault through `/api/vault`, for an API key or a connected tool. */
  readonly vault: Vault;
  readonly identities: Identities;
  readonly attestations: Attestations;
  readonly credentials: Credentials;
  readonly attestationChecks: AttestationChecks;
  readonly attestationShares: AttestationShares;
  readonly contacts: Contacts;
  readonly workspaces: Workspaces;
  readonly members: Members;
  readonly invites: Invites;
  readonly groups: Groups;
  readonly apiKeys: ApiKeys;
  readonly notifications: Notifications;
  /** Tools connected to this workspace, as the owner manages them. */
  readonly connections: Connections;
  readonly signIns: SignIns;
  /** A connected tool's own side, for a `connection` credential. */
  readonly connection: ToolConnection;
  readonly webhooks: Webhooks;
  readonly grants: Grants;
  /** Calls where the slug or token is the key. */
  readonly public: Public;

  private readonly ctx: ClientContext;

  constructor(options: RevokedOptions) {
    const transport = new Transport({
      server: options.server,
      credential: credentialOf(options),
      ...(options.fetch ? { fetch: options.fetch } : {}),
      ...(options.timeoutMs === undefined ? {} : { timeoutMs: options.timeoutMs }),
      ...(options.retry ? { retry: options.retry } : {}),
      ...(options.headers ? { headers: options.headers } : {}),
    });
    const ctx = new ClientContext(transport, options.workspace);
    this.ctx = ctx;
    this.server = new Server(ctx);
    this.links = new Links(ctx);
    this.requests = new Requests(ctx);
    this.templates = new Templates(ctx);
    this.records = new Records(ctx);
    this.sections = new Sections(ctx);
    this.vault = new Vault(ctx);
    this.identities = new Identities(ctx);
    this.attestations = new Attestations(ctx);
    this.credentials = new Credentials(ctx);
    this.attestationChecks = new AttestationChecks(ctx);
    this.attestationShares = new AttestationShares(ctx);
    this.contacts = new Contacts(ctx);
    this.workspaces = new Workspaces(ctx);
    this.members = new Members(ctx);
    this.invites = new Invites(ctx);
    this.groups = new Groups(ctx);
    this.apiKeys = new ApiKeys(ctx);
    this.notifications = new Notifications(ctx);
    this.connections = new Connections(ctx);
    this.signIns = new SignIns(ctx);
    this.connection = new ToolConnection(ctx);
    this.webhooks = new Webhooks(ctx);
    this.grants = new Grants(ctx, options.grantCache);
    this.public = new Public(ctx);
  }

  /** The server origin this client talks to. */
  get origin(): string {
    return this.ctx.transport.baseUrl.origin;
  }

  /** The current session token, after any automatic refresh. */
  get sessionToken(): string | undefined {
    return this.ctx.transport.sessionToken;
  }

  /** Who the credential acts as: the person, the API key or the tool, and its workspace. */
  me(options?: CallOptions): Promise<Me> {
    return this.ctx.whoami(options);
  }

  /** The workspace collection writes go to. */
  workspace(options?: CallOptions): Promise<string> {
    return this.ctx.workspace(options);
  }

  /** Who sees and who edits one item of the workspace. Session only. */
  access(
    collection: 'sections' | 'records' | 'links' | 'requests' | 'templates' | 'contacts' | 'attestations',
    id: string,
    options: CallOptions = {},
  ): Promise<{
    owner: unknown;
    readers: { count: number; members: unknown[] };
    editors: { count: number; members: unknown[] };
    canEdit: boolean;
    canChangeAudience: boolean;
    audience: { kind: string; groups: string[]; editing: boolean };
  }> {
    return this.ctx.transport.request(`api/access/${encodeURIComponent(collection)}/${encodeURIComponent(id)}`, {
      signal: options.signal,
    });
  }

  /** Replaces which parts of the app the signed-in account sees. Keys come from `server.features()`. */
  async setFeatures(features: string[], options: CallOptions = {}): Promise<string[]> {
    const res = await this.ctx.transport.request<{ features: string[] }>('api/account/features', {
      method: 'PUT',
      body: { features },
      signal: options.signal,
      idempotent: true,
    });
    return res.features;
  }

  /**
   * A request to any path, with this client's credential, retries and error
   * decoding, for an endpoint newer than this SDK.
   */
  request<T = unknown>(
    path: string,
    options: Parameters<Transport['request']>[1] = {},
  ): Promise<T> {
    return this.ctx.transport.request<T>(path, options);
  }
}
