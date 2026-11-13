import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_composer.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/vault/view/record_composer.dart';
import 'package:revoked_app/features/vault/view/section_views.dart';
import 'package:revoked_app/features/vault/views/view_data.dart';
import 'package:revoked_app/features/vault/views/view_editor.dart';

/// Edits how [section] shows as a card: its view's code, previewed over the
/// section's own records as it is typed.
Future<void> openSectionViewSheet(BuildContext context, Section section) =>
    showAppSheet(
      context: context,
      panelWidth: vaultComposerWidth,
      builder: (_) => _SectionViewSheet(section: section),
    );

class _SectionViewSheet extends StatefulWidget {
  final Section section;
  const _SectionViewSheet({required this.section});

  @override
  State<_SectionViewSheet> createState() => _SectionViewSheetState();
}

class _SectionViewSheetState extends State<_SectionViewSheet> {
  // The view the section shows now: its own, or the one it borrows from a
  // template, so editing starts from what is on screen.
  late final Map<String, dynamic>? _initial =
      widget.section.view ?? _borrowed();
  late final _draft = Local<Map<String, dynamic>?>(_initial);
  final _saving = Local(false);

  Map<String, dynamic>? _borrowed() {
    final shown = SectionView.of(
      widget.section,
      Stores.vault.records,
      vault: Stores.vault.records,
      templates: Stores.templates.templates,
    );
    if (shown == null) return null;
    for (final json in viewExamples(Stores.templates.templates)) {
      if (json['id'] == shown.spec.id) return json;
    }
    return null;
  }

  Future<void> _save() async {
    _saving.value = true;
    final ok = await Stores.vault.updateSection(widget.section.id, {
      'view': _draft.value,
    });
    if (!mounted) return;
    _saving.value = false;
    if (ok) {
      Navigator.of(context).pop();
      AppToast.success(
        context,
        _draft.value == null ? 'View removed' : 'View saved',
      );
    } else {
      AppToast.error(
        context,
        'The view could not be saved',
        subtitle: Stores.vault.errorMessage,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Observer(builder: _build);

  Widget _build(BuildContext context) {
    final records = [
      for (final r in Stores.vault.records)
        if (widget.section.records.contains(r.id)) r,
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: composerMaxHeight(context)),
      child: Column(
        mainAxisSize: AppSpacing.isNarrow(context)
            ? MainAxisSize.min
            : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VaultComposerHeader(
            title: 'Section view',
            area: widget.section.name,
            areaIcon: AppIcons.folder,
            subtitle:
                'How this section shows as one card. Every value comes from '
                'its records, by key; nothing is loaded from elsewhere.',
            onClose: _saving.value ? null : () => Navigator.of(context).pop(),
          ),
          const AppDivider(),
          Flexible(
            fit: AppSpacing.isNarrow(context) ? FlexFit.loose : FlexFit.tight,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl,
                vertical: AppSpacing.lg,
              ),
              child: ViewCodeEditor(
                initial: _initial,
                data: ViewData(section: records, vault: Stores.vault.records),
                examples: viewExamples(Stores.templates.templates),
                onChanged: (view) => _draft.value = view,
              ),
            ),
          ),
          const AppDivider(),
          AppComposerFooter(
            label: 'Save view',
            icon: AppIcons.check,
            busy: _saving.value,
            onSubmit: _saving.value ? null : _save,
            onCancel: _saving.value ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
