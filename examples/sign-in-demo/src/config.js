// Settings, read once from the environment and checked at startup.

const KEY_PATTERN = /^[a-z0-9_-]{1,64}$/;

function list(value) {
  return (value ?? '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function fail(message) {
  console.error(`Configuration error: ${message}`);
  process.exit(1);
}

const port = Number(process.env.PORT ?? 4000);
if (!Number.isInteger(port) || port < 1 || port > 65535) fail('PORT must be a port number.');

const publicUrl = new URL(process.env.PUBLIC_URL ?? `http://localhost:${port}`);
if (publicUrl.pathname !== '/' || publicUrl.search || publicUrl.hash) {
  fail('PUBLIC_URL must be an origin, without a path.');
}

const requestedKeys = list(process.env.REQUESTED_KEYS ?? 'shipping_address,phone');
for (const key of requestedKeys) {
  if (!KEY_PATTERN.test(key)) fail(`REQUESTED_KEYS: "${key}" is not a vault key.`);
}

export const config = Object.freeze({
  port,
  // The service is identified by its origin; no registration is needed.
  clientId: publicUrl.origin,
  redirectUri: `${publicUrl.origin}/callback`,
  secureCookies: publicUrl.protocol === 'https:',
  scope: 'openid profile email',
  requestedKeys,
  defaultServer: process.env.REVOKED_SERVER ?? '',
  allowedServers: list(process.env.REVOKED_SERVERS).map((s) => s.toLowerCase()),
});
