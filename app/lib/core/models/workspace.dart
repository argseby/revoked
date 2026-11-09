/// Represents a workspace from the PocketBase `workspaces` collection.
class Workspace {
  final String id;
  final String name;
  final String slug;
  final String? created;
  final String? updated;

  /// Who sees a new item of each area that names no audience, by collection:
  /// `{'links': 'workspace'}` (VISIBILITY.md §4.4). An area left out keeps its
  /// built-in default.
  final Map<String, String> defaultAudience;

  Workspace({
    required this.id,
    required this.name,
    required this.slug,
    this.created,
    this.updated,
    this.defaultAudience = const {},
  });

  /// Built-in defaults: what was private before audiences stays private, what
  /// was workspace data stays the workspace's.
  static const builtInAudience = {
    'records': 'private',
    'sections': 'private',
    'links': 'private',
    'requests': 'private',
    'templates': 'workspace',
    'contacts': 'workspace',
    'attestations': 'workspace',
  };

  /// Who sees a new item of [collection] here.
  String audienceFor(String collection) =>
      defaultAudience[collection] ?? builtInAudience[collection] ?? 'private';

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      created: json['created'] as String?,
      updated: json['updated'] as String?,
      defaultAudience: {
        if (json['defaultAudience'] case final Map<String, dynamic> m)
          for (final e in m.entries)
            if (e.value == 'private' || e.value == 'workspace')
              e.key: e.value as String,
      },
    );
  }
}
