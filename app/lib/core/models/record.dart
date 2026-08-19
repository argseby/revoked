/// Represents a record from the PocketBase `records` collection.
///
/// Two row shapes share this collection:
///   - Primary record: holds `value`, `aliasOf` is empty.
///   - Alias record: `aliasOf` points at a primary record id, `value` is
///     intentionally empty (the value resolves through the parent at read
///     time). Aliases keep their own `key`, `label`, `type`, `format` so the
///     UI can present them as first-class items grouped under the parent.
class Record {
  final String id;
  final String key;
  final String value;
  final String label;
  final String type; // 'text' | 'number'
  final String format; // 'hidden' | 'default'
  final String user;
  final String workspace;
  final String? created;
  final String? updated;

  /// Optional. Set when this record was instantiated as a result of an
  /// inbound public request submission; surfaces the responder's name
  /// or identifier in the vault UI.
  final String? requestedBy;

  /// Optional. When non-null this row is an alias and its `value` is
  /// always empty — the real value lives on the referenced parent.
  final String? aliasOf;

  Record({
    required this.id,
    required this.key,
    required this.value,
    required this.label,
    required this.type,
    required this.format,
    required this.user,
    required this.workspace,
    this.created,
    this.updated,
    this.requestedBy,
    this.aliasOf,
  });

  factory Record.fromJson(Map<String, dynamic> json) {
    final requestedByRaw = json['requestedBy'];
    final aliasRaw = json['aliasOf'];
    return Record(
      id: json['id'] as String,
      key: json['key'] as String,
      value: json['value'] as String? ?? '',
      label: json['label'] as String,
      type: json['type'] as String,
      format: json['format'] as String,
      user: json['user'] as String,
      workspace: json['workspace'] as String,
      created: json['created'] as String?,
      updated: json['updated'] as String?,
      requestedBy: (requestedByRaw is String && requestedByRaw.isNotEmpty)
          ? requestedByRaw
          : null,
      aliasOf: (aliasRaw is String && aliasRaw.isNotEmpty) ? aliasRaw : null,
    );
  }

  bool get isHidden => format == 'hidden';
  bool get isRequested => requestedBy != null && requestedBy!.isNotEmpty;
  bool get isAlias => aliasOf != null && aliasOf!.isNotEmpty;
}
