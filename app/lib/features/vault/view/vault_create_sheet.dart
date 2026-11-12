import 'package:material_ui/material_ui.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_tabs.dart';
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
  final duplicating = duplicateSection != null;
  showAppSheet(
    context: context,
    builder: (sheetContext) => ConstrainedBox(
      // A bottom sheet leaves a strip of the page in view; a side panel is
      // already beside the page, so it runs the full height and its buttons
      // sit at the bottom edge.
      constraints: BoxConstraints(
        maxHeight: AppSpacing.isNarrow(sheetContext)
            ? MediaQuery.of(sheetContext).size.height * 0.9
            : double.infinity,
      ),
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
                Text(duplicating ? 'Duplicate section' : 'Add to vault').header,
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  duplicating
                      ? 'A copy of "${duplicateSection.name}" with the same '
                            'records, under a new key.'
                      : 'A single record, a section of records, or the fields '
                            'of a template.',
                ).muted.small,
              ],
            ),
          ),
          Expanded(
            child: AppTabs(
              inset: AppSpacing.xl,
              initialIndex: duplicating
                  ? VaultCreateTab.section.index
                  : initialTab.index,
              tabs: [
                AppTab(
                  label: 'Record',
                  icon: AppIcons.key,
                  description: 'A single value, such as an IBAN, or a file.',
                  view: recordCreateForm(
                    parentContext: context,
                    initialType: recordType,
                  ),
                ),
                AppTab(
                  label: 'Section',
                  icon: AppIcons.folder,
                  description: 'Records grouped to be shared together.',
                  view: sectionCreateForm(
                    parentContext: context,
                    duplicateOf: duplicateSection,
                  ),
                ),
                AppTab(
                  label: 'Template',
                  icon: AppIcons.cardList,
                  description: 'Several records in one step, from a template.',
                  view: templateFillForm(parentContext: context),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
