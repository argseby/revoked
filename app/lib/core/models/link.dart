/// Represents a public link from the PocketBase `links` collection.
class Link {
  final String id;
  final String slug;
  final String label;
  final List<String> sections;
  final List<String> records;
  final String user;
  final String workspace;
  final String status; // active, paused, revoked, expired
  final String? created;
  final String? updated;

  /// Server-tracked, optionally bumped by the public viewer route.
  final int viewCount;

  /// Optional cap. 0 = unlimited.
  final int maxViews;

  /// Absolute ISO datetime; null/empty when there is no expiry.
  final String? expiresAt;

  /// Whether the public viewer is required to hold a handshake token.
  final bool requireHandshake;

  /// Whether the link is password-gated. The real hash is never sent: the
  /// owner-facing API masks it to a fixed placeholder when set and to empty
  /// when not, so a non-empty `password` field means "has a password". The
  /// public probe also exposes this as `requiresPassword`.
  final bool hasPassword;

  /// Optional identity that signs this link.
  final String? identity;

  /// The request this link answers, when it was minted by approving one.
  /// Empty for a manually-created share.
  final String request;

  Link({
    required this.id,
    required this.slug,
    required this.label,
    required this.sections,
    required this.records,
    required this.user,
    required this.workspace,
    required this.status,
    this.created,
    this.updated,
    this.viewCount = 0,
    this.maxViews = 0,
    this.expiresAt,
    this.requireHandshake = false,
    this.hasPassword = false,
    this.identity,
    this.request = '',
  });

  /// Legacy alias used by older UI code. Prefer [viewCount].
  int get views => viewCount;

  /// True when this link was created by approving a request (vs a manual share).
  bool get isFromRequest => request.isNotEmpty;

  factory Link.fromJson(Map<String, dynamic> json) {
    // The owner-facing API exposes `viewCount` (new). Older clients may
    // see `views`. Read both for safety.
    final viewCount =
        (json['viewCount'] as num?)?.toInt() ??
        (json['views'] as num?)?.toInt() ??
        0;
    final maxViews = (json['maxViews'] as num?)?.toInt() ?? 0;
    final expiresAtRaw = json['expiresAt'];
    final expiresAt = (expiresAtRaw is String && expiresAtRaw.isNotEmpty)
        ? expiresAtRaw
        : null;
    final passwordValue = json['password'];
    final hasPassword = passwordValue is String && passwordValue.isNotEmpty;

    return Link(
      id: json['id'] as String,
      slug: json['slug'] as String,
      label: json['label'] as String,
      sections:
          (json['sections'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      records:
          (json['records'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      user: json['user'] as String? ?? '',
      workspace: json['workspace'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      created: json['created'] as String?,
      updated: json['updated'] as String?,
      viewCount: viewCount,
      maxViews: maxViews,
      expiresAt: expiresAt,
      requireHandshake: json['requireHandshake'] as bool? ?? false,
      hasPassword: hasPassword,
      identity: json['identity'] as String?,
      request: json['request'] as String? ?? '',
    );
  }

  Link copyWith({
    String? id,
    String? slug,
    String? label,
    List<String>? sections,
    List<String>? records,
    String? user,
    String? workspace,
    String? status,
    String? created,
    String? updated,
    int? viewCount,
    int? maxViews,
    String? expiresAt,
    bool? requireHandshake,
    bool? hasPassword,
    String? identity,
    String? request,
  }) {
    return Link(
      id: id ?? this.id,
      slug: slug ?? this.slug,
      label: label ?? this.label,
      sections: sections ?? this.sections,
      records: records ?? this.records,
      user: user ?? this.user,
      workspace: workspace ?? this.workspace,
      status: status ?? this.status,
      created: created ?? this.created,
      updated: updated ?? this.updated,
      viewCount: viewCount ?? this.viewCount,
      maxViews: maxViews ?? this.maxViews,
      expiresAt: expiresAt ?? this.expiresAt,
      requireHandshake: requireHandshake ?? this.requireHandshake,
      hasPassword: hasPassword ?? this.hasPassword,
      identity: identity ?? this.identity,
      request: request ?? this.request,
    );
  }
}
