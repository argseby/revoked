/// One entry on the public request probe's `template` payload, returned
/// by `GET /api/public/requests/:slug`. Mirrors the (flattened) shape of
/// the referenced `templates.schema` JSON — each entry can be a leaf
/// record or a section that nests its own records.
class RequestTemplateItem {
  /// Slug-style key the responder is expected to fill in. For sections
  /// this is the section's own key (its children carry their own keys).
  final String key;

  /// Human-friendly label rendered above the input.
  final String label;

  /// 'text' or 'number'. Empty for section entries.
  final String type;

  /// 'hidden' or 'default'. Empty for section entries.
  final String format;

  /// When true the responder cannot remove the field and must supply a
  /// non-empty value (server enforces with code request_required_missing).
  final bool required;

  /// Optional explanation from the requester rendered alongside the field
  /// so the responder understands why this entry was demanded.
  final String reason;

  /// Populated only for section entries; the leaf records grouped under
  /// this section.
  final List<RequestTemplateItem> records;

  const RequestTemplateItem({
    required this.key,
    required this.label,
    this.type = '',
    this.format = '',
    this.required = false,
    this.reason = '',
    this.records = const [],
  });

  factory RequestTemplateItem.fromJson(Map<String, dynamic> json) {
    final children = <RequestTemplateItem>[];
    if (json['records'] is List) {
      for (final raw in (json['records'] as List)) {
        if (raw is Map<String, dynamic>) {
          children.add(RequestTemplateItem.fromJson(raw));
        }
      }
    }
    return RequestTemplateItem(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      type: json['type'] as String? ?? '',
      format: json['format'] as String? ?? '',
      required: json['required'] as bool? ?? false,
      reason: json['reason'] as String? ?? '',
      records: children,
    );
  }

  bool get isSection => records.isNotEmpty;
  bool get isRecord => !isSection;
}
