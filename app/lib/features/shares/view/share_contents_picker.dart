import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';

/// What a new link's draft shares, in words: "IBAN", "IBAN and 2 more",
/// "Onboarding pack". Empty when nothing is picked yet.
String shareContentsSummary() {
  final names = <String>[
    for (final s in Stores.vault.sections)
      if (Stores.shares.draftSections.contains(s.id)) s.name,
    for (final r in Stores.vault.records)
      if (Stores.shares.draftRecords.contains(r.id)) recordTitle(r),
  ];
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  return '${names.first} and ${names.length - 1} more';
}

/// A record's name as a person reads it: its label, else its key.
String recordTitle(models.Record r) => r.label.isEmpty ? r.key : r.label;

/// Lets the owner tick the sections and records a new link shares. A section
/// is shared as a unit: records added to it later show up on the link too.
Future<void> openShareContentsPicker(BuildContext context) {
  return showAppSheet(
    context: context,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
      ),
      child: Observer(
        builder: (_) {
          final vault = Stores.vault;
          final draft = Stores.shares;
          final picked = draft.draftRecords.length + draft.draftSections.length;
          return Column(
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
                    const Text('What is shared').header,
                    AppSpacing.gapXxs,
                    const Text(
                      'The link shows the current value of each item. A '
                      'section is shared as a whole, including records added '
                      'to it later.',
                    ).muted.small,
                  ],
                ),
              ),
              const AppDivider(),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  children: [
                    if (vault.records.isEmpty && vault.sections.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                        ),
                        child: const Text(
                          'The vault has no records yet, so there is nothing '
                          'to share.',
                        ).muted,
                      ),
                    if (vault.sections.isNotEmpty) ...[
                      const _GroupLabel('Sections'),
                      for (final s in vault.sections)
                        AppCheckRow(
                          label: s.name,
                          subtitle:
                              '${s.records.length} '
                              '${s.records.length == 1 ? 'record' : 'records'}',
                          value: draft.draftSections.contains(s.id),
                          onChanged: (_) => draft.toggleDraftSection(s.id),
                        ),
                    ],
                    if (vault.records.isNotEmpty) ...[
                      const _GroupLabel('Records'),
                      for (final r in vault.records)
                        AppCheckRow(
                          label: recordTitle(r),
                          subtitle: r.isFile
                              ? 'File'
                              : (r.isHidden ? 'Hidden value' : null),
                          value: draft.draftRecords.contains(r.id),
                          onChanged: (_) => draft.toggleDraftRecord(r.id),
                        ),
                    ],
                    AppSpacing.gapMd,
                  ],
                ),
              ),
              const AppDivider(),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: AppButton(
                  icon: AppIcons.check,
                  label: picked == 0
                      ? 'Done'
                      : 'Share $picked ${picked == 1 ? 'item' : 'items'}',
                  onTap: () => Navigator.of(sheetContext).pop(),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.lg,
        bottom: AppSpacing.xxs,
      ),
      child: Text(text.toUpperCase()).muted.small,
    );
  }
}

/// The form row that opens [openShareContentsPicker].
class ShareContentsRow extends StatelessWidget {
  const ShareContentsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final summary = shareContentsSummary();
        return AppFormRow(
          icon: AppIcons.safe,
          label: 'What is shared',
          valueText: summary.isEmpty
              ? 'Required — pick from the vault'
              : summary,
          isPlaceholder: summary.isEmpty,
          isError: summary.isEmpty,
          onTap: () => openShareContentsPicker(context),
        );
      },
    );
  }
}
