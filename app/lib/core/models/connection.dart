import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/tool_client.dart';

/// A tool the owner connected. It may propose links, see what became of
/// them, and receive the ones it was handed. It reaches the vault only where
/// the owner allowed it, and the connection lapses unless the owner connects
/// the tool again.
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

  /// Whether the tool may read the values in the vault. Only a new connect
  /// grants it; the owner can withdraw it here.
  final bool allowVaultRead;

  /// The scopes it holds, expanded from the permissions the owner gave it.
  final List<String> scopes;

  /// What it may do in the sections it reaches: `""`, `read` or `write`.
  final String vaultAccess;

  /// Its own section, where it keeps what it writes. Empty when it has none.
  final String section;

  /// Whether the owner switched its own section off, keeping it to give back.
  final bool sectionOff;

  /// Sections the owner added, which it may read and never change.
  final List<String> sections;

  /// The permission keys it holds, as the server last named them. Null when
  /// only [scopes] are known, and they are named from the catalogue instead.
  final List<String>? permissions;

  /// Whether the owner paused it: its tokens are refused until they activate
  /// it again.
  final bool paused;

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
    this.allowVaultRead = false,
    this.scopes = const [],
    this.vaultAccess = '',
    this.sectionOff = false,
    this.section = '',
    this.sections = const [],
    this.permissions,
    this.paused = false,
    this.expiresAt,
    this.lastUsedAt,
    this.created,
  });

  /// The name to show: the claimed one, else the host it lives on.
  String get name =>
      clientName.isNotEmpty ? clientName : Uri.tryParse(clientId)?.host ?? '';

  /// The host, which is what the tool provably is.
  String get host => Uri.tryParse(clientId)?.host ?? clientId;

  /// Whether the tool may use its own section: the owner can take that away
  /// and keep the section, ready to give back.
  bool get hasOwnSection =>
      section.isNotEmpty && !sectionOff && vaultAccess.isNotEmpty;

  /// Whether the tool's tokens have stopped working.
  bool get isExpired {
    final at = DateTime.tryParse((expiresAt ?? '').replaceFirst(' ', 'T'));
    return at != null && !at.isAfter(DateTime.now());
  }

  /// The scopes "End what it proposed" stands for.
  static const endScopes = [
    'link:update',
    'request:update',
    'attestation:update',
  ];

  /// The scope receiving links stands for.
  static const handOverScope = 'link:read';

  /// The permissions a tool may be given, in the catalogue's terms.
  static const toolPermissions = ConnectRequest.toolPermissions;

  /// Every section it reaches: its own first.
  List<String> get reachedSections => [
    if (section.isNotEmpty && !sectionOff) section,
    for (final s in sections)
      if (s != section) s,
  ];

  /// Whether it can read [sectionId]'s records today.
  bool reaches(String sectionId) =>
      vaultAccess.isNotEmpty && reachedSections.contains(sectionId);

  /// The permission keys it holds, named from [catalogue] when the server
  /// has not named them itself.
  List<String> permissionKeys(List<InvitePermission> catalogue) {
    if (permissions != null) {
      return permissions!.where(toolPermissions.contains).toList();
    }
    return [
      for (final key in toolPermissions)
        if (switch (key) {
          'vault:read' => vaultAccess.isNotEmpty,
          'vault:write' => vaultAccess == 'write',
          _ => catalogue.any((p) => p.key == key && p.isSatisfiedBy(scopes)),
        })
          key,
    ];
  }

  /// This connection with what the server answered after a change.
  Connection withGrant(Map<String, dynamic> json) {
    List<String>? list(String key) =>
        (json[key] as List<dynamic>?)?.map((e) => e.toString()).toList();
    return Connection(
      id: id,
      clientId: clientId,
      clientName: clientName,
      allowRevoke: json['allowRevoke'] as bool? ?? allowRevoke,
      allowHandOver: json['allowHandOver'] as bool? ?? allowHandOver,
      allowVaultRead: json['allowVaultRead'] as bool? ?? allowVaultRead,
      scopes: scopes,
      vaultAccess: json['vaultAccess'] as String? ?? vaultAccess,
      section: json['section'] as String? ?? section,
      sectionOff: json['sectionOff'] as bool? ?? sectionOff,
      sections: list('sections') ?? sections,
      permissions: list('permissions') ?? permissions,
      paused: paused,
      expiresAt: expiresAt,
      lastUsedAt: lastUsedAt,
      created: created,
    );
  }

  factory Connection.fromJson(Map<String, dynamic> json) {
    String? date(String key) {
      final v = json[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    List<String> list(String key) => ((json[key] as List<dynamic>?) ?? const [])
        .map((e) => e.toString())
        .toList();
    final scopes = list('scopes');

    return Connection(
      id: json['id'] as String,
      clientId: json['clientId'] as String? ?? '',
      clientName: json['clientName'] as String? ?? '',
      // An older server still stores the two choices as fields of their own.
      allowRevoke:
          json['allowRevoke'] as bool? ?? endScopes.every(scopes.contains),
      allowHandOver:
          json['allowHandOver'] as bool? ?? scopes.contains(handOverScope),
      allowVaultRead: json['allowVaultRead'] as bool? ?? false,
      scopes: scopes,
      vaultAccess: json['vaultAccess'] as String? ?? '',
      section: json['section'] as String? ?? '',
      sectionOff: json['sectionOff'] as bool? ?? false,
      sections: list('sections'),
      paused: json['paused'] as bool? ?? false,
      expiresAt: date('expiresAt'),
      lastUsedAt: date('lastUsedAt'),
      created: date('created'),
    );
  }
}
