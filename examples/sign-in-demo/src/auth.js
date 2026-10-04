// Sign in with Revoked, through an ordinary OpenID Connect client library.
//
// Nothing here is specific to Revoked except two things: which server to ask
// depends on the person (every server is self-hosted), and vault entries are
// asked for with the `revoked_links` claim.
//
// The server is found one of two ways. Usually the person's Revoked app knows
// it: the sign-in starts without one, the app opens its own server, and the
// answer names that server in `iss` (RFC 9207). Without the app on the
// device, the person names their server instead.

import * as oidc from 'openid-client';
import { config } from './config.js';

const HOST_PATTERN = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*(:\d{1,5})?$/;

export class SignInError extends Error {}

// A server as people type it — "revoked.example", or a pasted address — to
// its issuer URL. Plain http is used only for a server on this machine.
export function issuerFor(input) {
  let host = String(input ?? '').trim().toLowerCase();
  host = host.replace(/^https?:\/\//, '').replace(/\/+$/, '');
  if (!HOST_PATTERN.test(host)) {
    throw new SignInError('Enter the domain of your Revoked server, for example revoked.example.');
  }
  if (config.allowedServers.length && !config.allowedServers.includes(host)) {
    throw new SignInError(`This service does not work with ${host}.`);
  }
  const local = /^(localhost|127\.0\.0\.1)(:\d+)?$/.test(host);
  return `${local ? 'http' : 'https'}://${host}`;
}

// Discovery is cached per server: the metadata and keys rarely change, and
// the library refetches the key set when it meets a key it does not know.
const providers = new Map();

async function providerFor(issuer) {
  if (!providers.has(issuer)) {
    const insecure = issuer.startsWith('http://');
    const pending = oidc
      .discovery(new URL(issuer), config.clientId, undefined, oidc.None(), {
        execute: insecure ? [oidc.allowInsecureRequests] : [],
      })
      .catch((err) => {
        providers.delete(issuer);
        throw new SignInError(`${issuer} could not be reached as a Revoked server (${err.message}).`);
      });
    providers.set(issuer, pending);
  }
  return providers.get(issuer);
}

// The authorization request, apart from the server it goes to. Nothing in it
// depends on that server, which is what lets the app choose it.
async function authorizationRequest(issuer) {
  const verifier = oidc.randomPKCECodeVerifier();
  const pending = {
    issuer,
    verifier,
    state: oidc.randomState(),
    nonce: oidc.randomNonce(),
  };
  const params = {
    client_id: config.clientId,
    response_type: 'code',
    redirect_uri: config.redirectUri,
    scope: config.scope,
    code_challenge: await oidc.calculatePKCECodeChallenge(verifier),
    code_challenge_method: 'S256',
    state: pending.state,
    nonce: pending.nonce,
  };
  if (config.requestedKeys.length) {
    params.claims = JSON.stringify({
      userinfo: { revoked_links: { values: config.requestedKeys } },
    });
  }
  return { params, pending };
}

// Starts a sign-in through the person's Revoked app, which knows their
// server: returns the revoked://signin link, and what to remember until the
// browser comes back. The server is not known until then.
export async function beginAppSignIn() {
  const { params, pending } = await authorizationRequest(null);
  return { url: `revoked://signin?${new URLSearchParams(params)}`, pending };
}

// Starts a sign-in at a server the person named.
export async function beginSignIn(server) {
  const issuer = issuerFor(server);
  const provider = await providerFor(issuer);
  const { params, pending } = await authorizationRequest(issuer);
  return { url: oidc.buildAuthorizationUrl(provider, params).href, pending };
}

// The server a sign-in through the app ended at, read from the answer's
// `iss`. It is checked like a server the person typed — same allow-list, no
// plain http beyond this machine — and must be exactly an issuer URL; the
// library then confirms that the server's own metadata names the same issuer.
function issuerFromAnswer(callbackUrl) {
  const iss = callbackUrl.searchParams.get('iss');
  if (!iss) throw new SignInError('The answer does not say which server it came from.');
  if (issuerFor(iss) !== iss) throw new SignInError(`${iss} is not a server this service can use.`);
  return iss;
}

// Finishes a sign-in: checks the answer against what was remembered, redeems
// the code, verifies the ID token, and reads userinfo.
export async function completeSignIn(pending, callbackUrl) {
  const issuer = pending.issuer ?? issuerFromAnswer(callbackUrl);
  const provider = await providerFor(issuer);
  const tokens = await oidc.authorizationCodeGrant(provider, callbackUrl, {
    pkceCodeVerifier: pending.verifier,
    expectedState: pending.state,
    expectedNonce: pending.nonce,
    idTokenExpected: true,
  });
  const claims = tokens.claims();
  const userinfo = await oidc.fetchUserInfo(provider, tokens.access_token, claims.sub);
  return {
    issuer,
    // The subject is this service's own identifier for the person: the same
    // person gets a different one at every other service.
    subject: claims.sub,
    name: userinfo.name ?? claims.name ?? null,
    email: userinfo.email ?? claims.email ?? null,
    emailVerified: Boolean(userinfo.email_verified ?? claims.email_verified),
    grants: userinfo.revoked_links ?? null,
    signedInAt: new Date(),
  };
}
