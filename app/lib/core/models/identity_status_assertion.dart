import 'dart:convert';
import 'dart:typed_data';

/// The issuing server's signed, timestamped answer about one identity.
///
/// This is the piece a certificate cannot carry. A leaf is minted for ten
/// years and its `parentSignature` never expires, so a holder who has been
/// removed from the workspace goes on proving exactly what they proved on
/// their first day. A signed challenge does not help — it proves possession
/// of the key, which they still have. Only the issuer's current opinion
/// closes the gap, and this is that opinion, signed by the same DNS-pinned
/// root key that signed the identity.
///
/// [payload] holds the exact bytes that were signed. It is transmitted rather
/// than reconstructed because signer and verifier would otherwise have to
/// agree on JSON field order and which empty fields are omitted; a mismatch
/// there looks like a broken key rather than a formatting bug.
class IdentityStatusAssertion {
  static const type = 'identity-status-v1';

  final String payload;
  final String signature;

  const IdentityStatusAssertion({
    required this.payload,
    required this.signature,
  });

  static IdentityStatusAssertion? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final payload = json['payload'];
    final signature = json['signature'];
    if (payload is! String || signature is! String) return null;
    if (payload.isEmpty || signature.isEmpty) return null;
    return IdentityStatusAssertion(payload: payload, signature: signature);
  }

  /// The signed bytes, for handing to a signature check.
  Uint8List? signedBytes() {
    try {
      return base64Url.decode(base64.normalize(payload));
    } catch (_) {
      return null;
    }
  }

  /// Decodes the payload WITHOUT checking the signature. Only for rendering
  /// something already verified — callers acting on the answer must go
  /// through [IdentityStatusBody.verified].
  IdentityStatusBody? decodeUnverified() {
    final bytes = signedBytes();
    if (bytes == null) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) return null;
      return IdentityStatusBody._fromMap(decoded);
    } catch (_) {
      return null;
    }
  }
}

/// The statement inside a verified [IdentityStatusAssertion].
class IdentityStatusBody {
  static const active = 'active';
  static const revoked = 'revoked';

  /// The issuer has no record of the fingerprint. Deliberately not a synonym
  /// for [revoked]: a restored backup or a reinstall answers this way about
  /// identities that were perfectly valid, so it means "no information".
  static const unknown = 'unknown';

  final String type;
  final String domain;
  final String fingerprint;
  final String status;
  final String reason;
  final DateTime? revokedAt;
  final DateTime issuedAt;
  final DateTime expiresAt;

  const IdentityStatusBody._({
    required this.type,
    required this.domain,
    required this.fingerprint,
    required this.status,
    required this.reason,
    required this.revokedAt,
    required this.issuedAt,
    required this.expiresAt,
  });

  bool get isActive => status == active;
  bool get isRevoked => status == revoked;

  static DateTime? _epoch(Object? seconds) {
    if (seconds is! num || seconds == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      seconds.toInt() * 1000,
      isUtc: true,
    );
  }

  static IdentityStatusBody? _fromMap(Map<String, dynamic> map) {
    final issuedAt = _epoch(map['issuedAt']);
    final expiresAt = _epoch(map['expiresAt']);
    if (issuedAt == null || expiresAt == null) return null;
    return IdentityStatusBody._(
      type: map['type'] as String? ?? '',
      domain: map['domain'] as String? ?? '',
      fingerprint: map['fingerprint'] as String? ?? '',
      status: map['status'] as String? ?? '',
      reason: map['reason'] as String? ?? '',
      revokedAt: _epoch(map['revokedAt']),
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
  }

  /// Checks the assertion end to end and returns the statement it verified,
  /// or null if anything about it fails to hold.
  ///
  /// Returning the body only on success is deliberate: it leaves no way for a
  /// caller to reach an answer it has not checked. [rootPublicKeyPem] must be
  /// a key the caller has already tied to [expectDomain] through the DNS pin —
  /// this establishes that the key signed the statement, not that the key
  /// deserves to be believed.
  static IdentityStatusBody? verified({
    required IdentityStatusAssertion assertion,
    required String rootPublicKeyPem,
    required String expectDomain,
    required String expectFingerprint,
    required DateTime now,
    required bool Function({
      required String publicKeyPem,
      required String message,
      required Uint8List signatureBytes,
    })
    verifySignature,
    required Uint8List? Function(String) decodeHex,
  }) {
    final signedBytes = assertion.signedBytes();
    if (signedBytes == null) return null;

    final signatureBytes = decodeHex(assertion.signature);
    if (signatureBytes == null) return null;

    // Over the transmitted bytes, before they are parsed — so what is checked
    // and what is read are the same thing.
    final ok = verifySignature(
      publicKeyPem: rootPublicKeyPem,
      message: utf8.decode(signedBytes),
      signatureBytes: signatureBytes,
    );
    if (!ok) return null;

    final body = assertion.decodeUnverified();
    if (body == null) return null;

    if (body.type != IdentityStatusAssertion.type) return null;
    if (body.domain.toLowerCase() != expectDomain.toLowerCase()) return null;
    if (body.fingerprint.toLowerCase() != expectFingerprint.toLowerCase()) {
      return null;
    }
    if (body.issuedAt.isAfter(now)) return null;
    if (body.expiresAt.isBefore(now)) return null;
    return body;
  }
}
