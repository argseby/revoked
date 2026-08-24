import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_collapsible_group.dart';
import 'package:revoked_app/core/widgets/app_edit_sheet.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_tile.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/features/vault/view/vault_file_row.dart';

/// The vault create drawer's third tab: answer a template's fields one at a
/// time. Each answer is a record the moment it is saved — a template is a
/// checklist of what to store, not a form that has to be completed.
Widget templateFillForm({required BuildContext parentContext}) =>
    _TemplateFillForm(parentContext: parentContext);

/// One field a template asks for, flattened out of its schema. [group] is the
/// template's own heading for it — a reading aid only: every answer is filed
/// in the template's section, so a template's records stay together in the
/// vault instead of scattering across a section each.
class _Field {
  final String key;
  final String label;
  final String type;
  final String format;
  final String value;
  final String reason;
  final String group;

  const _Field({
    required this.key,
    required this.label,
    required this.type,
    required this.format,
    required this.value,
    required this.reason,
    required this.group,
  });

  String get title => label.isEmpty ? key : label;

  bool get isFile => type == 'file';
}

/// Keys are sanitised the same way instantiating a whole template sanitises
/// them, or "already filled" would never match what the import wrote.
String _sanitiseKey(String raw) {
  final key = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
  return key.isEmpty ? 'key' : key;
}

_Field _field(Map<dynamic, dynamic> m, String group) {
  final rawType = (m['type'] as String? ?? 'text').trim();
  return _Field(
    key: _sanitiseKey((m['key'] as String? ?? '').trim()),
    label: (m['label'] as String? ?? '').trim(),
    type: RecordTypeUtils.supportedTypes.contains(rawType) ? rawType : 'text',
    format: (m['format'] as String? ?? 'default').trim(),
    value: (m['value'] as String? ?? '').trim(),
    reason: (m['reason'] as String? ?? '').trim(),
    group: group,
  );
}

/// The vault section a template fills into: one per template, named after it.
String _sectionKeyOf(Template template) => _sanitiseKey(template.name);

List<_Field> _fieldsOf(Template template) {
  final out = <_Field>[];
  for (final r in template.schema['records'] as List<dynamic>? ?? const []) {
    if (r is Map) out.add(_field(r, ''));
  }
  for (final s in template.schema['sections'] as List<dynamic>? ?? const []) {
    if (s is! Map) continue;
    final key = _sanitiseKey((s['key'] as String? ?? '').trim());
    final name = (s['name'] as String? ?? '').trim();
    for (final r in s['records'] as List<dynamic>? ?? const []) {
      if (r is Map) out.add(_field(r, name.isEmpty ? key : name));
    }
  }
  return out;
}

class _TemplateFillForm extends StatefulWidget {
  final BuildContext parentContext;

  const _TemplateFillForm({required this.parentContext});

  @override
  State<_TemplateFillForm> createState() => _TemplateFillFormState();
}

