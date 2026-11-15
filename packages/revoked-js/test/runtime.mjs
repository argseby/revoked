// Runs the built package on plain Node, with no build or test tooling, so the
// oldest Node in `engines` is checked against what users install rather than
// against tools that no longer support it.
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
const require = createRequire(import.meta.url);

const subpaths = Object.keys(pkg.exports).filter((p) => p !== './package.json');
for (const subpath of subpaths) {
  const name = pkg.name + subpath.slice(1);
  const esm = await import(name);
  const cjs = require(name);
  assert.ok(Object.keys(esm).length > 0, `${name} exports nothing`);
  assert.deepEqual(Object.keys(cjs).sort(), Object.keys(esm).sort(), `${name}: ESM and CJS exports differ`);
}

const { Revoked } = await import(pkg.name);
const seen = [];
const revoked = new Revoked({
  server: 'https://id.example.com',
  apiKey: 'key',
  fetch: async (input, init) => {
    const request = new Request(input, init);
    seen.push(request);
    return new Response(JSON.stringify({ features: { sealed: true } }), {
      headers: { 'content-type': 'application/json' },
    });
  },
});
assert.deepEqual(await revoked.server.features(), { features: { sealed: true } });
assert.equal(new URL(seen[0].url).pathname, '/api/features');

const { verifyWebhook } = await import(`${pkg.name}/webhooks`);
const secret = 'whsec_runtime';
const body = JSON.stringify({ id: 'evt_1', type: 'link.viewed', data: {} });
const t = Math.floor(Date.now() / 1000);
const v1 = createHmac('sha256', secret).update(`${t}.${body}`).digest('hex');
assert.equal((await verifyWebhook({ body, secret, signature: `t=${t},v1=${v1}` })).id, 'evt_1');
await assert.rejects(verifyWebhook({ body, secret, signature: `t=${t},v1=${'0'.repeat(64)}` }));

const { generateIdentityKey, exportPublicKeyPem, signChallenge } = await import(`${pkg.name}/identity`);
const key = await generateIdentityKey();
assert.match(await exportPublicKeyPem(key), /^-----BEGIN PUBLIC KEY-----/);
assert.ok((await signChallenge(key, 'nonce')).length > 0);

console.log(`${pkg.name} runs on Node ${process.versions.node}: ${subpaths.length} entry points, ESM and CJS`);
