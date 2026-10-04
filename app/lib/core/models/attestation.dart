/// A statement this workspace signs about someone's identity, in the name of
/// the server's domain.
///
/// It starts as an offer — what is stated, and a one-time link — and becomes
/// active when its subject accepts it with a proof of their identity key. The
/// signed credential is handed to them at that moment and not kept here.
class Attestation {
  final String id;
  final String type;
  final String label;
  final Map<String, dynamic> claims;

  /// offered, active or revoked.
  final String status;

  /// When the credential itself stops being valid.
  final String? expiresAt;

  /// Until when the offer can be accepted.
  final String? offerExpiresAt;
  final String subjectFingerprint;
  final String subjectDomain;
  final String subjectName;
  final String? issuedAt;
  final String? revokedAt;
  final String? created;

  const Attestation({
    required this.id,
    required this.type,
    required this.status,
    this.label = '',
    this.claims = const {},
    this.expiresAt,
    this.offerExpiresAt,
    this.subjectFingerprint = '',
    this.subjectDomain = '',
    this.subjectName = '',
    this.issuedAt,
    this.revokedAt,
    this.created,
  });

  factory Attestation.fromJson(Map<String, dynamic> json) {
    final claims = json['claims'];
    return Attestation(
      id: json['id'] as String,
      type: json['type'] as String? ?? '',
      label: json['label'] as String? ?? '',
      claims: claims is Map<String, dynamic> ? claims : const {},
      status: json['status'] as String? ?? 'offered',
      expiresAt: _date(json['expiresAt']),
      offerExpiresAt: _date(json['offerExpiresAt']),
      subjectFingerprint: json['subjectFingerprint'] as String? ?? '',
      subjectDomain: json['subjectDomain'] as String? ?? '',
      subjectName: json['subjectName'] as String? ?? '',
      issuedAt: _date(json['issuedAt']),
      revokedAt: _date(json['revokedAt']),
      created: _date(json['created']),
    );
  }

  static String? _date(Object? raw) =>
      raw is String && raw.isNotEmpty ? raw : null;

  bool get isOffered => status == 'offered';
  bool get isActive => status == 'active';
  bool get isRevoked => status == 'revoked';

  /// What a list shows for it: the name it was given, or its type.
  String get title => label.isEmpty ? type : label;

  /// Who holds it, once accepted.
  String get subject => subjectName.isEmpty
      ? subjectDomain
      : subjectDomain.isEmpty
      ? subjectName
      : '$subjectName · $subjectDomain';
}

/// What an offer shows before it is accepted: who attests, what, and for
/// whom. Read from the server the offer lives on, with nothing but its token.
class AttestationOffer {
  final String type;
  final String label;

  /// offered, or active once it was accepted.
  final String status;

  /// What would be stated. Empty once the offer was accepted: the values are
  /// shown only while it is open.
  final Map<String, dynamic> claims;
  final String? expiresAt;
  final String? offerExpiresAt;

  /// Set when the offer was made for one identity, or accepted by one.
  final String subjectFingerprint;

  /// The attesting domain, as the server names itself. Worth what the DNS
  /// check says it is worth.
  final String serverDomain;
  final String rootFingerprint;

  /// The workspace that issues it, in its own words.
  final String workspaceName;

  const AttestationOffer({
    required this.type,
    required this.status,
    this.label = '',
    this.claims = const {},
    this.expiresAt,
    this.offerExpiresAt,
    this.subjectFingerprint = '',
    this.serverDomain = '',
    this.rootFingerprint = '',
    this.workspaceName = '',
  });

  factory AttestationOffer.fromJson(Map<String, dynamic> json) {
    final claims = json['claims'];
    final server = json['server'];
    final workspace = json['workspace'];
    String? date(Object? raw) => raw is String && raw.isNotEmpty ? raw : null;
    return AttestationOffer(
      type: json['type'] as String? ?? '',
      label: json['label'] as String? ?? '',
      status: json['status'] as String? ?? 'offered',
      claims: claims is Map<String, dynamic> ? claims : const {},
      expiresAt: date(json['expiresAt']),
      offerExpiresAt: date(json['offerExpiresAt']),
      subjectFingerprint: json['subjectFingerprint'] as String? ?? '',
      serverDomain: server is Map<String, dynamic>
          ? server['domain'] as String? ?? ''
          : '',
      rootFingerprint: server is Map<String, dynamic>
          ? server['rootFingerprint'] as String? ?? ''
          : '',
      workspaceName: workspace is Map<String, dynamic>
          ? workspace['name'] as String? ?? ''
          : '',
    );
  }

  bool get wasAccepted => status == 'active';
  String get title => label.isEmpty ? type : label;
}
