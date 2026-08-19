/// Represents a section from the PocketBase `sections` collection.
class Section {
  final String id;
  final String key;
  final String name;
  final List<String> records;
  final String user;
  final String workspace;
  final String? created;
  final String? updated;

  /// Optional. Set when this section was instantiated as a result of an
  /// inbound public request submission.
  final String? requestedBy;

  Section({
    required this.id,
    required this.key,
    required this.name,
    required this.records,
    required this.user,
    required this.workspace,
    this.created,
    this.updated,
    this.requestedBy,
  });

  factory Section.fromJson(Map<String, dynamic> json) {
    final requestedByRaw = json['requestedBy'];
    return Section(
      id: json['id'] as String,
      key: json['key'] as String,
      name: json['name'] as String,
      records:
          (json['records'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      user: json['user'] as String,
      workspace: json['workspace'] as String,
      created: json['created'] as String?,
      updated: json['updated'] as String?,
      requestedBy: (requestedByRaw is String && requestedByRaw.isNotEmpty)
          ? requestedByRaw
          : null,
    );
  }

  bool get isRequested => requestedBy != null && requestedBy!.isNotEmpty;
}
