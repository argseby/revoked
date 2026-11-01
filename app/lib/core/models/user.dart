/// Represents a user from the PocketBase `users` collection.
class User {
  final String id;
  final String email;
  final bool verified;
  final String? avatar;
  final String? activeWorkspace;
  final String? activeRole;
  final String? created;
  final String? updated;

  User({
    required this.id,
    required this.email,
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
      verified: json['verified'] as bool? ?? false,
      avatar: json['avatar'] as String?,
      activeWorkspace: json['activeWorkspace'] as String?,
      activeRole: json['activeRole'] as String?,
      created: json['created'] as String?,
      updated: json['updated'] as String?,
    );
  }
}
