const FILTER = Symbol('revoked.filter');

/** A PocketBase filter expression whose interpolated values are escaped. */
export interface Filter {
  readonly [FILTER]: true;
  readonly expression: string;
}

export type FilterValue = string | number | boolean | null | Date | Filter;

function literal(value: FilterValue): string {
  if (value === null) return 'null';
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new TypeError('A filter number must be finite.');
    return String(value);
  }
  if (value instanceof Date) return quote(value.toISOString().replace('T', ' '));
  if (typeof value === 'object' && FILTER in value) return `(${value.expression})`;
  return quote(value);
}

function quote(text: string): string {
  return `'${text.replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
}

/**
 * Builds a filter from a template, escaping every interpolated value:
 * `` f`key = ${key} && created > ${since}` ``. A user-supplied value can never
 * end the string literal and add a clause of its own.
 */
export function f(strings: TemplateStringsArray, ...values: FilterValue[]): Filter {
  let expression = strings[0] ?? '';
  values.forEach((value, i) => {
    expression += literal(value) + (strings[i + 1] ?? '');
  });
  return { [FILTER]: true, expression };
}

/** Joins filters with `&&`, parenthesizing each so `||` inside one cannot widen the rest. */
export function and(...filters: (Filter | undefined)[]): Filter | undefined {
  const parts = filters.filter((x): x is Filter => x !== undefined && x.expression.trim() !== '');
  if (parts.length === 0) return undefined;
  if (parts.length === 1) return parts[0];
  return { [FILTER]: true, expression: parts.map((p) => `(${p.expression})`).join(' && ') };
}

export function isFilter(value: unknown): value is Filter {
  return typeof value === 'object' && value !== null && FILTER in value;
}
