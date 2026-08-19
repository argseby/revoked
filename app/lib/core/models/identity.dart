/// A cryptographic identity issued to a user within a workspace: an X.509
/// certificate (public key) plus metadata the backend uses to attribute
/// signed handshakes and requests.
class Identity {
  final String id;
  final String name;

  /// The PEM-encoded X.509 certificate; this is the identity's public key.
  final String certificate;

  /// PEM-encoded private key. Normally null — the server only returns it
  /// transiently at issuance, after which it lives in local secure storage.
  final String? privateKey;

  /// Lowercase hex SHA-256 fingerprint of the certificate, used to pin and
  /// reference the identity across handshake and verification flows.
  final String fingerprint;
  final String user;
  final String workspace;
  final bool isPrimary;

  /// The server domain captured when this identity was issued. Identities
  /// issued by this server carry the server's root domain here; used to tell
  /// "issued by this root" apart from externally-issued identities.
  final String domainAtIssue;
  final String? created;
  final String? updated;

  Identity({
    required this.id,
    required this.name,
    required this.certificate,
    this.privateKey,
    required this.fingerprint,
    required this.user,
    required this.workspace,
    this.isPrimary = false,
    this.domainAtIssue = '',
    this.created,
    this.updated,
  });

  /// Abbreviated fingerprint (first 8 … last 8 hex chars) for display.
  String get shortFingerprint => fingerprint.length > 16
      ? '${fingerprint.substring(0, 8)}...${fingerprint.substring(fingerprint.length - 8)}'
      : fingerprint;

  /// Alias for [certificate]; the certificate is the identity's public key.
  String get publicKey => certificate;

  factory Identity.fromJson(Map<String, dynamic> json) {
    return Identity(
      id: json['id'] as String,
      name: json['name'] as String,
      certificate: json['certificate'] as String,
      privateKey: json['privateKey'] as String?,
      fingerprint: json['fingerprint'] as String,
      user: json['user'] as String,
      workspace: json['workspace'] as String,
      isPrimary: json['isPrimary'] as bool? ?? false,
      domainAtIssue: json['domainAtIssue'] as String? ?? '',
      created: json['created'] as String?,
      updated: json['updated'] as String?,
    );
  }

  /// Returns a copy with the given fields replaced. Used by the store to
  /// flip [isPrimary] without dropping server-set fields like
  /// [domainAtIssue] (which the `from_root` identity scope depends on).
  Identity copyWith({
    String? id,
    String? name,
    String? certificate,
    String? privateKey,
    String? fingerprint,
    String? user,
    String? workspace,
    bool? isPrimary,
    String? domainAtIssue,
    String? created,
    String? updated,
  }) {
    return Identity(
      id: id ?? this.id,
      name: name ?? this.name,
      certificate: certificate ?? this.certificate,
      privateKey: privateKey ?? this.privateKey,
      fingerprint: fingerprint ?? this.fingerprint,
      user: user ?? this.user,
      workspace: workspace ?? this.workspace,
      isPrimary: isPrimary ?? this.isPrimary,
      domainAtIssue: domainAtIssue ?? this.domainAtIssue,
      created: created ?? this.created,
      updated: updated ?? this.updated,
    );
  }
}
