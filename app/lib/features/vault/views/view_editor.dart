import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_menu_button.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/features/vault/views/view_data.dart';
import 'package:revoked_app/features/vault/views/view_renderer.dart';
import 'package:revoked_app/features/vault/views/view_spec.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';

/// A view's code and, under it, the view itself drawn over [data] as it is
/// typed. Empty code means no view: the section shows as a list.
///
/// [onChanged] receives the parsed layout, or null for none. While the code
/// does not parse, it is not called, so a half-typed view never replaces a
/// working one.
class ViewCodeEditor extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final ViewData data;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  /// Views offered to start from, by name.
  final List<Map<String, dynamic>> examples;

  const ViewCodeEditor({
    super.key,
    required this.initial,
    required this.data,
    required this.onChanged,
    this.examples = const [],
  });

  @override
  State<ViewCodeEditor> createState() => _ViewCodeEditorState();
}

String _pretty(Map<String, dynamic> json) =>
    const JsonEncoder.withIndent('  ').convert(json);

class _ViewCodeEditorState extends State<ViewCodeEditor> {
  late final _code = ObservableTextController(
    text: widget.initial == null ? '' : _pretty(widget.initial!),
  );
  late final _spec = Local<ViewSpec?>(
    widget.initial == null ? null : ViewSpec.parse(widget.initial!),
  );
  final _problem = Local<String?>(null);

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _read(String text) {
    if (text.trim().isEmpty) {
      _spec.value = null;
      _problem.value = null;
      widget.onChanged(null);
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      _problem.value =
          'Not valid JSON yet: a bracket, comma or quote may be '
          'missing.';
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      _problem.value = 'A view is a JSON object: { … }.';
      return;
    }
    final spec = ViewSpec.parse(decoded);
    if (spec == null) {
      _problem.value =
          'A view needs "version": $viewFormatVersion, an "id", the record '
          'keys it "match"es and at least one known block.';
      return;
    }
    _problem.value = null;
    _spec.value = spec;
    widget.onChanged(decoded);
  }

  void _use(Map<String, dynamic> json) {
    _code.text = _pretty(json);
    _read(_code.text);
  }

  @override
  Widget build(BuildContext context) => Observer(builder: _build);

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spec = _spec.value;
    final problem = _problem.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (widget.examples.isNotEmpty)
              AppMenuButton(
                icon: AppIcons.stars,
                label: 'Start from…',
                tooltip: 'Start from an existing view',
                style: AppButtonStyle.outline,
                size: AppButtonSize.small,
                items: [
                  for (final e in widget.examples)
                    AppMenuItem(
                      icon: viewIcon(_firstIcon(e)),
                      label: e['name'] is String ? e['name'] as String : '',
                      onSelected: () => _use(e),
                    ),
                ],
              ),
            if (spec != null)
              AppButton(
                icon: AppIcons.code,
                label: 'Tidy',
                style: AppButtonStyle.ghost,
                size: AppButtonSize.small,
                onTap: () {
                  final decoded = jsonDecode(_code.text);
                  if (decoded is Map<String, dynamic>) _use(decoded);
                },
              ),
            if (_code.text.trim().isNotEmpty)
              AppButton(
                icon: AppIcons.trash,
                label: 'Remove view',
                style: AppButtonStyle.ghost,
                size: AppButtonSize.small,
                onTap: () {
                  _code.clear();
                  _read('');
                },
              ),
          ],
        ),
        AppSpacing.gapMd,
        AppTextField(
          controller: _code,
          hint: '{ "version": 1, "id": "…", "match": ["…"], "blocks": [ … ] }',
          mono: true,
          minLines: 8,
          maxLines: 20,
          onChanged: _read,
        ),
        AppSpacing.gapSm,
        if (problem != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AppIcons.exclamationTriangle,
                size: 16,
                color: scheme.warning,
              ),
              AppSpacing.gapSm,
              Expanded(child: Text(problem).small),
            ],
          )
        else
          Text(
            spec == null
                ? 'No view: the section shows as a list of records.'
                : 'Valid · ${spec.name} · ${spec.blocks.length} '
                      '${spec.blocks.length == 1 ? 'block' : 'blocks'}',
          ).small.muted,
        if (spec != null) ...[
          AppSpacing.gapLg,
          const Text('Preview').small.bold,
          AppSpacing.gapSm,
          ViewRenderer(
            spec: spec,
            // Before the section holds any record, the preview fills each
            // key the view names with its own name.
            data: widget.data.isEmpty
                ? ViewData.sample(
                    jsonDecode(_code.text) as Map<String, dynamic>,
                  )
                : widget.data,
          ),
        ],
      ],
    );
  }

  static String _firstIcon(Map<String, dynamic> view) {
    for (final b in (view['blocks'] as List?) ?? const []) {
      if (b is Map && b['type'] == 'header' && b['icon'] is String) {
        return b['icon'] as String;
      }
      if (b is Map && b['type'] == 'split') {
        for (final inner in (b['main'] as List?) ?? const []) {
          if (inner is Map && inner['icon'] is String) {
            return inner['icon'] as String;
          }
        }
      }
    }
    return 'folder';
  }
}

/// Stand-in records for a template's fields, so its view can be previewed
/// before anyone fills it in: each field's default value, or a sample of its
/// type.
ViewData sampleViewData(Map<String, dynamic> schema) {
  final soon = DateTime.now().add(const Duration(days: 20));
  String sample(Map field) {
    final value = field['value'];
    if (value is String && value.isNotEmpty) return value;
    final label = field['label'] is String ? field['label'] as String : '';
    final key = field['key'] is String ? field['key'] as String : '';
    return switch (field['type']) {
      'number' => '12',
      'url' => 'https://example.com',
      'boolean' => 'true',
      'datetime' => soon.toIso8601String(),
      _ when RegExp(r'-(morning|evening)$').hasMatch(key) => '1',
      _ => label.isEmpty ? key : label,
    };
  }

  final fields = <Map>[
    for (final r in (schema['records'] as List?) ?? const [])
      if (r is Map) r,
    for (final s in (schema['sections'] as List?) ?? const [])
      if (s is Map)
        for (final r in (s['records'] as List?) ?? const [])
          if (r is Map) r,
  ];
  return ViewData(
    section: [
      for (final f in fields)
        if (f['key'] is String && f['type'] != 'file')
          models.Record(
            id: 'sample-${f['key']}',
            key: f['key'] as String,
            value: sample(f),
            label: f['label'] is String ? f['label'] as String : '',
            type: f['type'] is String ? f['type'] as String : 'text',
            format: f['format'] == 'hidden' ? 'hidden' : 'default',
            user: '',
            workspace: '',
          ),
    ],
  );
}
