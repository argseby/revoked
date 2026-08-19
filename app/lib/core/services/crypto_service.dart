import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart' as pc;

/// Owns all ECDSA (secp256r1) key generation, signing, and X.509 work
/// performed inside the client.
///
/// Identity keypairs are generated locally; the private key is kept in the
/// device's secure storage and never leaves it — only the public key is sent
/// to the server, which issues a certificate for it. Every signing operation
/// uses the locally stored PEM.
class CryptoService {
  static const _storagePrefix = 'identity_priv_';

  /// Must stay in step with the digest the server verifies
  /// (`util/signature.go` hashes with SHA-256).
  static const ecdsaAlgorithm = 'SHA-256/ECDSA';

  final FlutterSecureStorage _storage;

  CryptoService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          FlutterSecureStorage(
            // macOS: the data-protection keychain needs a Keychain Sharing
            // entitlement that local/ad-hoc dev builds don't have, so writes
            // and reads silently fail ("no private key stored for identity").
            // The legacy keychain works for the sandboxed app without it.
            mOptions: const MacOsOptions(usesDataProtectionKeychain: false),
          );

  /// Generates a fresh ECDSA (secp256r1) keypair.
  /// Returns the PEM-encoded private and public keys.
  GeneratedIdentity generateIdentity({required String commonName}) {
    final keyPair = CryptoUtils.generateEcKeyPair();
    final privatePem = CryptoUtils.encodeEcPrivateKeyToPem(
      keyPair.privateKey as pc.ECPrivateKey,
    );
    final publicPem = CryptoUtils.encodeEcPublicKeyToPem(
      keyPair.publicKey as pc.ECPublicKey,
    );

    return GeneratedIdentity(
      privateKeyPem: privatePem,
      publicKeyPem: publicPem,
    );
  }

  /// Persist the private key locally, keyed by the server-assigned
  /// identity id. Subsequent sign operations look it up here.
  Future<void> storePrivateKey(String identityId, String privateKeyPem) {
    return _storage.write(
      key: '$_storagePrefix$identityId',
      value: privateKeyPem,
    );
  }

  Future<String?> loadPrivateKey(String identityId) {
    return _storage.read(key: '$_storagePrefix$identityId');
  }

  Future<void> deletePrivateKey(String identityId) {
    return _storage.delete(key: '$_storagePrefix$identityId');
  }

  /// Signs [message] with the locally stored private key for [identityId]
  /// using ECDSA with SHA-256. The signature is returned as a
  /// base64-encoded string, matching the encoding the server expects.
  Future<String> signMessage({
    required String identityId,
    required String message,
  }) async {
    final pem = await loadPrivateKey(identityId);
    if (pem == null || pem.isEmpty) {
      throw StateError(
        'No private key stored for identity $identityId — cannot sign.',
      );
    }
    return signWithPrivateKey(privateKeyPem: pem, message: message);
  }

  /// Variant of [signMessage] used for ephemeral keys (e.g. the in-browser
  /// guest identity minted on the public response screen). Skips the
  /// secure-storage lookup so callers can sign with material that was
  /// generated moments earlier.
  String signWithPrivateKey({
    required String privateKeyPem,
    required String message,
  }) {
    final privateKey = CryptoUtils.ecPrivateKeyFromPem(privateKeyPem);
    final data = Uint8List.fromList(utf8.encode(message));
    // The digest must be named explicitly: ecSign defaults to SHA-1/ECDSA,
    // while the server verifies a SHA-256 digest, so every signature made with
    // the default was rejected as invalid.
    final sig = CryptoUtils.ecSign(
      privateKey,
      data,
      algorithmName: ecdsaAlgorithm,
    );
    return CryptoUtils.ecSignatureToBase64(sig);
  }

  /// Verifies an ECDSA / SHA-256 signature.
  ///
  /// [signatureBytes] is the raw signature (already hex- or base64-decoded
  /// by the caller). Returns true if the signature is valid for [message]
  /// under the ECDSA public key encoded in [publicKeyPem].
  ///
  /// Used by [DomainVerificationService] to confirm an identity's
  /// parentSignature was produced by the claimed server's root key.
  bool verifySignature({
    required String publicKeyPem,
    required String message,
    required Uint8List signatureBytes,
  }) {
    final data = Uint8List.fromList(utf8.encode(message));

    // A server root key is RSA (see cmd/revoked/server/root.go), so the RSA
    // path is tried first: parsing an RSA key as EC throws, which used to make
    // every parentSignature check fail and report the peer as spoofed.
    try {
      final rsaKey = CryptoUtils.rsaPublicKeyFromPem(publicKeyPem);
      final verifier = pc.Signer('SHA-256/RSA') as pc.RSASigner;
      verifier.init(false, pc.PublicKeyParameter<pc.RSAPublicKey>(rsaKey));
      if (verifier.verifySignature(data, pc.RSASignature(signatureBytes))) {
        return true;
      }
    } catch (_) {
      // Not an RSA key, or not an RSA signature — fall through to ECDSA.
    }

    try {
      final publicKey = CryptoUtils.ecPublicKeyFromPem(publicKeyPem);
      final sig = CryptoUtils.ecSignatureFromDerBytes(signatureBytes);
      return CryptoUtils.ecVerify(
        publicKey,
        data,
        sig,
        algorithm: ecdsaAlgorithm,
      );
    } catch (_) {
      // PEM parse / format errors all count as "not verifiable" — we
      // refuse to trust signatures we can't even decode. Swallowing
      // the specific error here is intentional; the caller's
      // TrustVerdict already carries the higher-level reason.
      return false;
    }
  }

  /// SHA-256 of [input], returned as lowercase hex — matches the
  /// fingerprint encoding the server uses for both identity certificates
  /// and the root pubkey PEM. Lets the DomainVerificationService
  /// recompute the fingerprint from a fetched pubkey and compare it
  /// against the DNS TXT pin without trusting the server's claimed
  /// fingerprint field.
  String sha256Hex(String input) {
    final digest = pc.SHA256Digest().process(
      Uint8List.fromList(utf8.encode(input)),
    );
    final buf = StringBuffer();
    for (final b in digest) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }
}

/// Bundle of artifacts produced by [CryptoService.generateIdentity].
class GeneratedIdentity {
  final String privateKeyPem;
  final String publicKeyPem;

  const GeneratedIdentity({
    required this.privateKeyPem,
    required this.publicKeyPem,
  });
}
