import 'package:revoked_app/core/widgets/app_composer.dart';
import 'package:revoked_app/features/vault/views/view_data.dart';
import 'package:revoked_app/features/vault/views/view_editor.dart';
import 'package:revoked_app/features/vault/views/view_renderer.dart';
import 'package:revoked_app/features/vault/views/view_spec.dart';
import 'package:material_ui/material_ui.dart';
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
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_tile.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
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
  /// The template's values come first: answering them is what this form is
  /// for; the switch shows how the section will look.
  bool _showView = false;

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
      // The template's view belongs to its own section, not to the others
      // its fields are filed in.
      view: field.sectionKey.isEmpty ? templateView(template) : null,
    );
  }

  bool _adding = false;

  bool _hasSection(Template template) {
    final key = templateSectionKey(template);
    return Stores.vault.sections.any((s) => s.key == key);
  }

  /// Closes the drawer on a picked template, making its section first when
  /// the vault has none yet, and says what is now in the vault.
  Future<void> _finish(Template template) async {
    if (_hasSection(template)) {
      AppToast.success(
        widget.parentContext,
        '${template.name} is in your vault',
        subtitle: _progress(templateFieldsOf(template)),
      );
      Navigator.of(context).pop();
      return;
    }
    setState(() => _adding = true);
    final ok = await Stores.vault.createSection(
      key: templateSectionKey(template),
      name: template.name,
      recordIds: const [],
      user: Stores.auth.userId,
      workspace: Stores.auth.activeWorkspace ?? '',
      view: templateView(template),
    );
    if (!mounted) return;
    setState(() => _adding = false);
    if (!ok) {
      AppToast.error(
        context,
        'The section could not be created',
        subtitle: Stores.vault.errorMessage,
      );
      return;
    }
    // Drawn on the root overlay, so it outlasts the drawer it is raised from.
    AppToast.success(
      context,
      'Section created',
      subtitle: '${template.name} · its fields can be filled in later',
    );
    Navigator.of(context).pop();
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
              final template = _selected();
              // A picked template is added to the vault even before any
              // answer: its section is made empty and filled in later.
              final adds = template != null && !_hasSection(template);
              final done = AppButton(
                icon: adds ? AppIcons.plus : AppIcons.check,
                label: adds ? 'Create section' : 'Done',
                busy: _adding,
                onTap: template == null
                    ? () => Navigator.of(context).pop()
                    : () => _finish(template),
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

  Widget _body() => AppComposerLayout(
    rail: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppText('Template').bold,
        AppSpacing.gapMd,
        for (final template in Stores.templates.templates) ...[
          AppComposerChoice(
            label: template.name,
            icon: AppIcons.cardList,
            selected: template.id == Stores.vault.fillTemplateId,
            onTap: Stores.vault.isFillingField
                ? null
                : () => Stores.vault.selectFillTemplate(template.id),
          ),
          AppSpacing.gapXxs,
        ],
      ],
    ),
    child: _editor(),
  );

  Widget _editor() {
    final template = _selected();
    if (template != null) return _fields(template);

    final templates = Stores.templates;
    if (templates.isLoading && templates.templates.isEmpty) {
      return const AppListSkeleton();
    }
    if (templates.templates.isEmpty) {
      return const AppEmptyState(
        icon: AppIcons.cardList,
        title: 'No templates',
        subtitle: 'Templates are managed in Settings, under Developer.',
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
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.md,
            AppSpacing.xxl,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppText('Choose a template').bold,
              AppSpacing.gapXxs,
              const Text(
                'Save each answer as a record. You can finish the rest later.',
              ).small.muted,
            ],
          ),
        ),
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
    final preview = _preview(template, fields);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(template.name).header),
              AppSpacing.gapSm,
              AppBadge(label: _progress(fields)),
            ],
          ),
          AppSpacing.gapSm,
          const Text('Each answer is saved to your vault as a record.')
              .small
              .muted,
          AppSpacing.gapXl,
          // How the section shows and the answers it is made of, one at a
          // time: the switch moves between them.
          if (preview != null) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppSegmented<bool>(
                key: const ValueKey('template-fill-view-switch'),
                value: _showView,
                items: [
                  AppSegmentedItem(
                    value: true,
                    label: preview.spec.name,
                    icon: AppIcons.dashboard,
                  ),
                  const AppSegmentedItem(
                    value: false,
                    label: 'Values',
                    icon: AppIcons.cardList,
                  ),
                ],
                onChanged: (view) => setState(() => _showView = view),
              ),
            ),
            AppSpacing.gapLg,
          ],
          if (preview != null && _showView)
            preview.widget
          else ...[
            if (fields.isEmpty)
              const Text('This template has no fields.').small.muted,
            for (final entry in groups.entries)
              AppListGroup(
                title: entry.key.isEmpty ? 'Records' : entry.key,
                trailing: const SizedBox.shrink(),
                children: [
                  for (final field in entry.value) _row(template, field),
                ],
              ),
          ],
        ],
      ),
    );
  }

  /// How the section this template fills will show: over the answers given
  /// so far, or sample values before the first one.
  ({ViewSpec spec, Widget widget})? _preview(
    Template template,
    List<TemplateField> fields,
  ) {
    final json = templateView(template);
    final spec = json == null ? null : ViewSpec.parse(json);
    if (spec == null) return null;
    final keys = {for (final f in fields) f.key};
    final answered = [
      for (final r in Stores.vault.records)
        if (keys.contains(r.key) && r.requestedBy == null) r,
    ];
    return (
      spec: spec,
      widget: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            answered.isEmpty
                ? 'Shows as · sample values'
                : 'Shows as · your answers so far',
          ).small.bold,
          AppSpacing.gapSm,
          ViewRenderer(
            spec: spec,
            data: answered.isEmpty
                ? sampleViewData(template.schema)
                : ViewData(section: answered),
          ),
        ],
      ),
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
        horizontal: AppSpacing.md,
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
