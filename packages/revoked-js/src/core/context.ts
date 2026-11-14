import { RevokedError } from './errors.js';
import { fromBase64, fromUtf8 } from './encoding.js';
import type { Transport, CallOptions } from './transport.js';

/** Who the client's credential acts as. */
export interface Me {
  kind: 'user' | 'apiKey' | 'connection' | (string & {});
  id?: string;
  user?: string;
  workspace?: string;
  [field: string]: unknown;
}

export class ClientContext {
  private me: Promise<Me> | undefined;
  private workspaceId: string | undefined;

  constructor(
    readonly transport: Transport,
    workspace?: string,
  ) {
    this.workspaceId = workspace;
  }

  /** The id of the signed-in user, read from the session token without a request. */
  get sessionUser(): string | undefined {
    const token = this.transport.sessionToken;
    if (!token) return undefined;
    try {
      const payload = JSON.parse(fromUtf8(fromBase64(token.split('.')[1] ?? ''))) as { id?: unknown };
      return typeof payload.id === 'string' ? payload.id : undefined;
    } catch {
      return undefined;
    }
  }

  async whoami(options: CallOptions = {}): Promise<Me> {
    this.me ??= this.resolveMe(options).catch((error: unknown) => {
      this.me = undefined;
      throw error;
    });
    return this.me;
  }

  /** The workspace collection writes are bound to. Collection create rules require it in the body. */
  async workspace(options: CallOptions = {}): Promise<string> {
    if (this.workspaceId) return this.workspaceId;
    const me = await this.whoami(options);
    if (!me.workspace) {
      throw new RevokedError({
        status: 0,
        code: 'workspace_unknown',
        message: 'The workspace is unknown. Pass `workspace` to the client.',
      });
    }
    this.workspaceId = me.workspace;
    return me.workspace;
  }

  setWorkspace(id: string): void {
    this.workspaceId = id;
    this.me = undefined;
  }

  private async resolveMe(options: CallOptions): Promise<Me> {
    const user = this.sessionUser;
    if (this.transport.credentialKind === 'session' && user) {
      const record = await this.transport.request<{ id: string; activeWorkspace?: string; activeRole?: string }>(
        `api/collections/users/records/${encodeURIComponent(user)}`,
        { signal: options.signal },
      );
      return {
        kind: 'user',
        id: record.id,
        user: record.id,
        ...(record.activeWorkspace ? { workspace: record.activeWorkspace } : {}),
        ...(record.activeRole ? { role: record.activeRole } : {}),
      };
    }
    if (this.transport.credentialKind === 'none') {
      throw new RevokedError({ status: 0, code: 'not_authenticated', message: 'The client has no credential.' });
    }
    return this.transport.request<Me>('api/me', { signal: options.signal });
  }
}

export function path(template: TemplateStringsArray, ...parts: string[]): string {
  let out = template[0] ?? '';
  parts.forEach((part, i) => {
    if (typeof part !== 'string' || part === '') throw new TypeError('An id in the path is empty.');
    out += encodeURIComponent(part) + (template[i + 1] ?? '');
  });
  return out;
}
