import { derToPem, pemToDer, toBase64, utf8 } from '../core/encoding.js';

/** An identity's key pair. The private key never leaves the device. */
export interface IdentityKey {
  privateKey: CryptoKey;
  publicKey: CryptoKey;
}

const ALGORITHM = { name: 'ECDSA', namedCurve: 'P-256' } as const;

export interface GenerateIdentityKeyOptions {
  /**
   * Allow `exportPrivateKeyPem`, to persist the key in storage of the caller's
   * choosing. Off by default: a non-extractable key cannot be copied out of
   * this runtime even by code running in it.
   */
  extractable?: boolean;
}

export async function generateIdentityKey(options: GenerateIdentityKeyOptions = {}): Promise<IdentityKey> {
  return (await crypto.subtle.generateKey(ALGORITHM, options.extractable ?? false, ['sign', 'verify'])) as CryptoKeyPair;
}

/** The SPKI PEM the server issues a certificate over. */
export async function exportPublicKeyPem(key: Pick<IdentityKey, 'publicKey'>): Promise<string> {
  return derToPem(new Uint8Array(await crypto.subtle.exportKey('spki', key.publicKey)), 'PUBLIC KEY');
}

/** PKCS#8 PEM, for a key generated with `extractable: true`. Store it as a secret. */
export async function exportPrivateKeyPem(key: Pick<IdentityKey, 'privateKey'>): Promise<string> {
  return derToPem(new Uint8Array(await crypto.subtle.exportKey('pkcs8', key.privateKey)), 'PRIVATE KEY');
}

/** Loads a key saved with `exportPrivateKeyPem`. The loaded private key is not extractable. */
export async function importIdentityKey(privateKeyPem: string, publicKeyPem: string): Promise<IdentityKey> {
  const [privateKey, publicKey] = await Promise.all([
    crypto.subtle.importKey('pkcs8', pemToDer(privateKeyPem), ALGORITHM, false, ['sign']),
    crypto.subtle.importKey('spki', pemToDer(publicKeyPem), ALGORITHM, true, ['verify']),
  ]);
  return { privateKey, publicKey };
}

/**
 * Signs a challenge nonce as the server verifies it: ECDSA P-256 over SHA-256
 * of the nonce's UTF-8 bytes, ASN.1 DER, standard base64.
 */
export async function signChallenge(key: Pick<IdentityKey, 'privateKey'>, nonce: string): Promise<string> {
  const raw = new Uint8Array(
    await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key.privateKey, utf8(nonce)),
  );
  return toBase64(p1363ToDer(raw));
}

/** WebCrypto returns r‖s; the server verifies with `ecdsa.VerifyASN1`, which wants DER. */
export function p1363ToDer(signature: Uint8Array): Uint8Array {
  if (signature.length % 2 !== 0) throw new TypeError('Invalid ECDSA signature length.');
  const half = signature.length / 2;
  const r = derInteger(signature.subarray(0, half));
  const s = derInteger(signature.subarray(half));
  const body = [...r, ...s];
  return new Uint8Array([0x30, ...derLength(body.length), ...body]);
}

function derInteger(bytes: Uint8Array): number[] {
  let start = 0;
  while (start < bytes.length - 1 && bytes[start] === 0) start++;
  const value = Array.from(bytes.subarray(start));
  if ((value[0] ?? 0) & 0x80) value.unshift(0);
  return [0x02, ...derLength(value.length), ...value];
}

function derLength(length: number): number[] {
  if (length < 0x80) return [length];
  const out: number[] = [];
  for (let n = length; n > 0; n >>= 8) out.unshift(n & 0xff);
  return [0x80 | out.length, ...out];
}
