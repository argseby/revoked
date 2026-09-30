import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_collapsible_group.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_tile.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/features/vault/view/template_field_fill.dart';

/// The vault create drawer's third tab: answer a template's fields one at a
/// time. Each answer is a record the moment it is saved — a template is a
/// checklist of what to store, not a form that has to be completed.
Widget templateFillForm({required BuildContext parentContext}) =>
    _TemplateFillForm(parentContext: parentContext);

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

  Template? _selected() {
    final id = Stores.vault.fillTemplateId;
    if (id == null) return null;
    for (final t in Stores.templates.templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> _fill(Template template, TemplateField field) {
    final section = templateFieldSection(template, field);
    return fillTemplateFieldInteractively(
      context: context,
      toastContext: widget.parentContext,
      sectionKey: section.key,
      sectionName: section.name,
      field: field,
    );
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
      subtitle: Text(_progress(templateFieldsOf(t))).muted.small,
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

  String _progress(List<TemplateField> fields) {
    final filled = fields.where((f) => Stores.vault.isKeyFilled(f.key)).length;
    return '$filled of ${fields.length} filled';
  }

  Widget _fields(Template template) {
    final fields = templateFieldsOf(template);
    final groups = <String, List<TemplateField>>{};
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

  Widget _row(Template template, TemplateField field) {
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
