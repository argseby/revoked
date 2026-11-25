package routes

// passkeyIdentityScript derives an identity key from a passkey's PRF output
// and signs with it (BROWSER.md §4.8). It touches neither the document nor the
// network, so passkeyIdentity_test.go runs exactly this text against a Go
// derivation of the same key; the two must agree byte for byte, or an
// identity registered in one browser would not be the one another derives.
//
// It expects identityError(code) from the page around it. No backticks and no
// template actions in here: it is spliced into the page as it stands.
const passkeyIdentityScript = `
var IDENTITY_PRF_SALT = new TextEncoder().encode('revoked-passkey-identity-prf-v1');
var IDENTITY_HKDF_INFO = new TextEncoder().encode('revoked-passkey-identity-v1');
var P256_ORDER = BigInt('0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551');
function bytesToBigInt(bytes) {
  var hex = '';
  for (var i = 0; i < bytes.length; i++) hex += ('0' + bytes[i].toString(16)).slice(-2);
  return BigInt('0x' + hex);
}
function bigIntTo32(n) {
  var hex = n.toString(16);
  while (hex.length < 64) hex = '0' + hex;
  var out = new Uint8Array(32);
  for (var i = 0; i < 32; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}
function pemOf(der) {
  var b64 = btoa(String.fromCharCode.apply(null, new Uint8Array(der)));
  var lines = [];
  for (var i = 0; i < b64.length; i += 64) lines.push(b64.slice(i, i + 64));
  return '-----BEGIN PUBLIC KEY-----\n' + lines.join('\n') + '\n-----END PUBLIC KEY-----\n';
}
// PKCS#8 for a P-256 private key without its public half, which the browser
// computes on import.
var P256_PKCS8_PREFIX = [0x30, 0x41, 0x02, 0x01, 0x00, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
  0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x04, 0x27, 0x30, 0x25, 0x02, 0x01, 0x01, 0x04, 0x20];

async function deriveIdentityKey(prf) {
  var ikm = await crypto.subtle.importKey('raw', prf, 'HKDF', false, ['deriveBits']);
  var bits = await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt: new Uint8Array(0), info: IDENTITY_HKDF_INFO }, ikm, 384);
  // 384 bits reduced into [1, n-1]: the bias is below 2^-128.
  var d = bytesToBigInt(new Uint8Array(bits)) % (P256_ORDER - BigInt(1)) + BigInt(1);
  var der = new Uint8Array(P256_PKCS8_PREFIX.length + 32);
  der.set(P256_PKCS8_PREFIX);
  der.set(bigIntTo32(d), P256_PKCS8_PREFIX.length);
  var alg = { name: 'ECDSA', namedCurve: 'P-256' };
  var full;
  try { full = await crypto.subtle.importKey('pkcs8', der, alg, true, ['sign']); }
  catch (e) { throw identityError('id.unsupported'); }
  var jwk = await crypto.subtle.exportKey('jwk', full);
  var pub = await crypto.subtle.importKey('jwk', { kty: 'EC', crv: 'P-256', x: jwk.x, y: jwk.y, ext: true }, alg, true, ['verify']);
  var spki = await crypto.subtle.exportKey('spki', pub);
  var privateKey = await crypto.subtle.importKey('pkcs8', der, alg, false, ['sign']);
  der.fill(0);
  return { privateKey: privateKey, publicPem: pemOf(spki) };
}

// ECDSA P-256 over SHA-256, DER-encoded as the server and the app read it.
function derInteger(bytes) {
  var i = 0;
  while (i < bytes.length - 1 && bytes[i] === 0) i++;
  var v = Array.prototype.slice.call(bytes, i);
  if (v[0] & 0x80) v.unshift(0);
  return [0x02, v.length].concat(v);
}
async function identitySignWith(privateKey, message) {
  var raw = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, privateKey, new TextEncoder().encode(message)));
  var body = derInteger(raw.slice(0, 32)).concat(derInteger(raw.slice(32)));
  var der = [0x30, body.length].concat(body);
  return btoa(String.fromCharCode.apply(null, der));
}

`
