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

/// What a draft shares, in words: "IBAN", "IBAN and 2 more", "Onboarding
/// pack". Empty when nothing is picked yet.
///
/// The sets default to the link draft's. A send to a contact passes its own,
/// so both read the vault the same way rather than growing a second picker.
String shareContentsSummary({Set<String>? records, Set<String>? sections}) {
  final pickedRecords = records ?? Stores.shares.draftRecords;
  final pickedSections = sections ?? Stores.shares.draftSections;
  final names = <String>[
    for (final s in Stores.vault.sections)
      if (pickedSections.contains(s.id)) s.name,
    for (final r in Stores.vault.records)
      if (pickedRecords.contains(r.id)) recordTitle(r),
  ];
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  return '${names.first} and ${names.length - 1} more';
}

/// A record's name as a person reads it: its label, else its key.
String recordTitle(models.Record r) => r.label.isEmpty ? r.key : r.label;

/// Lets the owner tick the sections and records a share gives out. A section
/// is shared as a unit: records added to it later show up on the link too.
///
/// [toggleRecord]/[toggleSection] and the sets they read come from whichever
/// draft is being filled in — a new link's, or a send to a contact.
Future<void> openShareContentsPicker(
  BuildContext context, {
  Set<String>? records,
  Set<String>? sections,
  void Function(String id)? toggleRecord,
  void Function(String id)? toggleSection,
}) {
  final shares = Stores.shares;
  final pickedRecords = records ?? shares.draftRecords;
  final pickedSections = sections ?? shares.draftSections;
  final onRecord = toggleRecord ?? shares.toggleDraftRecord;
  final onSection = toggleSection ?? shares.toggleDraftSection;
  return showAppSheet(
    context: context,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
      ),
      child: Observer(
        builder: (_) {
          final vault = Stores.vault;
          final picked = pickedRecords.length + pickedSections.length;
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
                    const Text('What to share').header,
                    AppSpacing.gapXxs,
                    const Text(
                      'They always see the latest version. Share a section, '
                      'and records you add to it later are shared too.',
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
                          'Your vault is empty. Add a record first, then '
                          'share it.',
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
                          value: pickedSections.contains(s.id),
                          onChanged: (_) => onSection(s.id),
                        ),
                    ],
                    if (vault.records.any((r) => !r.sealed)) ...[
                      const _GroupLabel('Records'),
                      for (final r in vault.records.where((r) => !r.sealed))
                        AppCheckRow(
                          label: recordTitle(r),
                          subtitle: r.isFile
                              ? 'File'
                              : (r.isHidden ? 'Hidden value' : null),
                          value: pickedRecords.contains(r.id),
                          onChanged: (_) => onRecord(r.id),
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
      child: Text(text).small.bold.muted,
    );
  }
}

/// The form row that opens [openShareContentsPicker], for the link draft or
/// for any other draft that gives vault entries out.
class ShareContentsRow extends StatelessWidget {
  final Set<String>? records;
  final Set<String>? sections;
  final void Function(String id)? toggleRecord;
  final void Function(String id)? toggleSection;

  /// Off inside a sheet that already pads its fields.
  final bool inset;

  const ShareContentsRow({
    super.key,
    this.records,
    this.sections,
    this.toggleRecord,
    this.toggleSection,
    this.inset = true,
  });

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final summary = shareContentsSummary(
          records: records,
          sections: sections,
        );
        return AppFormField(
          label: 'What to share',
          inset: inset,
          child: AppPickerField(
            leading: AppIcons.safe,
            text: summary.isEmpty ? 'Pick from your vault' : summary,
            isPlaceholder: summary.isEmpty,
            onTap: () => openShareContentsPicker(
              context,
              records: records,
              sections: sections,
              toggleRecord: toggleRecord,
              toggleSection: toggleSection,
            ),
          ),
        );
      },
    );
  }
}
