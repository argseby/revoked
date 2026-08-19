import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_entity_card.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_select.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_switch.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/api/api_request_spec.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/templates/store/templates_store.dart';

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authStore = Stores.auth;
      if (authStore.isAuthenticated) {
        Stores.templates.loadTemplates(authStore.activeWorkspace ?? '');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authStore = Stores.auth;
    final settingsStore = Stores.settings;
    final templatesStore = Stores.templates;

    final outerPad = AppSpacing.screenH(context);
    final horizontalPad = EdgeInsets.symmetric(horizontal: outerPad);

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: horizontalPad,
            child: Observer(
              builder: (context) {
                final activeWorkspaceId = authStore.activeWorkspace ?? '';
                final userRole = settingsStore.getRoleForWorkspace(
                  activeWorkspaceId,
                );
                final isAdmin = userRole == 'admin';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: [
                        AppButton(
                          icon: AppIcons.chevronLeft,
                          tooltip: 'Back',
                          style: AppButtonStyle.accent,
                          onTap: () => context.go(AppRoutes.settings),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Templates').header,
                              const Text(
                                'Structural blueprints for creating sections and records.',
                              ).muted.small,
                            ],
                          ),
                        ),
                        if (isAdmin)
                          AppButton(
                            icon: AppIcons.plus,
                            tooltip: 'New template',
                            onTap: () => _showCreateTemplateSheet(
                              context,
                              templatesStore,
                              authStore,
                            ),
                          )
                        else
                          const AppBadge(
                            label: 'Read-Only',
                            variant: AppBadgeVariant.outline,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const AppDivider(spaced: true),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                );
              },
            ),
          ),

          Expanded(
            child: Padding(
              padding: horizontalPad,
              child: Observer(
                builder: (context) {
                  final activeWorkspaceId = authStore.activeWorkspace ?? '';
                  final userRole = settingsStore.getRoleForWorkspace(
                    activeWorkspaceId,
                  );
                  final isAdmin = userRole == 'admin';

                  final _ = templatesStore.errorMessage;
                  if (templatesStore.isLoading &&
                      templatesStore.templates.isEmpty) {
                    return const Center(child: AppSpinner(large: true));
                  }

                  if (templatesStore.templates.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            AppIcons.cardList,
                            size: 40,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const Text('No templates'),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            isAdmin
                                ? 'Create a template to define shared structure.'
                                : 'Contact your workspace admin to add structural templates.',
                          ).muted.small,
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: AppSpacing.huge),
                    itemCount: templatesStore.templates.length,
                    itemBuilder: (context, index) {
                      final template = templatesStore.templates[index];
                      return _TemplateCard(
                        template: template,
                        isAdmin: isAdmin,
                        onEdit: () => _showCreateTemplateSheet(
                          context,
                          templatesStore,
                          authStore,
                          initialTemplate: template,
                        ),
                        onDelete: () => _confirmDeleteTemplate(
                          context,
                          templatesStore,
                          template.id,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateTemplateSheet(
    BuildContext context,
    TemplatesStore templatesStore,
    AuthStore authStore, {
    Template? initialTemplate,
  }) {
    showAppSheet(
      context: context,
      builder: (sheetContext) => _TemplateEditorSheet(
        templatesStore: templatesStore,
        authStore: authStore,
        initialTemplate: initialTemplate,
      ),
    );
  }

  Future<void> _confirmDeleteTemplate(
    BuildContext context,
    TemplatesStore templatesStore,
    String templateId,
  ) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete template',
      message:
          'Are you sure you want to permanently delete this template? '
          'Existing vault items created from this template will not be '
          'affected.',
      content: ApiPreview(
        spec: Stores.templates.deleteTemplateSpec(templateId),
        title: 'API request · delete',
      ),
      confirmLabel: 'Delete permanently',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await templatesStore.deleteTemplate(templateId);
    if (ok && context.mounted) {
      AppToast.success(context, 'Template permanently deleted');
    }
  }
}

class _TemplateCard extends StatelessWidget {
  final Template template;
  final bool isAdmin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TemplateCard({
    required this.template,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = template.schema['sections'] as List<dynamic>? ?? [];
    final records = template.schema['records'] as List<dynamic>? ?? [];

    return AppEntityCard(
      icon: AppIcons.cardList,
      title: template.name,
      tags: [
        AppBadge(
          icon: AppIcons.folderSymlink,
          label: '${records.length} records',
        ),
        AppBadge(icon: AppIcons.folder, label: '${sections.length} sections'),
        if (!isAdmin)
          const AppBadge(label: 'Read-only', variant: AppBadgeVariant.outline),
      ],
      expandedBody: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Blueprint structure').small.muted,
          const SizedBox(height: AppSpacing.sm),
          const SizedBox(height: AppSpacing.sm),
          if (records.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xxs,
                bottom: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    AppIcons.folderSymlink,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Text('Root Records').small.muted,
                ],
              ),
            ),
            ...records.map((rec) {
              final r = rec as Map<String, dynamic>? ?? {};
              return _TemplateRecordRow(raw: r, indent: 16);
            }),
          ],
          if (sections.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            ...sections.map((sec) {
              final s = sec as Map<String, dynamic>? ?? {};
              final name = s['name'] as String? ?? 'Section';
              final key = s['key'] as String? ?? '';
              final secRecords = s['records'] as List<dynamic>? ?? [];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.xxs,
                      top: AppSpacing.xxs,
                      bottom: AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          AppIcons.folder,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text('$name ($key)').small,
                      ],
                    ),
                  ),
                  if (secRecords.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.xxl,
                        bottom: AppSpacing.sm,
                      ),
                      child: const Text(
                        'No records in this section',
                      ).muted.small,
                    )
                  else
                    ...secRecords.map((rec) {
                      final r = rec as Map<String, dynamic>? ?? {};
                      return _TemplateRecordRow(raw: r, indent: 24);
                    }),
                ],
              );
            }),
          ],
        ],
      ),
      actions: [
        if (isAdmin) ...[
          AppSheetAction(
            icon: AppIcons.pencil,
            label: 'Edit',
            primary: true,
            onTap: onEdit,
          ),
          AppSheetAction(
            icon: AppIcons.trash,
            label: 'Delete',
            destructive: true,
            onTap: onDelete,
          ),
        ],
      ],
    );
  }
}

