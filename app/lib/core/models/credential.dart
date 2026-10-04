import 'package:revoked_app/core/utils/sd_jwt.dart';

/// An attestation its subject holds: a credential another party signed about
/// one of this person's identities.
///
/// The credential itself is an SD-JWT. It is kept on the person's own server,
/// which checked it when it arrived; presenting it needs the identity key,
/// which only this device has.
class Credential {
  final String id;

  /// The attesting domain.
  final String issuer;

  /// What kind of statement it is, in the attester's own words.
  final String type;

  /// The identity it is bound to.
  final String identity;
  final String workspace;

  /// The SD-JWT with every disclosure.
  final String credential;

  /// What it states, read by the server when it was kept.
  final Map<String, dynamic> claims;
  final String? issuedAt;
  final String? expiresAt;
  final String? created;

  const Credential({
    required this.id,
    required this.issuer,
    required this.type,
    required this.identity,
    required this.workspace,
    required this.credential,
    this.claims = const {},
    this.issuedAt,
    this.expiresAt,
    this.created,
  });

  factory Credential.fromJson(Map<String, dynamic> json) {
    final claims = json['claims'];
    return Credential(
      id: json['id'] as String,
      issuer: json['issuer'] as String? ?? '',
      type: json['type'] as String? ?? '',
      identity: json['identity'] as String? ?? '',
      workspace: json['workspace'] as String? ?? '',
      credential: json['credential'] as String? ?? '',
      claims: claims is Map<String, dynamic> ? claims : const {},
      issuedAt: _date(json['issuedAt']),
      expiresAt: _date(json['expiresAt']),
      created: _date(json['created']),
    );
  }

  static String? _date(Object? raw) =>
      raw is String && raw.isNotEmpty ? raw : null;

  /// The claims as the holder can disclose them one by one, in the
  /// credential's own order. Empty when the credential cannot be read.
  List<SdJwtDisclosure> get disclosures =>
      SdJwtCredential.tryParse(credential)?.disclosures ?? const [];

  DateTime? get expires => expiresAt == null
      ? null
      : DateTime.tryParse(expiresAt!.replaceFirst(' ', 'T'));

  bool get isExpired {
    final at = expires;
    return at != null && !at.isAfter(DateTime.now());
  }
}

/// What the holder's server found when it checked a credential it keeps:
/// whether the attester's key is tied to its domain, and whether the
/// credential and the identity it was issued to still stand.
class CredentialVerdict {
  /// verified, unverified, dnsMissing, spoofed, revoked, expired or invalid.
  final String state;
  final String reason;

  /// How the attester's key was tied to its domain.
  final String issuerState;

  /// valid, revoked or unknown — the attester's status list.
  final String status;

  const CredentialVerdict({
    required this.state,
    required this.reason,
    this.issuerState = '',
    this.status = '',
  });

  factory CredentialVerdict.fromJson(Map<String, dynamic> json) =>
      CredentialVerdict(
        state: json['state'] as String? ?? 'unverified',
        reason: json['reason'] as String? ?? '',
        issuerState: json['issuerState'] as String? ?? '',
        status: json['status'] as String? ?? '',
      );

  bool get isVerified => state == 'verified';
  bool get isRevoked => state == 'revoked';
  bool get isExpired => state == 'expired';

  /// A credential that nobody could verify any more.
  bool get isUnusable =>
      isRevoked || isExpired || state == 'spoofed' || state == 'invalid';

  /// One word for a list row.
  String get label => switch (state) {
    'verified' => 'Verified',
    'revoked' => 'Revoked',
    'expired' => 'Expired',
    'spoofed' => 'Not genuine',
    'invalid' => 'Unreadable',
    'dnsMissing' => 'Issuer unverified',
    _ => 'Unverified',
  };
}
