import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/state/local.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/features/vault/view/record_composer.dart';
import 'package:revoked_app/features/vault/view/record_create_sheet.dart';
import 'package:revoked_app/features/vault/view/section_create_sheet.dart';
import 'package:revoked_app/features/vault/view/template_fill_form.dart';

/// The tabs of [openVaultCreateSheet], in the order they are shown.
enum VaultCreateTab { record, section, template }

/// The vault's one create drawer. The tabs pick what is being added, so the
/// floating button opens the form itself rather than a menu asking which form
/// to open. Every way to a new section comes here — the New picker, the
/// vault's "+ Section" and a section's Duplicate — so its form lives once.
/// [initialTab] lets a caller that already knows (the empty vault's "From
/// template") open on the right form. [recordType] preselects the record
/// form's type, such as `file` for the New picker's "File".
/// [duplicateSection] opens on the Section tab with a copy of that section
/// filled in, so a new section and a duplicate share the one form.
void openVaultCreateSheet(
  BuildContext context, {
  VaultCreateTab initialTab = VaultCreateTab.record,
  String? recordType,
  Section? duplicateSection,
}) {
  showAppSheet(
    context: context,
    panelWidth: vaultComposerWidth,
    builder: (_) => _VaultCreateComposer(
      parentContext: context,
      initialTab: initialTab,
      recordType: recordType,
      duplicateSection: duplicateSection,
    ),
  );
}

class _VaultCreateComposer extends StatefulWidget {
  final BuildContext parentContext;
  final VaultCreateTab initialTab;
  final String? recordType;
  final Section? duplicateSection;

  const _VaultCreateComposer({
    required this.parentContext,
    required this.initialTab,
    this.recordType,
    this.duplicateSection,
  });

  @override
  State<_VaultCreateComposer> createState() => _VaultCreateComposerState();
}

class _VaultCreateComposerState extends State<_VaultCreateComposer> {
  late final Local<VaultCreateTab> _tab = Local(
    widget.duplicateSection == null
        ? widget.initialTab
        : VaultCreateTab.section,
  );

  @override
  Widget build(BuildContext context) =>
      Observer(builder: (_) => _build(context));

  Widget _build(BuildContext context) {
    final duplicate = widget.duplicateSection;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: AppSpacing.isNarrow(context)
            ? MediaQuery.sizeOf(context).height * 0.9
            : double.infinity,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Observer(
            builder: (_) => VaultComposerHeader(
              title: duplicate == null ? 'Add to vault' : 'Duplicate section',
              subtitle: duplicate == null
                  ? 'Your information, ready when you need it.'
                  : 'A copy of "${duplicate.name}" with the same records, '
                        'under a new key.',
              onClose:
                  Stores.vault.isSubmittingRecord ||
                      Stores.vault.isSubmittingSection
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              0,
              AppSpacing.xxl,
              AppSpacing.xl,
            ),
            child: Observer(
              builder: (_) => IgnorePointer(
                ignoring:
                    Stores.vault.isSubmittingRecord ||
                    Stores.vault.isSubmittingSection,
                child: AppSegmented<VaultCreateTab>(
                  value: _tab.value,
                  expand: true,
                  onChanged: (tab) {
                    if (Stores.vault.isSubmittingRecord ||
                        Stores.vault.isSubmittingSection) {
                      return;
                    }
                    _tab.value = tab;
                  },
                  items: const [
                    AppSegmentedItem(
                      value: VaultCreateTab.record,
                      label: 'Record',
                      icon: AppIcons.key,
                    ),
                    AppSegmentedItem(
                      value: VaultCreateTab.section,
                      label: 'Section',
                      icon: AppIcons.folder,
                    ),
                    AppSegmentedItem(
                      value: VaultCreateTab.template,
                      label: 'Template',
                      icon: AppIcons.cardList,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const AppDivider(),
          Expanded(
            child: IndexedStack(
              index: _tab.value.index,
              children: [
                recordCreateForm(
                  parentContext: widget.parentContext,
                  initialType: widget.recordType,
                ),
                sectionCreateForm(
                  parentContext: widget.parentContext,
                  duplicateOf: duplicate,
                ),
                templateFillForm(parentContext: widget.parentContext),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
