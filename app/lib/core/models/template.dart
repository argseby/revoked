/// Represents a template from the PocketBase `templates` collection.
class Template {
  final String id;
  final String name;
  final String description;
  final String workspace;
  final Map<String, dynamic> schema;
  final DateTime created;
  final DateTime updated;

  Template({
    required this.id,
    required this.name,
    required this.description,
    required this.workspace,
    required this.schema,
    required this.created,
    required this.updated,
  });

  /// Built-in templates are seeded by the server for every workspace; they
  /// carry no workspace relation and cannot be edited or deleted.
  bool get isBuiltin => workspace.isEmpty;

  factory Template.fromJson(Map<String, dynamic> json) {
    return Template(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      workspace: json['workspace'] as String? ?? '',
      schema: json['schema'] is Map
          ? json['schema'] as Map<String, dynamic>
          : {},
      created: DateTime.parse(
        json['created'] as String? ?? DateTime.now().toIso8601String(),
      ),
      updated: DateTime.parse(
        json['updated'] as String? ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}
