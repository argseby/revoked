import 'package:revoked_app/core/state/observable_text_controller.dart';

import 'package:revoked_app/features/vault/utils/record_type_utils.dart';

/// through the visual builder never drops metadata authored in JSON mode.
class TemplateFieldDraft {
  final ObservableTextController labelCtrl;
  final ObservableTextController keyCtrl;
  String type;
  bool required;

  // Preserved verbatim from JSON; the visual builder doesn't edit these but
  // must not silently discard them on save.
  String format;
  String reason;
  String value;

  TemplateFieldDraft({
    String label = '',
    String key = '',
    this.type = 'text',
    this.required = false,
    this.format = 'default',
    this.reason = '',
    this.value = '',
  }) : labelCtrl = ObservableTextController(text: label),
       keyCtrl = ObservableTextController(text: key);

  factory TemplateFieldDraft.fromMap(Map<dynamic, dynamic> m) {
    final rawType = (m['type'] as String? ?? 'text').trim();
    return TemplateFieldDraft(
      label: (m['label'] as String? ?? '').trim(),
      key: (m['key'] as String? ?? '').trim(),
      type: RecordTypeUtils.supportedTypes.contains(rawType) ? rawType : 'text',
      required: m['required'] as bool? ?? false,
      format: (m['format'] as String? ?? 'default').trim(),
      reason: (m['reason'] as String? ?? '').trim(),
      value: (m['value'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() => {
    'label': labelCtrl.text.trim(),
    'key': keyCtrl.text.trim(),
    'type': type,
    'format': format,
    'required': required,
    'reason': reason,
    if (value.isNotEmpty) 'value': value,
  };

  void dispose() {
    labelCtrl.dispose();
    keyCtrl.dispose();
  }
}

/// Mutable in-memory model for one section (named group of fields).
class TemplateSectionDraft {
  final ObservableTextController nameCtrl;
  final ObservableTextController keyCtrl;
  final List<TemplateFieldDraft> fields;

  TemplateSectionDraft({
    String name = '',
    String key = '',
    List<TemplateFieldDraft>? fields,
  }) : nameCtrl = ObservableTextController(text: name),
       keyCtrl = ObservableTextController(text: key),
       fields = fields ?? [];

  factory TemplateSectionDraft.fromMap(Map<dynamic, dynamic> m) {
    final rawRecords = m['records'] as List<dynamic>? ?? const [];
    return TemplateSectionDraft(
      name: (m['name'] as String? ?? '').trim(),
      key: (m['key'] as String? ?? '').trim(),
      fields: rawRecords
          .whereType<Map>()
          .map((r) => TemplateFieldDraft.fromMap(r))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': nameCtrl.text.trim(),
    'key': keyCtrl.text.trim(),
    'records': fields.map((f) => f.toMap()).toList(),
  };

  void dispose() {
    nameCtrl.dispose();
    keyCtrl.dispose();
    for (final f in fields) {
      f.dispose();
    }
  }
}
