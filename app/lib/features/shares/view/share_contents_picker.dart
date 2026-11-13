import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_composer.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/features/vault/view/record_composer.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:material_ui/material_ui.dart';
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
    for (final s in [...Stores.vault.sections, ...Stores.vault.sharedSections])
      if (pickedSections.contains(s.id)) s.name,
    for (final r in Stores.vault.records)
      if (pickedRecords.contains(r.id)) recordTitle(r),
    for (final r in Stores.vault.sharedRecords)
      if (pickedRecords.contains(r.id)) recordTitle(r),
  ];
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  return '${names.first} and ${names.length - 1} more';
}

/// A record's name as a person reads it: its label, else its key.
String recordTitle(models.Record r) => r.label.isEmpty ? r.key : r.label;

/// Lets the owner tick the sections and records a share gives out. A section
/// is shared with the records it holds now; one added later joins the link
/// only when ticked on it.
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
    panelWidth: vaultComposerWidth,
    builder: (_) => _ShareContentsPicker(
      records: pickedRecords,
      sections: pickedSections,
      toggleRecord: onRecord,
      toggleSection: onSection,
    ),
  );
}

class _ShareContentsPicker extends StatefulWidget {
  final Set<String> records;
  final Set<String> sections;
  final void Function(String) toggleRecord;
  final void Function(String) toggleSection;
  const _ShareContentsPicker({
    required this.records,
    required this.sections,
    required this.toggleRecord,
    required this.toggleSection,
  });
  @override
  State<_ShareContentsPicker> createState() => _ShareContentsPickerState();
}

class _ShareContentsPickerState extends State<_ShareContentsPicker> {
  final _query = Local('');
  final _filter = Local('all');
  final _sort = Local('name');

  @override
  Widget build(BuildContext context) =>
      Observer(builder: (_) => _build(context));

  Widget _build(BuildContext context) {
    final vault = Stores.vault;
    final sections = <String, Section>{
      for (final s in [...vault.sections, ...vault.sharedSections]) s.id: s,
    }.values.toList();
    final records = <String, models.Record>{
      for (final r in [...vault.records, ...vault.sharedRecords]) r.id: r,
    }.values.where((r) => !r.isLocked).toList();
    final inherited = <String>{
      for (final s in sections)
        if (widget.sections.contains(s.id)) ...s.records,
    };
    final q = _query.value.trim().toLowerCase();
    bool matches(models.Record r, {bool sectionMatch = false}) =>
        (q.isEmpty ||
            sectionMatch ||
            '${recordTitle(r)} ${r.key}'.toLowerCase().contains(q)) &&
        switch (_filter.value) {
          'files' => r.isFile,
          'values' => !r.isFile,
          'selected' =>
            widget.records.contains(r.id) || inherited.contains(r.id),
          _ => true,
        };
    records.sort((a, b) {
      if (_sort.value == 'newest') {
        return (b.created ?? '').compareTo(a.created ?? '');
      }
      final result = recordTitle(a)
          .toLowerCase()
          .compareTo(recordTitle(b).toLowerCase());
      return _sort.value == 'reverse' ? -result : result;
    });
    sections.sort((a, b) {
      if (_sort.value == 'newest') {
        return (b.created ?? '').compareTo(a.created ?? '');
      }
      final result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return _sort.value == 'reverse' ? -result : result;
    });
    Widget row(models.Record r) {
      final included = inherited.contains(r.id);
      return AppCheckRow(
        label: recordTitle(r),
        icon: RecordTypeUtils.icon(r.type),
        subtitle: included
            ? 'Included with a selected section'
            : r.sealed
            ? 'End-to-end encrypted'
            : r.isFile
            ? 'File'
            : r.isHidden
            ? 'Hidden value'
            : r.key,
        value: included || widget.records.contains(r.id),
        onChanged: included ? null : (_) => widget.toggleRecord(r.id),
      );
    }

    final groups = <Widget>[];
    final grouped = <String>{for (final s in sections) ...s.records};
    for (final section in sections) {
      final sectionMatch = '${section.name} ${section.key}'
          .toLowerCase()
          .contains(q);
      final contents = records
          .where(
            (r) =>
                section.records.contains(r.id) &&
                matches(r, sectionMatch: sectionMatch),
          )
          .toList();
      final showEmpty = _filter.value == 'all' && (q.isEmpty || sectionMatch);
      final showSelected =
          _filter.value == 'selected' &&
          widget.sections.contains(section.id) &&
          (q.isEmpty || sectionMatch);
      if (contents.isEmpty && !showEmpty && !showSelected) continue;
      groups.add(
        AppListGroup(
          title: section.name,
          trailing: const SizedBox.shrink(),
          children: [
            AppCheckRow(
              label: 'Entire section',
              subtitle:
                  'All ${section.records.length} records it holds now.',
              icon: AppIcons.folder,
              value: widget.sections.contains(section.id),
              onChanged: (_) => widget.toggleSection(section.id),
            ),
            for (final r in contents) row(r),
          ],
        ),
      );
    }
    final ungrouped = records
        .where((r) => !grouped.contains(r.id) && matches(r))
        .toList();
    if (ungrouped.isNotEmpty) {
      groups.add(
        AppListGroup(
          title: 'Without a section',
          trailing: const SizedBox.shrink(),
          children: [for (final r in ungrouped) row(r)],
        ),
      );
    }
    final picked = widget.records.length + widget.sections.length;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: composerMaxHeight(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VaultComposerHeader(
            title: 'What to share',
            subtitle: 'Choose records or a whole section.',
            area: 'Shares',
            areaIcon: AppIcons.share,
            onClose: () => Navigator.of(context).pop(),
          ),
          const AppDivider(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              children: [
                AppTextField(
                  hint: 'Search records and sections',
                  leading: const Icon(AppIcons.search),
                  onChanged: (value) => _query.value = value,
                ),
                AppSpacing.gapMd,
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _filter.value,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Filter'),
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('All records'),
                          ),
                          DropdownMenuItem(
                            value: 'values',
                            child: Text('Values'),
                          ),
                          DropdownMenuItem(
                            value: 'files',
                            child: Text('Files'),
                          ),
                          DropdownMenuItem(
                            value: 'selected',
                            child: Text('Selected'),
                          ),
                        ],
                        onChanged: (value) => _filter.value = value ?? 'all',
                      ),
                    ),
                    AppSpacing.gapMd,
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _sort.value,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Sort'),
                        items: const [
                          DropdownMenuItem(
                            value: 'name',
                            child: Text('Name A–Z'),
                          ),
                          DropdownMenuItem(
                            value: 'reverse',
                            child: Text('Name Z–A'),
                          ),
                          DropdownMenuItem(
                            value: 'newest',
                            child: Text('Newest first'),
                          ),
                        ],
                        onChanged: (value) => _sort.value = value ?? 'name',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              children: groups.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xl,
                        ),
                        child: Text(
                          records.isEmpty && sections.isEmpty
                              ? 'The vault is empty. Only existing records can be shared.'
                              : 'No records or sections match your search and filters.',
                        ).small.muted,
                      ),
                    ]
                  : groups,
            ),
          ),
          const AppDivider(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: AppButton(
              icon: AppIcons.check,
              label: picked == 0
                  ? 'Done'
                  : 'Share $picked ${picked == 1 ? 'item' : 'items'}',
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
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
        return AppComposerField(
          label: 'What to share',
          inset: inset,
          child: AppPickerField(
            leading: AppIcons.safe,
            text: summary.isEmpty ? 'Select from the vault' : summary,
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
