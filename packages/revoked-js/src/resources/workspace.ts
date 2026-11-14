import { jsonBody } from '../core/body.js';
import { Collection, ReadableCollection } from '../core/collection.js';
import type { ClientContext } from '../core/context.js';
import { path } from '../core/context.js';
import { RevokedError } from '../core/errors.js';
import { f } from '../core/filter.js';
import { onceHeader, type CallOptions } from '../core/transport.js';
import type {
  ApiKey,
  ApiKeyInput,
  Audience,
  Group,
  Invite,
  InviteInput,
  MemberList,
  Notification,
  Workspace,
  WorkspaceMember,
} from '../models.js';

export interface WorkspaceInput {
  name?: string;
  slug?: string;
  defaultAudience?: Record<string, Audience>;
}

export class Workspaces extends Collection<Workspace, WorkspaceInput> {
  constructor(ctx: ClientContext) {
    super(ctx, 'workspaces', { bindWorkspace: false });
  }

  /**
   * Makes a workspace the session's active one, which every collection rule
   * and later write of this client is bound to. Session only.
   */
  async activate(id: string, options: CallOptions = {}): Promise<void> {
    const user = this.ctx.sessionUser;
    if (!user) {
      throw new RevokedError({ status: 0, code: 'session_required', message: 'Switching workspace takes a session.' });
    }
    const membership = await this.ctx.transport.request<{ items: WorkspaceMember[] }>(
      'api/collections/workspaceMembers/records',
      { query: { filter: f`workspace = ${id} && user = ${user}`.expression, perPage: 1 }, signal: options.signal },
    );
    const member = membership.items[0];
    if (!member) {
      throw new RevokedError({ status: 403, code: 'not_workspace_member', message: 'Not a member of this workspace.' });
    }
    await this.ctx.transport.request(path`api/collections/users/records/${user}`, {
      method: 'PATCH',
      body: { activeWorkspace: id, activeRole: member.role },
      signal: options.signal,
      idempotent: true,
    });
    this.ctx.setWorkspace(id);
  }
}

export interface WorkspaceMemberInput {
  user?: string;
  workspace?: string;
  /** Permission keys from `server.permissions()`. */
  permissions?: string[];
}

export class Members extends Collection<WorkspaceMember, WorkspaceMemberInput> {
  constructor(ctx: ClientContext) {
    super(ctx, 'workspaceMembers', { bindUser: false });
  }

  /** The members of a workspace with their expanded permissions, and what the caller may grant. */
  overview(workspaceId: string, options: CallOptions = {}): Promise<MemberList> {
    return this.ctx.transport.request(path`api/workspaces/${workspaceId}/members`, { signal: options.signal });
  }
}

export interface CreatedInvite {
  invite: Invite;
  /** The secret part of the invitation. Shown once; only its hash is stored. */
  token: string;
}

export class Invites extends Collection<Invite, InviteInput> {
  constructor(ctx: ClientContext) {
    super(ctx, 'invites');
  }

  /** Use `createWithToken`: the token comes back once, in a header. */
  override async create(input: InviteInput, options: CallOptions = {}): Promise<Invite> {
    return (await this.createWithToken(input, options)).invite;
  }

  async createWithToken(input: InviteInput, options: CallOptions = {}): Promise<CreatedInvite> {
    const res = await this.createRaw(input, options);
    return { invite: res.data, token: onceHeader(res.headers, 'X-Invite-Token') };
  }

  revoke(id: string, options?: CallOptions): Promise<Invite> {
    return this.update(id, { status: 'revoked' }, options);
  }
}

/** Named sets of members an audience can name. Session only. */
export class Groups {
  constructor(private readonly ctx: ClientContext) {}

  list(options: CallOptions = {}): Promise<{ groups: Group[]; canManage: boolean }> {
    return this.ctx.transport.request('api/groups', { signal: options.signal });
  }

  create(input: { name: string }, options: CallOptions = {}): Promise<Group> {
    return this.ctx.transport.request('api/groups', { method: 'POST', body: jsonBody(input), signal: options.signal });
  }

  rename(id: string, name: string, options: CallOptions = {}): Promise<Group> {
    return this.ctx.transport.request(path`api/groups/${id}`, {
      method: 'PATCH',
      body: { name },
      signal: options.signal,
      idempotent: true,
    });
  }

  async delete(id: string, options: CallOptions = {}): Promise<void> {
    await this.ctx.transport.request(path`api/groups/${id}`, { method: 'DELETE', responseType: 'none', signal: options.signal });
  }

  addMember(id: string, user: string, options: CallOptions = {}): Promise<Group> {
    return this.ctx.transport.request(path`api/groups/${id}/members/${user}`, {
      method: 'PUT',
      signal: options.signal,
      idempotent: true,
    });
  }

  removeMember(id: string, user: string, options: CallOptions = {}): Promise<Group> {
    return this.ctx.transport.request(path`api/groups/${id}/members/${user}`, { method: 'DELETE', signal: options.signal });
  }
}

export interface CreatedApiKey {
  key: ApiKey;
  /** The key to send as `X-API-Key`. Shown once; only its hash is stored. */
  token: string;
}

/** API keys of the signed-in person. Keys cannot manage keys. */
export class ApiKeys extends ReadableCollection<ApiKey> {
  constructor(ctx: ClientContext) {
    super(ctx, 'apiKeys');
  }

  async create(input: ApiKeyInput, options: CallOptions = {}): Promise<CreatedApiKey> {
    const { permissions, ...rest } = input;
    const body = jsonBody({
      ...rest,
      scopes: permissions,
      workspace: await this.ctx.workspace(options),
      user: this.ctx.sessionUser,
    });
    const res = await this.ctx.transport.raw<ApiKey>(this.base, { method: 'POST', body, signal: options.signal });
    return { key: res.data, token: onceHeader(res.headers, 'X-Plain-Token') };
  }

  /** Revoked keys stop working immediately. */
  async delete(id: string, options: CallOptions = {}): Promise<void> {
    await this.ctx.transport.request(`${this.base}/${encodeURIComponent(id)}`, {
      method: 'DELETE',
      responseType: 'none',
      signal: options.signal,
    });
  }
}

export class Notifications extends ReadableCollection<Notification> {
  constructor(ctx: ClientContext) {
    super(ctx, 'notifications');
  }

  markRead(id: string, options: CallOptions = {}): Promise<Notification> {
    return this.ctx.transport.request(`${this.base}/${encodeURIComponent(id)}`, {
      method: 'PATCH',
      body: { read: true },
      signal: options.signal,
      idempotent: true,
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
