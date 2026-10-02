import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_edit_sheet.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/features/vault/view/record_value_input.dart';
import 'package:revoked_app/features/vault/view/vault_file_row.dart';

/// One field a template asks for, flattened out of its schema. [group] is the
/// template's own heading for it and [sectionKey] that section's key; both
/// are empty for a field the template lists on its own. An answer is filed
/// where the template put the field — see [templateFieldSection].
class TemplateField {
  final String key;
  final String label;
  final String type;
  final String format;
  final String value;
  final String reason;
  final String group;
  final String sectionKey;

  const TemplateField({
    required this.key,
    required this.label,
    required this.type,
    required this.format,
    required this.value,
    required this.reason,
    required this.group,
    this.sectionKey = '',
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

TemplateField _field(
  Map<dynamic, dynamic> m,
  String group, [
  String sectionKey = '',
]) {
  final rawType = (m['type'] as String? ?? 'text').trim();
  return TemplateField(
    key: _sanitiseKey((m['key'] as String? ?? '').trim()),
    label: (m['label'] as String? ?? '').trim(),
    type: RecordTypeUtils.supportedTypes.contains(rawType) ? rawType : 'text',
    format: (m['format'] as String? ?? 'default').trim(),
    value: (m['value'] as String? ?? '').trim(),
    reason: (m['reason'] as String? ?? '').trim(),
    group: group,
    sectionKey: sectionKey,
  );
}

/// The vault section key for a name, sanitised the way a template's is.
String sectionKeyFor(String name) => _sanitiseKey(name);

/// The vault section a template's own fields fill into, named after it.
String templateSectionKey(Template template) => sectionKeyFor(template.name);

/// Where an answer to [field] is filed: the section the template put the
/// field in, or the template's own for a field it lists by itself. Sections
/// are found by key, so two templates that both have a "Personal information"
/// section fill the same one — a name is personal data whichever template
/// asked for it.
({String key, String name}) templateFieldSection(
  Template template,
  TemplateField field,
) => field.sectionKey.isEmpty
    ? (key: templateSectionKey(template), name: template.name)
    : (key: field.sectionKey, name: field.group);

List<TemplateField> templateFieldsOf(Template template) {
  final out = <TemplateField>[];
  for (final r in template.schema['records'] as List<dynamic>? ?? const []) {
    if (r is Map) out.add(_field(r, ''));
  }
  for (final s in template.schema['sections'] as List<dynamic>? ?? const []) {
    if (s is! Map) continue;
    final key = _sanitiseKey((s['key'] as String? ?? '').trim());
    final name = (s['name'] as String? ?? '').trim();
    for (final r in s['records'] as List<dynamic>? ?? const []) {
      if (r is Map) out.add(_field(r, name.isEmpty ? key : name, key));
    }
  }
  return out;
}

/// The record already answering this field, if the vault holds its key as
/// the owner's own — an answer someone sent to one of your requests is theirs.
models.Record? templateFieldAnswer(TemplateField field) {
  for (final r in Stores.vault.records) {
    if (r.key == field.key && r.requestedBy == null) return r;
  }
  return null;
}

/// Answers one field the way its type asks to be answered — typed, picked
/// from a calendar, or attached — and saves it as a record filed in the
/// section [sectionKey] (created, as [sectionName], on the first answer).
/// Toasts land on [toastContext], which outlives the sheets opened here.
/// True when a value was saved.
Future<bool> fillTemplateFieldInteractively({
  required BuildContext context,
  required BuildContext toastContext,
  required String sectionKey,
  required String sectionName,
  required TemplateField field,
}) async {
  final section = (key: sectionKey, name: sectionName);
  if (field.isFile) {
    return _fillFile(context, toastContext, section, field);
  }
  if (field.type == 'datetime') {
    return _fillDateTime(context, toastContext, section, field);
  }
  if (field.type == 'boolean') {
    return _fillBoolean(context, toastContext, section, field);
  }

  final store = Stores.vault;
  final answer = templateFieldAnswer(field);
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
  if (!saved) return false;

  final value = store.fillValue.text.trim();
  store.fillValue.clear();
  if (value.isEmpty) return false;

  if (!toastContext.mounted) return false;
  return _save(toastContext, section, field, value);
}

/// A file field is answered by attaching one: the same picker, size check
/// and streamed upload the record drawer uses, in a drawer of its own.
typedef _Section = ({String key, String name});

Future<bool> _fillFile(
  BuildContext context,
  BuildContext toastContext,
  _Section section,
  TemplateField field,
) async {
  final store = Stores.vault;
  store.clearPickedFile();

  final saved =
      await showAppSheet<bool>(
        context: context,
        builder: (sheetContext) => _FileFieldDrawer(
          section: section,
          field: field,
          attached: templateFieldAnswer(field)?.filename,
        ),
      ) ??
      false;
  store.clearPickedFile();

  if (!toastContext.mounted) return saved;
  if (saved) {
    AppToast.success(toastContext, 'Saved ${field.title}');
  } else if (store.errorMessage != null) {
    AppToast.error(
      toastContext,
      'Could not save ${field.title}',
      subtitle: store.errorMessage,
    );
  }
  return saved;
}

/// Yes or no is chosen, not typed: the stored value has to be `true` or
/// `false`, and one tap answers it. The answer the vault already holds is the
/// highlighted one.
Future<bool> _fillBoolean(
  BuildContext context,
  BuildContext toastContext,
  _Section section,
  TemplateField field,
) async {
  final stored = (templateFieldAnswer(field)?.value ?? field.value)
      .toLowerCase();
  final current = stored == 'true'
      ? true
      : stored == 'false'
      ? false
      : null;

  final answer = await showAppSheet<bool>(
    context: context,
    builder: (sheetCtx) {
      Widget choice(String label, IconData icon, bool value) => Expanded(
        child: AppButton(
          icon: icon,
          label: label,
          style: current == value
              ? AppButtonStyle.primary
              : AppButtonStyle.accent,
          onTap: () => Navigator.of(sheetCtx).pop(value),
        ),
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xxs,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(field.title).header,
            AppSpacing.gapXxs,
            Text(
              field.reason.isEmpty
                  ? 'Saved to your vault as ${field.key}.'
                  : field.reason,
            ).muted.small,
            AppSpacing.gapLg,
            Row(
              children: [
                choice('No', AppIcons.x, false),
                const SizedBox(width: AppSpacing.md),
                choice('Yes', AppIcons.check, true),
              ],
            ),
          ],
        ),
      );
    },
  );
  if (answer == null || !toastContext.mounted) return false;
  return _save(toastContext, section, field, answer ? 'true' : 'false');
}

/// A date is picked, not typed: the stored value has to parse as ISO 8601,
/// which is not what anyone writes by hand.
Future<bool> _fillDateTime(
  BuildContext context,
  BuildContext toastContext,
  _Section section,
  TemplateField field,
) async {
  final value = await pickRecordDateTime(
    context,
    title: field.title,
    current: templateFieldAnswer(field)?.value ?? field.value,
  );
  if (value == null || !toastContext.mounted) return false;
  return _save(toastContext, section, field, value);
}

Future<bool> _save(
  BuildContext toastContext,
  _Section section,
  TemplateField field,
  String value,
) async {
  final store = Stores.vault;
  store.setFillingField(true);
  final ok = await store.fillTemplateField(
    key: field.key,
    label: field.title,
    value: value,
    type: field.type,
    format: field.format,
    sectionKey: section.key,
    sectionName: section.name,
    user: Stores.auth.userId,
    workspace: Stores.auth.activeWorkspace ?? '',
  );
  store.setFillingField(false);

  if (!toastContext.mounted) return ok;
  if (ok) {
    AppToast.success(toastContext, 'Saved ${field.title}');
  } else {
    AppToast.error(
      toastContext,
      'Could not save ${field.title}',
      subtitle: store.errorMessage,
    );
  }
  return ok;
}

/// Answers one file field: pick or drop a file, then save it as the record
/// that field describes. The upload runs with the drawer still open, so its
/// progress — and its cancel — stay in reach.
class _FileFieldDrawer extends StatelessWidget {
  final _Section section;
  final TemplateField field;

  /// The file already answering this field, so replacing it is a decision
  /// rather than a surprise.
  final String? attached;

  const _FileFieldDrawer({
    required this.section,
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
      sectionKey: section.key,
      sectionName: section.name,
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
