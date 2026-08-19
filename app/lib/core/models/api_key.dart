/// Represents an API key from the PocketBase `apiKeys` collection.
class ApiKey {
  final String id;
  final String label;
  final String token; // hashed on server, only plain on creation
  final String user;
  final String workspace;
  final List<String> scopes;
  final String? lastUsedAt;

  /// Empty when the key never expires.
  final String? expiresAt;
  final String? created;
  final String? updated;

  /// Only set when the key is first created (from X-Plain-Token header).
  final String? plainToken;

  ApiKey({
    required this.id,
    required this.label,
    required this.token,
    required this.user,
    required this.workspace,
    required this.scopes,
    this.lastUsedAt,
    this.expiresAt,
    this.created,
    this.updated,
    this.plainToken,
  });

  factory ApiKey.fromJson(Map<String, dynamic> json, {String? plainToken}) {
    return ApiKey(
      id: json['id'] as String,
      label: json['label'] as String,
      token: json['token'] as String? ?? '',
      user: json['user'] as String,
      workspace: json['workspace'] as String,
      scopes: (json['scopes'] as List<dynamic>?)?.cast<String>() ?? [],
      lastUsedAt: json['lastUsedAt'] as String?,
      expiresAt: (json['expiresAt'] as String?)?.isEmpty ?? true
          ? null
          : json['expiresAt'] as String?,
      created: json['created'] as String?,
      updated: json['updated'] as String?,
      plainToken: plainToken,
    );
  }

  bool get neverExpires => expiresAt == null;
}
