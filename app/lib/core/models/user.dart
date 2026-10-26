/// Represents a user from the PocketBase `users` collection.
class User {
  final String id;
  final String email;

  /// The account's own name: what a service gets under the `profile` scope
  /// when someone signs in there with Revoked. Empty until it is set; the
  /// server then falls back to the main identity's name.
  final String name;
  final bool verified;
  final String? avatar;
  final String? activeWorkspace;
  final String? activeRole;
  final String? created;
  final String? updated;

  User({
    required this.id,
    required this.email,
    this.name = '',
    this.verified = false,
    this.avatar,
    this.activeWorkspace,
    this.activeRole,
    this.created,
    this.updated,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      verified: json['verified'] as bool? ?? false,
      avatar: json['avatar'] as String?,
      activeWorkspace: json['activeWorkspace'] as String?,
      activeRole: json['activeRole'] as String?,
      created: json['created'] as String?,
      updated: json['updated'] as String?,
    );
  }
}
