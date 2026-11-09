/// A group of a workspace (HR, Service, Techs) that an item's audience can
/// name (VISIBILITY.md §6), as `GET /api/groups` returns it.
class WorkspaceGroup {
  final String id;
  final String key;
  final String name;

  /// The members in it, by user id, with their address.
  final List<({String id, String email})> members;

  const WorkspaceGroup({
    required this.id,
    required this.key,
    required this.name,
    this.members = const [],
  });

  bool contains(String userId) => members.any((m) => m.id == userId);

  factory WorkspaceGroup.fromJson(Map<String, dynamic> json) => WorkspaceGroup(
    id: json['id'] as String,
    key: json['key'] as String? ?? '',
    name: json['name'] as String? ?? '',
    members: [
      for (final m in (json['members'] as List<dynamic>? ?? const []))
        if (m is Map<String, dynamic>)
          (id: m['id'] as String? ?? '', email: m['email'] as String? ?? ''),
    ],
  );
}
