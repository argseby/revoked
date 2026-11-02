import 'dart:typed_data';

/// One authenticator the account can sign in with. The key itself never
/// leaves the server; this is what tells the owner's passkeys apart.
class Passkey {
  final String id;

  /// Where it was made — "Safari on Mac" — as the sign-in page named it.
  final String name;

  /// The credential's id, which is how its device list entry names it.
  final String credentialId;

  final String? created;
  final String? lastUsedAt;

  const Passkey({
    required this.id,
    this.name = '',
    this.credentialId = '',
    this.created,
    this.lastUsedAt,
  });

  String get title => name.isEmpty ? 'Passkey' : name;

  factory Passkey.fromJson(Map<String, dynamic> json) {
    String? date(String key) {
      final v = json[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    return Passkey(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      credentialId: json['credentialId'] as String? ?? '',
      created: date('created'),
      lastUsedAt: date('lastUsedAt'),
    );
  }
}

/// What a passkey sign-in brought back besides the session: which passkey it
/// was, and the secret its PRF extension derived, when the authenticator gave
/// one. The secret lives in memory only and derives this account's encryption
/// keys (E2EE.md §6.8).
class PasskeySignIn {
  final String user;
  final String credentialId;
  final String name;

  /// Null when the authenticator gave none, or an older sign-in page never
  /// asked; [asked] tells the two apart.
  final Uint8List? secret;
  final bool asked;

  const PasskeySignIn({
    required this.user,
    required this.credentialId,
    required this.name,
    required this.secret,
    required this.asked,
  });

  bool get holdsSecret => secret != null;
}
