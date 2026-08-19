/// Represents a template from the PocketBase `templates` collection.
class Template {
  final String id;
  final String name;
  final String workspace;
  final Map<String, dynamic> schema;
  final DateTime created;
  final DateTime updated;

  Template({
    required this.id,
    required this.name,
    required this.workspace,
    required this.schema,
    required this.created,
    required this.updated,
  });

  factory Template.fromJson(Map<String, dynamic> json) {
    return Template(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
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