class _TemplateFillFormState extends State<_TemplateFillForm> {
  @override
  void initState() {
    super.initState();
    // The drawer opens on the template list, whatever was open last time.
    Stores.vault.selectFillTemplate(null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Stores.templates.loadTemplates(Stores.auth.activeWorkspace ?? '');
    });
  }

  /// The record already answering this field, if the vault holds its key.
  models.Record? _answer(_Field field) {
    for (final r in Stores.vault.records) {
      if (r.key == field.key) return r;
    }
    return null;
  }

  Template? _selected() {
    final id = Stores.vault.fillTemplateId;
    if (id == null) return null;
    for (final t in Stores.templates.templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// A file field is answered by attaching one: the same picker, size check
  /// and streamed upload the record drawer uses, in a drawer of its own.
  Future<void> _fillFile(Template template, _Field field) async {
    final store = Stores.vault;
    store.clearPickedFile();

    final saved =
        await showAppSheet<bool>(
          context: context,
          builder: (sheetContext) => _FileFieldDrawer(
            template: template,
            field: field,
            attached: _answer(field)?.filename,
          ),
        ) ??
        false;
    store.clearPickedFile();

    if (!widget.parentContext.mounted) return;
    if (saved) {
      AppToast.success(widget.parentContext, 'Saved ${field.title}');
    } else if (store.errorMessage != null) {
      AppToast.error(
        widget.parentContext,
        'Could not save ${field.title}',
        subtitle: store.errorMessage,
      );
    }
  }

  /// A date is picked, not typed: the stored value has to parse as ISO 8601,
  /// which is not what anyone writes by hand. The time step is optional — a
  /// date of birth has no time, so dismissing it stores the day alone.
  Future<void> _fillDateTime(Template template, _Field field) async {
    final now = DateTime.now();
    final stored = _answer(field)?.value ?? field.value;
    final initial = DateTime.tryParse(stored) ?? now;

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 50),
      helpText: field.title,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: '${field.title} — time (optional)',
    );

    final day =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final value = time == null
        ? day
        : '${day}T${time.hour.toString().padLeft(2, '0')}:'
              '${time.minute.toString().padLeft(2, '0')}';

    await _save(template, field, value);
  }

  Future<void> _save(Template template, _Field field, String value) async {
    final store = Stores.vault;
    store.setFillingField(true);
    final ok = await store.fillTemplateField(
      key: field.key,
      label: field.title,
      value: value,
      type: field.type,
      format: field.format,
      sectionKey: _sectionKeyOf(template),
      sectionName: template.name,
      user: Stores.auth.userId,
      workspace: Stores.auth.activeWorkspace ?? '',
    );
    store.setFillingField(false);

    if (!widget.parentContext.mounted) return;
    if (ok) {
      AppToast.success(widget.parentContext, 'Saved ${field.title}');
    } else {
      AppToast.error(
        widget.parentContext,
        'Could not save ${field.title}',
        subtitle: store.errorMessage,
      );
    }
  }

  Future<void> _fill(Template template, _Field field) async {
    if (field.isFile) return _fillFile(template, field);
    if (field.type == 'datetime') return _fillDateTime(template, field);

    final store = Stores.vault;
    final answer = _answer(field);
    store.fillValue.text = answer?.value ?? field.value;

    final saved = await showAppEditSheet(
      context: context,
      title: field.title,
      description: field.reason.isEmpty
          ? 'Saved to your vault as ${field.key}.'
          : field.reason,
      controller: store.fillValue,
      hint: 'Value',
      keyboardType: field.type == 'number' ? TextInputType.number : null,
      maxLines: field.format == 'multiline' ? 4 : 1,
      doneLabel: 'Save',
    );
    if (!saved) return;

    final value = store.fillValue.text.trim();
    store.fillValue.clear();
    if (value.isEmpty) return;

    await _save(template, field, value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          fit: FlexFit.tight,
          child: Observer(builder: (_) => _body()),
        ),
        const AppDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.md,
          ),
          child: Observer(
            builder: (_) {
              final done = AppButton(
                icon: AppIcons.check,
                label: 'Done',
                onTap: () => Navigator.of(context).pop(),
              );
              if (Stores.vault.fillTemplateId == null) return done;
              return Row(
                children: [
                  Expanded(
                    child: AppButton(
                      icon: AppIcons.arrowLeft,
                      label: 'Back',
                      style: AppButtonStyle.accent,
                      onTap: () => Stores.vault.selectFillTemplate(null),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: done),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _body() {
    final template = _selected();
    if (template != null) return _fields(template);

    final templates = Stores.templates;
    if (templates.isLoading && templates.templates.isEmpty) {
      return const Center(child: AppSpinner(large: true));
    }
    if (templates.templates.isEmpty) {
      return const AppEmptyState(
        icon: AppIcons.cardList,
        title: 'No templates yet',
        subtitle: 'Templates are created in Settings, under Developer.',
      );
    }

    Widget tile(Template t, {required bool inGroup}) => AppTile(
      padding: EdgeInsets.symmetric(
        horizontal: inGroup ? AppSpacing.md : AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      leading: Icon(
        AppIcons.cardList,
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(t.name),
      subtitle: Text(_progress(_fieldsOf(t))).muted.small,
      trailing: const Icon(AppIcons.chevronRight, size: 16),
      onTap: () => Stores.vault.selectFillTemplate(t.id),
    );

    final builtins = templates.templates.where((t) => t.isBuiltin).toList();
    final own = templates.templates.where((t) => !t.isBuiltin).toList();

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      children: [
        const AppFormSectionHeader('Templates'),
        if (builtins.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xs,
              AppSpacing.xl,
              0,
            ),
            child: AppCollapsibleGroup(
              icon: AppIcons.folder,
              title: 'Built-in',
              children: [for (final t in builtins) tile(t, inGroup: true)],
            ),
          ),
        for (final t in own) tile(t, inGroup: false),
      ],
    );
  }

  String _progress(List<_Field> fields) {
    final filled = fields.where((f) => Stores.vault.isKeyFilled(f.key)).length;
    return '$filled of ${fields.length} filled';
  }

  Widget _fields(Template template) {
    final fields = _fieldsOf(template);
    final groups = <String, List<_Field>>{};
    for (final f in fields) {
      groups.putIfAbsent(f.group, () => []).add(f);
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  template.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ).header,
              ),
              AppSpacing.gapSm,
              AppBadge(label: _progress(fields)),
            ],
          ),
        ),
        if (fields.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: const Text(
              'This template asks for nothing yet.',
            ).muted.small,
          ),
        for (final entry in groups.entries) ...[
          if (entry.key.isNotEmpty) AppFormSectionHeader(entry.key),
          if (entry.key.isEmpty) const AppFormSectionHeader('Records'),
          for (final f in entry.value) _row(template, f),
        ],
      ],
    );
  }

  Widget _row(Template template, _Field field) {
    final scheme = Theme.of(context).colorScheme;
    final filled = Stores.vault.isKeyFilled(field.key);
    // A save in flight closes the rows: two taps on one field would write the
    // key twice.
    // An answered field stays open: tapping it again edits what is stored.
    final tappable = !Stores.vault.isFillingField;

    return AppTile(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      leading: Icon(
        RecordTypeUtils.icon(field.type),
        size: 18,
        color: filled ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(field.title),
      subtitle: Text(field.key).mono.muted.small,
      trailing: Icon(
        filled ? AppIcons.checkCircle : AppIcons.chevronRight,
        size: filled ? 18 : 16,
        color: filled ? scheme.primary : scheme.onSurfaceVariant,
      ),
      onTap: tappable ? () => _fill(template, field) : null,
    );
  }
}

