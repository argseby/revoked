/// A link the holder made to show one of their attestations to whoever opens
/// it. The link itself is shown once, when it is made: the server keeps only
/// a hash of it, so this row is for seeing and ending it, not for copying it.
class AttestationShare {
  final String id;

  /// The held attestation it shows.
  final String credential;

  /// `pending` until signed, then `active`, or `revoked` once ended.
  final String status;

  /// The names of the details it shows.
  final List<String> disclosed;
  final DateTime? expiresAt;
  final int viewCount;
  final DateTime? lastViewedAt;
  final DateTime? created;

  const AttestationShare({
    required this.id,
    required this.credential,
    required this.status,
    this.disclosed = const [],
    this.expiresAt,
    this.viewCount = 0,
    this.lastViewedAt,
    this.created,
  });

  factory AttestationShare.fromJson(Map<String, dynamic> json) {
    final disclosed = json['disclosed'];
    return AttestationShare(
      id: json['id'] as String,
      credential: json['credential'] as String? ?? '',
      status: json['status'] as String? ?? '',
      disclosed: disclosed is List
          ? [for (final d in disclosed) d.toString()]
          : const [],
      expiresAt: _date(json['expiresAt']),
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      lastViewedAt: _date(json['lastViewedAt']),
      created: _date(json['created']),
    );
  }

  static DateTime? _date(Object? raw) => raw is String && raw.isNotEmpty
      ? DateTime.tryParse(raw.replaceFirst(' ', 'T'))
      : null;

  bool get isRevoked => status == 'revoked';

  bool get isExpired {
    final at = expiresAt;
    return at != null && !at.isAfter(DateTime.now());
  }

  /// Whether whoever has the link can still open it.
  bool get isOpen => status == 'active' && !isExpired;
}

/// A link just made: the address to pass on, shown this once.
class NewAttestationShare {
  final String id;
  final String url;
  final DateTime? expiresAt;

  const NewAttestationShare({
    required this.id,
    required this.url,
    this.expiresAt,
  });
}
