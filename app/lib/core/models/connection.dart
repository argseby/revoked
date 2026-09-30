/// A tool the owner connected. It may propose links, see what became of
/// them, and receive the ones it was handed. It never reads the vault, and
/// the connection lapses unless the owner connects the tool again.
class Connection {
  final String id;

  /// The tool's origin — who it is.
  final String clientId;

  /// The name it gives itself; a claim.
  final String clientName;

  /// Whether the tool may revoke the links its proposals became.
  final bool allowRevoke;

  /// Whether the tool may receive links the owner shares with it.
  final bool allowHandOver;

  /// When the connection lapses; connecting the tool again renews it.
  final String? expiresAt;

  final String? lastUsedAt;
  final String? created;

  const Connection({
    required this.id,
    required this.clientId,
    this.clientName = '',
    this.allowRevoke = false,
    this.allowHandOver = false,
    this.expiresAt,
    this.lastUsedAt,
    this.created,
  });

  /// The name to show: the claimed one, else the host it lives on.
  String get name =>
      clientName.isNotEmpty ? clientName : Uri.tryParse(clientId)?.host ?? '';

  /// The host, which is what the tool provably is.
  String get host => Uri.tryParse(clientId)?.host ?? clientId;

  /// Whether the tool's tokens have stopped working.
  bool get isExpired {
    final at = DateTime.tryParse((expiresAt ?? '').replaceFirst(' ', 'T'));
    return at != null && !at.isAfter(DateTime.now());
  }

  factory Connection.fromJson(Map<String, dynamic> json) {
    String? date(String key) {
      final v = json[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    return Connection(
      id: json['id'] as String,
      clientId: json['clientId'] as String? ?? '',
      clientName: json['clientName'] as String? ?? '',
      allowRevoke: json['allowRevoke'] as bool? ?? false,
      allowHandOver: json['allowHandOver'] as bool? ?? false,
      expiresAt: date('expiresAt'),
      lastUsedAt: date('lastUsedAt'),
      created: date('created'),
    );
  }
}
