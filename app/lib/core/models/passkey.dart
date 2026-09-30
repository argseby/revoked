/// One authenticator the account can sign in with. The key itself never
/// leaves the server; this is what tells the owner's passkeys apart.
class Passkey {
  final String id;

  /// Where it was made — "Safari on Mac" — as the sign-in page named it.
  final String name;

  final String? created;
  final String? lastUsedAt;

  const Passkey({
    required this.id,
    this.name = '',
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
      created: date('created'),
      lastUsedAt: date('lastUsedAt'),
    );
  }
}