/// Compact row that renders one template record entry with the new
/// `required` + `reason` metadata surfaced as a badge + subtitle. Used
/// for both root-level records and section children.
class _TemplateRecordRow extends StatelessWidget {
  final Map<String, dynamic> raw;
  final double indent;

  const _TemplateRecordRow({required this.raw, required this.indent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = raw['label'] as String? ?? 'Record';
    final key = raw['key'] as String? ?? '';
    final type = raw['type'] as String? ?? 'text';
    final format = raw['format'] as String? ?? 'default';
    final required = raw['required'] as bool? ?? false;
    final reason = raw['reason'] as String? ?? '';

    return Container(
      margin: EdgeInsets.only(left: indent, bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppRadius.allSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                type == 'number' ? AppIcons.hash : AppIcons.fileText,
                size: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('$label ($key)').small.mono),
              const SizedBox(width: AppSpacing.xs),
              AppBadge(label: type),
              if (format == 'hidden') ...[
                const SizedBox(width: AppSpacing.xxs),
                const AppBadge(
                  label: 'hidden',
                  variant: AppBadgeVariant.outline,
                ),
              ],
              if (required) ...[
                const SizedBox(width: AppSpacing.xxs),
                const AppBadge(label: 'REQ', variant: AppBadgeVariant.primary),
              ],
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xl),
              child: Text('“$reason”').muted.small,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Editor sheet — visual builder + JSON (advanced) editing the same schema.
// ---------------------------------------------------------------------------

/// Which editing surface the template sheet is showing.
enum _TemplateEditMode { visual, json }

/// Mutable in-memory model for one field (record) row in the visual builder.
///
/// Mirrors a record map in the schema: keys `label`, `key`, `type`,
/// `required`, plus pass-through `format`/`reason`/`value` so round-tripping
/// through the visual builder never drops metadata authored in JSON mode.
class _FieldModel {
  final TextEditingController labelCtrl;
  final TextEditingController keyCtrl;
  String type;
  bool required;

  // Preserved verbatim from JSON; the visual builder doesn't edit these but
  // must not silently discard them on save.
  String format;
  String reason;
  String value;

  _FieldModel({
    String label = '',
    String key = '',
    this.type = 'text',
    this.required = false,
    this.format = 'default',
    this.reason = '',
    this.value = '',
  }) : labelCtrl = TextEditingController(text: label),
       keyCtrl = TextEditingController(text: key);

  factory _FieldModel.fromMap(Map<dynamic, dynamic> m) {
    final rawType = (m['type'] as String? ?? 'text').trim();
    return _FieldModel(
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
class _SectionModel {
  final TextEditingController nameCtrl;
  final TextEditingController keyCtrl;
  final List<_FieldModel> fields;

  _SectionModel({String name = '', String key = '', List<_FieldModel>? fields})
    : nameCtrl = TextEditingController(text: name),
      keyCtrl = TextEditingController(text: key),
      fields = fields ?? [];

  factory _SectionModel.fromMap(Map<dynamic, dynamic> m) {
    final rawRecords = m['records'] as List<dynamic>? ?? const [];
    return _SectionModel(
      name: (m['name'] as String? ?? '').trim(),
      key: (m['key'] as String? ?? '').trim(),
      fields: rawRecords
          .whereType<Map>()
          .map((r) => _FieldModel.fromMap(r))
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

class _TemplateEditorSheet extends StatefulWidget {
  final TemplatesStore templatesStore;
  final AuthStore authStore;
  final Template? initialTemplate;

  const _TemplateEditorSheet({
    required this.templatesStore,
    required this.authStore,
    this.initialTemplate,
  });

  @override
  State<_TemplateEditorSheet> createState() => _TemplateEditorSheetState();
}

class _TemplateEditorSheetState extends State<_TemplateEditorSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _jsonCtrl;

  _TemplateEditMode _mode = _TemplateEditMode.visual;

  // Visual-mode model.
  final List<_FieldModel> _rootFields = [];
  final List<_SectionModel> _sections = [];

  // Any top-level schema keys that are neither `records` nor `sections` are
  // preserved verbatim so JSON-authored extras survive a visual-mode save.
  final Map<String, dynamic> _extraSchemaKeys = {};

  bool _submitting = false;
  String? _jsonError;

  bool get _isEdit => widget.initialTemplate != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialTemplate?.name ?? '');

    final schema = widget.initialTemplate?.schema ?? _defaultSchema();
    _loadSchemaIntoModel(schema);
    _jsonCtrl = TextEditingController(text: _encodeSchema(schema));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _jsonCtrl.dispose();
    for (final f in _rootFields) {
      f.dispose();
    }
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  // --- Schema <-> model ------------------------------------------------

  Map<String, dynamic> _defaultSchema() => {
    'records': [
      {
        'label': 'API Endpoint',
        'key': 'api_url',
        'type': 'url',
        'format': 'default',
        'required': false,
        'reason': '',
      },
    ],
    'sections': <dynamic>[],
  };

  String _encodeSchema(Map<String, dynamic> schema) =>
      const JsonEncoder.withIndent('  ').convert(schema);

  /// Replaces the visual model with the contents of [schema]. Disposes the
  /// previous controllers first.
  void _loadSchemaIntoModel(Map<String, dynamic> schema) {
    for (final f in _rootFields) {
      f.dispose();
    }
    for (final s in _sections) {
      s.dispose();
    }
    _rootFields.clear();
    _sections.clear();
    _extraSchemaKeys.clear();

    final records = schema['records'] as List<dynamic>? ?? const [];
    for (final r in records.whereType<Map>()) {
      _rootFields.add(_FieldModel.fromMap(r));
    }

    final sections = schema['sections'] as List<dynamic>? ?? const [];
    for (final s in sections.whereType<Map>()) {
      _sections.add(_SectionModel.fromMap(s));
    }

    for (final entry in schema.entries) {
      if (entry.key != 'records' && entry.key != 'sections') {
        _extraSchemaKeys[entry.key] = entry.value;
      }
    }
  }

  /// Builds the schema map from the current visual model. Sections with no
  /// records and no name are dropped; `sections` is always emitted (possibly
  /// empty) for shape stability, matching the existing default schema.
  Map<String, dynamic> _buildSchemaFromModel() {
    final sections = _sections
        .where((s) => s.nameCtrl.text.trim().isNotEmpty || s.fields.isNotEmpty)
        .map((s) => s.toMap())
        .toList();

    return {
      ..._extraSchemaKeys,
      'records': _rootFields.map((f) => f.toMap()).toList(),
      'sections': sections,
    };
  }

  // --- Mode switching --------------------------------------------------

  void _switchMode(_TemplateEditMode next) {
    if (next == _mode) return;

    if (next == _TemplateEditMode.json) {
      // Visual -> JSON: serialise the live model so JSON reflects edits.
      _jsonCtrl.text = _encodeSchema(_buildSchemaFromModel());
      setState(() {
        _jsonError = null;
        _mode = next;
      });
    } else {
      // JSON -> Visual: parse, guard invalid JSON with a clear error.
      final parsed = _tryParseJson();
      if (parsed == null) return; // _jsonError already set + toast shown.
      _loadSchemaIntoModel(parsed);
      setState(() {
        _jsonError = null;
        _mode = next;
      });
    }
  }

  /// Parses the JSON text field. On failure sets [_jsonError], shows a toast,
  /// and returns null.
  Map<String, dynamic>? _tryParseJson() {
    final text = _jsonCtrl.text.trim();
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        setState(() => _jsonError = 'Schema must be a JSON object ({ ... }).');
        AppToast.error(
          context,
          'Invalid schema',
          subtitle: 'Expected an object',
        );
        return null;
      }
      return decoded;
    } catch (e) {
      setState(() => _jsonError = e.toString());
      AppToast.error(context, 'Invalid JSON structure', subtitle: e.toString());
      return null;
    }
  }

  // --- Save ------------------------------------------------------------

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      AppToast.error(context, 'Name cannot be empty');
      return;
    }

    final Map<String, dynamic> schema;
    if (_mode == _TemplateEditMode.json) {
      final parsed = _tryParseJson();
      if (parsed == null) return;
      schema = parsed;
    } else {
      schema = _buildSchemaFromModel();
    }

    setState(() => _submitting = true);
    bool ok;
    if (_isEdit) {
      ok = await widget.templatesStore.updateTemplate(
        widget.initialTemplate!.id,
        name: name,
        schema: schema,
      );
    } else {
      ok = await widget.templatesStore.createTemplate(
        name: name,
        schema: schema,
        workspaceId: widget.authStore.activeWorkspace ?? '',
      );
    }
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop();
      AppToast.success(
        context,
        _isEdit ? 'Template updated' : 'Template created',
      );
    } else {
      setState(() => _submitting = false);
      AppToast.error(
        context,
        _isEdit ? 'Could not update template' : 'Could not create template',
        subtitle: widget.templatesStore.errorMessage,
      );
    }
  }

  /// The exact API request this editor would issue — drives the live developer
  /// preview (create vs update), mirroring [_save].
  ApiRequestSpec _buildSpec() {
    final name = _nameCtrl.text.trim();
    final schema = _previewSchema();
    if (_isEdit) {
      return Stores.templates.updateTemplateSpec(
        widget.initialTemplate!.id,
        name: name,
        schema: schema,
      );
    }
    return Stores.templates.createTemplateSpec(
      name: name,
      schema: schema,
      workspaceId: widget.authStore.activeWorkspace ?? '',
    );
  }

  /// Best-effort schema for the preview — no side effects (unlike [_save]).
  Map<String, dynamic> _previewSchema() {
    if (_mode == _TemplateEditMode.json) {
      try {
        final parsed = jsonDecode(_jsonCtrl.text);
        if (parsed is Map<String, dynamic>) return parsed;
      } catch (_) {}
      return const {};
    }
    return _buildSchemaFromModel();
  }

  // --- Build -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xxs,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isEdit ? 'Edit template' : 'New template').header,
                const SizedBox(height: AppSpacing.xxs),
                const Text(
                  'Define the fields a responder must fill. Build it visually '
                  'or edit the raw JSON.',
                ).muted.small,
              ],
            ),
          ),
          const AppDivider(),

          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              children: [
                const Text('Template name').small,
                const SizedBox(height: AppSpacing.xs),
                AppTextField(
                  controller: _nameCtrl,
                  hint: 'e.g. AWS Project Setup',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.lg),

                _buildModeToggle(),
                const SizedBox(height: AppSpacing.lg),

                if (_mode == _TemplateEditMode.visual)
                  _buildVisualEditor()
                else
                  _buildJsonEditor(),

                const SizedBox(height: AppSpacing.xl),
                const Text('Developer').small,
                const SizedBox(height: AppSpacing.sm),
                ApiPreview(
                  spec: _buildSpec(),
                  title: 'API request · ${_isEdit ? 'update' : 'create'}',
                ),
              ],
            ),
          ),
          const AppDivider(),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Cancel',
                    onTap: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: AppButtonStyle.accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    label: _isEdit ? 'Save changes' : 'Create template',
                    busy: _submitting,
                    onTap: _save,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return AppSegmented<_TemplateEditMode>(
      value: _mode,
      items: const [
        AppSegmentedItem(
          value: _TemplateEditMode.visual,
          icon: AppIcons.cardList,
          label: 'Visual',
        ),
        AppSegmentedItem(
          value: _TemplateEditMode.json,
          icon: AppIcons.fileText,
          label: 'JSON (advanced)',
        ),
      ],
      onChanged: _switchMode,
    );
  }

  // --- Visual editor ---------------------------------------------------

  Widget _buildVisualEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: const Text('Fields').small),
            Text('${_rootFields.length}').muted.small,
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        const Text(
          'Each field is a value the responder must provide.',
        ).muted.small,
        const SizedBox(height: AppSpacing.sm),

        if (_rootFields.isEmpty)
          _buildEmptyHint('No fields yet. Add one below.')
        else
          ...List.generate(
            _rootFields.length,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _FieldEditorCard(
                field: _rootFields[i],
                onRemove: () => setState(() {
                  _rootFields.removeAt(i).dispose();
                }),
                onChanged: () => setState(() {}),
              ),
            ),
          ),

        const SizedBox(height: AppSpacing.xxs),
        AppButton(
          icon: AppIcons.plus,
          label: 'Add field',
          style: AppButtonStyle.accent,
          onTap: () => setState(() => _rootFields.add(_FieldModel())),
        ),

        const SizedBox(height: AppSpacing.xxl),
        const AppDivider(),
        const SizedBox(height: AppSpacing.lg),

        Row(
          children: [
            Expanded(child: const Text('Sections').small),
            Text('${_sections.length}').muted.small,
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        const Text(
          'A named group of fields (e.g. "Database credentials").',
        ).muted.small,
        const SizedBox(height: AppSpacing.sm),

        ...List.generate(
          _sections.length,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _SectionEditorCard(
              section: _sections[i],
              onRemove: () => setState(() {
                _sections.removeAt(i).dispose();
              }),
              onChanged: () => setState(() {}),
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.xxs),
        AppButton(
          icon: AppIcons.folderPlus,
          label: 'Add section',
          style: AppButtonStyle.accent,
          onTap: () => setState(() => _sections.add(_SectionModel())),
        ),
      ],
    );
  }

  Widget _buildEmptyHint(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: AppRadius.allMd,
      ),
      child: Center(child: Text(text).muted.small),
    );
  }

  // --- JSON editor -----------------------------------------------------

  Widget _buildJsonEditor() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('Template schema').small,
            const Spacer(),
            const AppBadge(
              label: 'Monospace JSON',
              variant: AppBadgeVariant.outline,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text('Switching back to Visual parses this JSON.').muted.small,
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          controller: _jsonCtrl,
          maxLines: 16,
          minLines: 10,
          mono: true,
          hint: '{\n  "records": [...],\n  "sections": [...]\n}',
          onChanged: (_) {
            if (_jsonError != null) setState(() => _jsonError = null);
          },
        ),
        if (_jsonError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.exclamationTriangle, size: 14, color: scheme.error),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: AppErrorText(_jsonError!)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Editable card for a single field (record): label, key, type, required.
