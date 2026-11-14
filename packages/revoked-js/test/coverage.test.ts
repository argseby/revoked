import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import * as connect from '../src/connect.js';
import { Revoked } from '../src/index.js';
import * as trust from '../src/trust.js';
import * as webhooks from '../src/webhooks.js';
import * as identity from '../src/identity.js';
import * as sealed from '../src/sealed.js';

const manifest = JSON.parse(readFileSync(new URL('../coverage.json', import.meta.url), 'utf8')) as {
  operations: Record<string, string | { excluded: string }>;
};

const modules: Record<string, unknown> = {
  client: new Revoked({ server: 'https://id.example.com' }),
  connect,
  trust,
  webhooks,
  identity,
  sealed,
};

function resolve(target: string): unknown {
  const [module, path = ''] = target.split(':');
  let value: unknown = modules[module ?? ''];
  for (const part of path.split('.')) {
    value = value === undefined || value === null ? undefined : (value as Record<string, unknown>)[part];
  }
  return value;
}

describe('coverage manifest', () => {
  for (const [operation, target] of Object.entries(manifest.operations)) {
    if (typeof target !== 'string') continue;
    it(`${operation} → ${target}`, () => {
      expect(typeof resolve(target)).toBe('function');
    });
  }
});
