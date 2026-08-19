/// Represents a request from the PocketBase `requests` collection.
///
/// Schema introduced by migration 000020. The owning workspace defines a
/// request, distributes the public slug to senders, and receives
/// submissions through the `/api/public/requests/:slug` endpoint.
///
/// Gating:
///   - `password` (hashed server-side, stripped from responses)
///   - `expiresAt` (auto-expire)
///   - `maxResponses` (auto-complete)
///   - `identifier` (sender must echo back this value)
///   - `requireHandshake` (sender must pin a cryptographic identity)
class DataRequest {
  final String id;
  final String slug;
  final String label;
  final String status; // active, paused, revoked, expired, completed
  final String identity;
  final String templateId;
  final bool hasPassword;
  final String? expiresAt;
  final int maxResponses;
  final int responseCount;
  final String identifier;
  final String callbackUrl;
  final bool requireHandshake;
  final String identityScope; // 'any' | 'from_root'
  final bool allowExtraFields;
  final String user;
  final String workspace;
  final String? created;
  final String? updated;

  DataRequest({
    required this.id,
    required this.slug,
    required this.label,
    required this.status,
    required this.identity,
    this.templateId = '',
    this.hasPassword = false,
    this.expiresAt,
    this.maxResponses = 0,
    this.responseCount = 0,
    this.identifier = '',
    this.callbackUrl = '',
    this.requireHandshake = false,
    this.identityScope = 'any',
    this.allowExtraFields = false,
    required this.user,
    required this.workspace,
    this.created,
    this.updated,
  });

  factory DataRequest.fromJson(Map<String, dynamic> json) {
    final passwordValue = json['password'];
    final expRaw = json['expiresAt'];
    return DataRequest(
      id: json['id'] as String,
      slug: json['slug'] as String? ?? '',
      // Some older payloads used `title` instead of `label`.
      label: (json['label'] as String?) ?? (json['title'] as String?) ?? '',
      status: json['status'] as String? ?? 'active',
      identity: json['identity'] as String? ?? '',
      templateId: json['template'] as String? ?? '',
      hasPassword: passwordValue is String && passwordValue.isNotEmpty,
      expiresAt: (expRaw is String && expRaw.isNotEmpty) ? expRaw : null,
      maxResponses: (json['maxResponses'] as num?)?.toInt() ?? 0,
      responseCount: (json['responseCount'] as num?)?.toInt() ?? 0,
      identifier: json['identifier'] as String? ?? '',
      callbackUrl: json['callbackUrl'] as String? ?? '',
      requireHandshake: json['requireHandshake'] as bool? ?? false,
      identityScope: json['identityScope'] as String? ?? 'any',
      allowExtraFields: json['allowExtraFields'] as bool? ?? false,
      user: json['user'] as String? ?? '',
      workspace: json['workspace'] as String? ?? '',
      created: json['created'] as String?,
      updated: json['updated'] as String?,
    );
  }

  DataRequest copyWith({
    String? id,
    String? slug,
    String? label,
    String? status,
    String? identity,
    String? templateId,
    bool? hasPassword,
    String? expiresAt,
    int? maxResponses,
    int? responseCount,
    String? identifier,
    String? callbackUrl,
    bool? requireHandshake,
    String? identityScope,
    bool? allowExtraFields,
    String? user,
    String? workspace,
    String? created,
    String? updated,
  }) {
    return DataRequest(
      id: id ?? this.id,
      slug: slug ?? this.slug,
      label: label ?? this.label,
      status: status ?? this.status,
      identity: identity ?? this.identity,
      templateId: templateId ?? this.templateId,
      hasPassword: hasPassword ?? this.hasPassword,
      expiresAt: expiresAt ?? this.expiresAt,
      maxResponses: maxResponses ?? this.maxResponses,
      responseCount: responseCount ?? this.responseCount,
      identifier: identifier ?? this.identifier,
      callbackUrl: callbackUrl ?? this.callbackUrl,
      requireHandshake: requireHandshake ?? this.requireHandshake,
      identityScope: identityScope ?? this.identityScope,
      allowExtraFields: allowExtraFields ?? this.allowExtraFields,
      user: user ?? this.user,
      workspace: workspace ?? this.workspace,
      created: created ?? this.created,
      updated: updated ?? this.updated,
    );
  }
}
