import 'package:revoked_app/core/models/credential.dart';

/// Someone this person asked to show an attestation: what was asked for,
/// and once answered, the verdict on what they showed.
///
/// The result is a snapshot of the moment it was checked. A credential
/// revoked afterwards does not change it.
class AttestationCheck {
  final String id;
  final String type;
  final List<String> issuers;
  final List<String> claims;
  final String status;
  final String? expiresAt;
  final String? answeredAt;
  final String? created;
  final CheckResult? result;

  const AttestationCheck({
    required this.id,
    required this.type,
    required this.issuers,
    required this.claims,
    required this.status,
    this.expiresAt,
    this.answeredAt,
    this.created,
    this.result,
  });

  factory AttestationCheck.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? raw) =>
        raw is List ? [for (final v in raw) v.toString()] : const [];
    final result = json['result'];
    String? date(Object? raw) => raw is String && raw.isNotEmpty ? raw : null;
    return AttestationCheck(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      issuers: strings(json['issuers']),
      claims: strings(json['claims']),
      status: json['status'] as String? ?? 'open',
      expiresAt: date(json['expiresAt']),
      answeredAt: date(json['answeredAt']),
      created: date(json['created']),
      result: result is Map<String, dynamic>
          ? CheckResult.fromJson(result)
          : null,
    );
  }

  bool get isAnswered => status == 'answered' && result != null;

  /// Open and still within its time: the other person can still answer.
  bool isWaiting(DateTime now) {
    if (status != 'open') return false;
    final until = DateTime.tryParse((expiresAt ?? '').replaceFirst(' ', 'T'));
    return until != null && until.isAfter(now);
  }

  String get title => type.isEmpty ? 'Any attestation' : type;
}

/// The verdict on what was shown, as the asker's server recorded it.
class CheckResult {
  final CredentialVerdict verdict;
  final String issuer;
  final String type;
  final Map<String, dynamic> claims;
  final int withheld;

  /// The shower's identity: its fingerprint, and the domain that issued it.
  final String holderFingerprint;
  final String holderDomain;

  const CheckResult({
    required this.verdict,
    required this.issuer,
    required this.type,
    required this.claims,
    required this.withheld,
    required this.holderFingerprint,
    required this.holderDomain,
  });

  factory CheckResult.fromJson(Map<String, dynamic> json) {
    final claims = json['claims'];
    final holder = json['holder'];
    return CheckResult(
      verdict: CredentialVerdict.fromJson(json),
      issuer: json['issuer'] as String? ?? '',
      type: json['type'] as String? ?? '',
      claims: claims is Map<String, dynamic> ? claims : const {},
      withheld: (json['withheld'] as num?)?.toInt() ?? 0,
      holderFingerprint: holder is Map
          ? holder['fingerprint'] as String? ?? ''
          : '',
      holderDomain: holder is Map ? holder['domain'] as String? ?? '' : '',
    );
  }

  /// Who showed it, as far as the verdict can say.
  String get shownBy {
    final short = holderFingerprint.length > 8
        ? '${holderFingerprint.substring(0, 8)}…'
        : holderFingerprint;
    if (short.isEmpty) return 'Unknown identity';
    return holderDomain.isEmpty ? short : '$short · $holderDomain';
  }
}
