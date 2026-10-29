import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_tabs.dart';
import 'package:revoked_app/features/vault/view/record_create_sheet.dart';
import 'package:revoked_app/features/vault/view/section_create_sheet.dart';
import 'package:revoked_app/features/vault/view/template_fill_form.dart';

/// The tabs of [openVaultCreateSheet], in the order they are shown.
enum VaultCreateTab { record, section, template }

/// The vault's one create drawer. The tabs pick what is being added, so the
/// floating button opens the form itself rather than a menu asking which form
/// to open — the same two forms the duplicate actions open on their own.
/// [initialTab] lets a caller that already knows (the empty vault's "From
/// template") open on the right form. [recordType] preselects the record
/// form's type, such as `file` for the New picker's "File".
void openVaultCreateSheet(
  BuildContext context, {
  VaultCreateTab initialTab = VaultCreateTab.record,
  String? recordType,
}) {
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
                const Text('Add to vault').header,
                const SizedBox(height: AppSpacing.xxs),
                const Text(
                  'Store a piece of information, group records under a '
                  'section, or answer what a template asks for.',
                ).muted.small,
              ],
            ),
          ),
          Expanded(
            child: AppTabs(
              inset: AppSpacing.xl,
              labels: const ['Record', 'Section', 'From template'],
              initialIndex: initialTab.index,
              views: [
                recordCreateForm(
                  parentContext: context,
                  initialType: recordType,
                ),
                sectionCreateForm(parentContext: context),
                templateFillForm(parentContext: context),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
