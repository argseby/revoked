/// Represents a user from the PocketBase `users` collection.
class User {
  final String id;
  final String email;
  final bool verified;
  final String? avatar;
  final String? activeWorkspace;
  final String? activeRole;

  /// The parts of the app this account chose to see, as feature keys. Null
  /// while the account has never chosen, when the catalogue's defaults apply.
  final List<String>? features;
  final String? created;
  final String? updated;

  User({
    required this.id,
    required this.email,
    this.verified = false,
    this.avatar,
    this.activeWorkspace,
    this.activeRole,
    this.features,
    this.created,
    this.updated,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final features = json['features'];
    return User(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      verified: json['verified'] as bool? ?? false,
      avatar: json['avatar'] as String?,
      activeWorkspace: json['activeWorkspace'] as String?,
      activeRole: json['activeRole'] as String?,
      features: features is List
          ? features.map((e) => e.toString()).toList()
          : null,
      created: json['created'] as String?,
      updated: json['updated'] as String?,
    );
  }

  /// The same account with a different feature set.
  User withFeatures(List<String> features) => User(
    id: id,
    email: email,
    verified: verified,
    avatar: avatar,
    activeWorkspace: activeWorkspace,
    activeRole: activeRole,
    features: features,
    created: created,
    updated: updated,
  );
}
