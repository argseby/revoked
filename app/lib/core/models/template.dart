import 'package:revoked_app/core/models/audience.dart';

/// Represents a template from the PocketBase `templates` collection.
class Template {
  final String id;
  final String name;
  final String description;
  final String workspace;
  final Map<String, dynamic> schema;
  final DateTime created;
  final DateTime updated;

  /// Who made it; empty on older templates and built-ins, which stay with
  /// the workspace.
  final String owner;

  /// Who sees it beside its owner: `private`, `workspace` or `groups`.
  final String audienceKind;

  /// Whether the members who see it may also change it: `owner` or
  /// `audience`.
  final String editing;

  Template({
    required this.id,
    required this.name,
    required this.description,
    required this.workspace,
    required this.schema,
    required this.created,
    required this.updated,
    this.owner = '',
    this.audienceKind = 'workspace',
    this.editing = 'audience',
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
      owner: json['user'] as String? ?? '',
      // Templates were workspace data: one that says nothing is shared.
      audienceKind: json['audienceKind'] == null
          ? 'workspace'
          : audienceKindFrom(json['audienceKind']),
      editing: json['editing'] == 'owner' ? 'owner' : 'audience',
    );
  }
}