class _FieldEditorCard extends StatelessWidget {
  final _FieldModel field;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _FieldEditorCard({
    required this.field,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: field.labelCtrl,
                  hint: 'Label (e.g. DB Host)',
                  onChanged: (_) => onChanged(),
                ),
              ),
              AppButton(
                icon: AppIcons.trash,
                tooltip: 'Remove field',
                style: AppButtonStyle.destructive,
                size: AppButtonSize.small,
                onTap: onRemove,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: field.keyCtrl,
            hint: 'Key (e.g. db_host)',
            mono: true,
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: AppSelect<String>(
                  value: field.type,
                  items: RecordTypeUtils.supportedTypes
                      .map((t) => AppSelectItem<String>(t, Text(t)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      field.type = v;
                      onChanged();
                    }
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text('Required').small,
                    AppSwitch(
                      value: field.required,
                      onChanged: (v) {
                        field.required = v;
                        onChanged();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Editable card for a section: name, key, and its own list of fields.
class _SectionEditorCard extends StatelessWidget {
  final _SectionModel section;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _SectionEditorCard({
    required this.section,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(AppIcons.folder, size: 16, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppTextField(
                  controller: section.nameCtrl,
                  hint: 'Section name',
                  onChanged: (_) => onChanged(),
                ),
              ),
              AppButton(
                icon: AppIcons.trash,
                tooltip: 'Remove section',
                style: AppButtonStyle.destructive,
                size: AppButtonSize.small,
                onTap: onRemove,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: section.keyCtrl,
            hint: 'Section key (e.g. db)',
            mono: true,
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: AppSpacing.md),
          if (section.fields.isEmpty)
            Padding(
              padding: const EdgeInsets.only(
                bottom: AppSpacing.sm,
                left: AppSpacing.xxs,
              ),
              child: const Text('No fields in this section.').muted.small,
            )
          else
            ...List.generate(
              section.fields.length,
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _FieldEditorCard(
                  field: section.fields[i],
                  onRemove: () {
                    section.fields.removeAt(i).dispose();
                    onChanged();
                  },
                  onChanged: onChanged,
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              icon: AppIcons.plus,
              label: 'Add field to section',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: () {
                section.fields.add(_FieldModel());
                onChanged();
              },
            ),
          ),
        ],
      ),
    );
  }
}
