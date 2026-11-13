import { bodyFor } from './body.js';
import type { ClientContext } from './context.js';
import { path } from './context.js';
import { fromPocketBase, iterate, listQuery, type ListParams, type Page, type PocketBaseList } from './pagination.js';
import type { CallOptions } from './transport.js';

export interface GetParams extends CallOptions {
  /** PocketBase relation expansion, e.g. `records,sections`. */
  expand?: string;
}

export interface CollectionOptions {
  /** Collection create rules compare `workspace` in the body with the caller's. */
  bindWorkspace?: boolean;
  /** Also name the signed-in person as `user`; off where `user` means someone else. */
  bindUser?: boolean;
}

/** Read access to one PocketBase collection, narrowed by its rules to what the caller may see. */
export class ReadableCollection<T> {
  constructor(
    protected readonly ctx: ClientContext,
    readonly name: string,
  ) {}

  protected get base(): string {
    return path`api/collections/${this.name}/records`;
  }

  async list(params: ListParams & { expand?: string } = {}): Promise<Page<T>> {
    const list = await this.ctx.transport.request<PocketBaseList<T>>(this.base, {
      query: listQuery(params, { expand: params.expand }),
      signal: params.signal,
    });
    return fromPocketBase(list);
  }

  /** Every matching row, page by page. */
  iterate(params: Omit<ListParams, 'page'> & { expand?: string } = {}): AsyncGenerator<T, void, undefined> {
    return iterate((page) => this.list({ perPage: 200, ...params, page }));
  }

  get(id: string, params: GetParams = {}): Promise<T> {
    return this.ctx.transport.request<T>(`${this.base}/${encodeURIComponent(id)}`, {
      query: { expand: params.expand },
      signal: params.signal,
    });
  }
}

export class Collection<T, Create extends object, Update extends object = Partial<Create>> extends ReadableCollection<T> {
  constructor(
    ctx: ClientContext,
    name: string,
    private readonly options: CollectionOptions = {},
  ) {
    super(ctx, name);
  }

  protected async createRaw(input: object, options: CallOptions = {}) {
    const owned: Record<string, unknown> = { ...input };
    if (this.options.bindWorkspace !== false) {
      owned.workspace ??= await this.ctx.workspace(options);
      const user = this.ctx.sessionUser;
      if (user && this.options.bindUser !== false) owned.user ??= user;
    }
    return this.ctx.transport.raw<T>(this.base, { method: 'POST', ...bodyFor(owned), signal: options.signal });
  }

  async create(input: Create, options: CallOptions = {}): Promise<T> {
    return (await this.createRaw(input, options)).data;
  }

  update(id: string, input: Update, options: CallOptions = {}): Promise<T> {
    return this.ctx.transport.request<T>(`${this.base}/${encodeURIComponent(id)}`, {
      method: 'PATCH',
      ...bodyFor(input),
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
