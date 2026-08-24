import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_tabs.dart';
import 'package:revoked_app/features/vault/view/record_create_sheet.dart';
import 'package:revoked_app/features/vault/view/section_create_sheet.dart';
import 'package:revoked_app/features/vault/view/template_fill_form.dart';

/// The vault's one create drawer. The tabs pick what is being added, so the
/// floating button opens the form itself rather than a menu asking which form
/// to open — the same two forms the duplicate actions open on their own.
void openVaultCreateSheet(BuildContext context) {
  showAppSheet(
    context: context,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
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
              labels: const ['Record', 'Section', 'From template'],
              views: [
                recordCreateForm(parentContext: context),
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
