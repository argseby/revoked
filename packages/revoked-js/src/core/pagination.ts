import type { Filter } from './filter.js';
import type { CallOptions, Query } from './transport.js';

export interface Page<T> {
  items: T[];
  page: number;
  perPage: number;
  /** Absent when the endpoint does not count. */
  totalItems?: number;
  totalPages?: number;
  hasMore: boolean;
}

export interface ListParams extends CallOptions {
  /** 1-based. Default 1. */
  page?: number;
  perPage?: number;
  /** Build with `f`, which escapes interpolated values. */
  filter?: Filter | undefined;
  /** PocketBase sort, e.g. `-created,label`. */
  sort?: string | undefined;
  /** Leaves out the count, which is faster on large lists. */
  skipTotal?: boolean;
}

export interface PocketBaseList<T> {
  page: number;
  perPage: number;
  totalItems: number;
  totalPages: number;
  items: T[];
}

export function listQuery(params: ListParams, extra: Query = {}): Query {
  return {
    page: params.page,
    perPage: params.perPage,
    filter: params.filter?.expression,
    sort: params.sort,
    skipTotal: params.skipTotal,
    ...extra,
  };
}

export function fromPocketBase<T, R = T>(list: PocketBaseList<T>, map: (item: T) => R = (x) => x as unknown as R): Page<R> {
  const counted = list.totalItems >= 0 && list.totalPages >= 0;
  return {
    items: list.items.map(map),
    page: list.page,
    perPage: list.perPage,
    ...(counted ? { totalItems: list.totalItems, totalPages: list.totalPages } : {}),
    hasMore: counted ? list.page < list.totalPages : list.items.length >= list.perPage,
  };
}

/** Walks every page in order. Stops early when the loop breaks. */
export async function* iterate<T>(
  fetchPage: (page: number) => Promise<Page<T>>,
  firstPage = 1,
): AsyncGenerator<T, void, undefined> {
  for (let page = firstPage; ; page++) {
    const result = await fetchPage(page);
    yield* result.items;
    if (!result.hasMore || result.items.length === 0) return;
  }
}