/// Answers one file field: pick or drop a file, then save it as the record
/// that field describes. The upload runs with the drawer still open, so its
/// progress — and its cancel — stay in reach.
class _FileFieldDrawer extends StatelessWidget {
  final Template template;
  final _Field field;

  /// The file already answering this field, so replacing it is a decision
  /// rather than a surprise.
  final String? attached;

  const _FileFieldDrawer({
    required this.template,
    required this.field,
    this.attached,
  });

  Future<void> _save(BuildContext context) async {
    final store = Stores.vault;
    final file = store.pickedFile;
    if (file == null) return;

    store.setFillingField(true);
    final ok = await store.fillTemplateField(
      key: field.key,
      label: field.title,
      value: '',
      type: 'file',
      format: field.format,
      sectionKey: _sectionKeyOf(template),
      sectionName: template.name,
      user: Stores.auth.userId,
      workspace: Stores.auth.activeWorkspace ?? '',
      file: file,
    );
    store.setFillingField(false);
    if (context.mounted) Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.vault;
    return vaultDropTarget(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                Text(field.title).header,
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  attached != null
                      ? 'Attached: $attached. Pick another to replace it.'
                      : (field.reason.isEmpty
                            ? 'Saved to your vault as ${field.key}.'
                            : field.reason),
                ).muted.small,
              ],
            ),
          ),
          const AppDivider(),
          const SizedBox(height: AppSpacing.sm),
          const VaultFileRow(),
          const AppDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Observer(
              builder: (_) => Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Cancel',
                      style: AppButtonStyle.accent,
                      onTap: store.isFillingField
                          ? null
                          : () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppButton(
                      icon: AppIcons.check,
                      label: 'Save',
                      busy: store.isFillingField,
                      onTap: store.pickedFile == null
                          ? null
                          : () => _save(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
