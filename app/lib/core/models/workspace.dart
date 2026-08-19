/// Represents a workspace from the PocketBase `workspaces` collection.
class Workspace {
  final String id;
  final String name;
  final String slug;
  final String? created;
  final String? updated;

  Workspace({
    required this.id,
    required this.name,
    required this.slug,
    this.created,
    this.updated,
  });

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      created: json['created'] as String?,
      updated: json['updated'] as String?,
    );
  }
}
