/// A service the person signed in to with Revoked: where, when, and what it
/// has learned. Each sign-in adds to the same row, so what a service once
/// learned stays listed.
class SignInService {
  final String id;

  /// The service's origin — who it is.
  final String clientId;

  /// The scopes it has learned, as the consent screen offered them.
  final List<String> scopes;

  /// The link its shared entries live in; empty when nothing was shared.
  final String link;

  /// The vault entry its name comes from; empty otherwise.
  final String nameRecord;

  /// The name it gets now. Empty when it gets none, or when the entry can't
  /// be read from this workspace.
  final String name;

  final String? lastSignInAt;
  final String? created;

  /// `active`, `paused` or `disconnected`. A row from before there were
  /// statuses is active.
  final String status;

  final String? disconnectedAt;

  /// Whether the service gets a new ID the next time this person signs in.
  final bool newIdOnReturn;

  const SignInService({
    required this.id,
    required this.clientId,
    this.scopes = const [],
    this.link = '',
    this.nameRecord = '',
    this.name = '',
    this.lastSignInAt,
    this.created,
    this.status = 'active',
    this.disconnectedAt,
    this.newIdOnReturn = false,
  });

  bool get isPaused => status == 'paused';

  bool get isDisconnected => status == 'disconnected';

  /// The host, which is what the service provably is.
  String get host {
    final uri = Uri.tryParse(clientId);
    if (uri == null || uri.host.isEmpty) return clientId;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  factory SignInService.fromJson(Map<String, dynamic> json) {
    String? date(String key) {
      final v = json[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    final expand = json['expand'] as Map<String, dynamic>? ?? const {};
    final identity = expand['nameIdentity'] as Map<String, dynamic>?;
    final entry = expand['nameRecord'] as Map<String, dynamic>?;

    return SignInService(
      id: json['id'] as String,
      clientId: json['clientId'] as String? ?? '',
      scopes: [
        for (final s in json['scopes'] as List<dynamic>? ?? const []) '$s',
      ],
      link: json['link'] as String? ?? '',
      nameRecord: json['nameRecord'] as String? ?? '',
      name: (identity?['name'] ?? entry?['value'] ?? '') as String,
      lastSignInAt: date('lastSignInAt'),
      created: date('created'),
      status: date('status') ?? 'active',
      disconnectedAt: date('disconnectedAt'),
      newIdOnReturn: json['newIdOnReturn'] as bool? ?? false,
    );
  }
}
