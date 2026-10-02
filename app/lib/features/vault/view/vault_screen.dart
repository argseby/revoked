import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/files/file_saver.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_search_field.dart';
import 'package:revoked_app/core/widgets/app_menu_button.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_filter_chips.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/features/vault/view/section_create_sheet.dart';

class VaultScreen extends StatefulWidget {
  final String? editingShareId;
  final String? shareFilterId;

  const VaultScreen({super.key, this.editingShareId, this.shareFilterId});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

/// Which records the chips above the list let through.
enum _VaultFilter { all, shared, files, hidden }

class _VaultScreenState extends State<VaultScreen> {
  late TableStore<models.Record> _tableController;
  final Local<_VaultFilter> _filter = Local(_VaultFilter.all);

  @override
  void initState() {
    super.initState();
    final store = Stores.vault;

    _tableController = TableStore<models.Record>(
      getSourceItems: () => store.records.toList(),
      fieldGetters: {
        'label': (r) => r.label,
        'key': (r) => r.key,
        'value': (r) => r.value,
        'type': (r) => r.type,
        'format': (r) => r.format,
        'created': (r) => r.created ?? '',
      },
      defaultSort: 'created_desc',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ShellSlots.title.claim(_title);
        ShellSlots.action.claim(_primaryAction);
      }
      store.loadRecords();
      if (widget.editingShareId != null || widget.shareFilterId != null) {
        Stores.shares.loadShares();
      }
    });
  }

  @override
  void dispose() {
    ShellSlots.title.release(_title);
    ShellSlots.action.release(_primaryAction);
    _tableController.dispose();
    super.dispose();
  }

  /// The top bar carries the search; its hint carries the count.
  Widget _title(BuildContext context) {
    final count = Stores.vault.recordCount;
    return AppSearchField<models.Record>(
      controller: _tableController,
      hint: 'Search $count ${count == 1 ? 'record' : 'records'}',
    );
  }

  /// The way out of a mode the screen is held in — editing a section's records,
  /// or picking what a share exposes. Creation lives on the shell's floating
  /// button, so there is nothing here otherwise.
  Widget _primaryAction(BuildContext context) {
    final store = Stores.vault;
    if (store.editingSectionId != null) {
      return AppButton(
        icon: AppIcons.check,
        label: 'Done',
        onTap: () => store.editSection(null),
      );
    }
    final shareId = widget.editingShareId ?? widget.shareFilterId;
    if (shareId != null) {
      // Back to the link these picks belong to.
      return AppButton(
        icon: AppIcons.check,
        label: 'Done',
        onTap: () => context.go(AppRoutes.shareDetailFor(shareId)),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.vault;

    return Observer(
      builder: (_) {
        if (store.isLoading &&
            store.records.isEmpty &&
            store.sections.isEmpty) {
          return const Center(child: AppSpinner(large: true));
        }

        if (store.errorMessage != null) {
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.screenH(context),
            ),
            child: AppLoadError(
              title: 'Failed to load data',
              message: store.errorMessage!,
              onRetry: store.loadRecords,
            ),
          );
        }

        if (store.records.isEmpty && store.sections.isEmpty) {
          return AppEmptyState(
            icon: AppIcons.safe,
            title: 'Your vault is empty',
            subtitle: 'Tap + to create a section or record.',
          );
        }

        final shareFilter = _shareById(widget.shareFilterId);
        final shareEdit = _shareById(widget.editingShareId);
        Section? editingSection;
        for (final s in store.sections) {
          if (s.id == store.editingSectionId) editingSection = s;
        }

        // Which links reach each record, directly or through a section — the
        // "2 links" on a row and the Shared chip both read this.
        final sectionLinks = {
          for (final s in store.sections)
            s.id: Stores.shares.linksForSection(s.id).map((l) => l.id).toSet(),
        };
        int linkCount(models.Record r) {
          final ids = Stores.shares
              .linksForRecord(r.id)
              .map((l) => l.id)
              .toSet();
          for (final s in store.sections) {
            if (s.records.contains(r.id)) ids.addAll(sectionLinks[s.id]!);
          }
          return ids.length;
        }

        final matches = _tableController.filteredItems;
        final links = {for (final r in matches) r.id: linkCount(r)};
        final filter = _filter.value;
        bool chip(models.Record r) => switch (filter) {
          _VaultFilter.all => true,
          _VaultFilter.shared => links[r.id]! > 0,
          _VaultFilter.files => r.isFile,
          _VaultFilter.hidden => r.isHidden,
        };

        final chips = AppFilterChips<_VaultFilter>(
          selected: filter,
          onSelected: (f) => _filter.value = f,
          options: [
            AppFilterOption(
              value: _VaultFilter.all,
              label: 'All',
              count: matches.length,
            ),
            AppFilterOption(
              value: _VaultFilter.shared,
              label: 'Shared',
              count: matches.where((r) => links[r.id]! > 0).length,
            ),
            AppFilterOption(
              value: _VaultFilter.files,
              label: 'Files',
              count: matches.where((r) => r.isFile).length,
            ),
            AppFilterOption(
              value: _VaultFilter.hidden,
              label: 'Hidden',
              count: matches.where((r) => r.isHidden).length,
            ),
          ],
        );

        var records = matches.where(chip).toList();

        // Picking a section's records: every record once, ticked if the
        // section holds it.
        if (editingSection != null) {
          final section = editingSection;
          return AppListPage(
            banners: [
              AppListBanner(
                icon: AppIcons.plusSlashMinus,
                message:
                    'Editing section "${_sectionName(section)}". Tick the '
                    'records it should hold.',
              ),
            ],
            filters: chips,
            emptyMessage: records.isEmpty
                ? 'No records match your filters.'
                : null,
            groups: [
              AppListGroup(
                title: 'All records',
                noun: 'records',
                children: [
                  for (final r in records)
                    _recordRow(
                      r,
                      links: links[r.id]!,
                      selected: section.records.contains(r.id),
                      onToggle: (on) => _toggleSectionRecord(section, r, on),
                    ),
                ],
              ),
            ],
          );
        }

        var sectionsSource = store.sections.toList();
        if (shareFilter != null) {
          final allowedSections = shareFilter.sections.toSet();
          final allowedRecords = {
            ...shareFilter.records,
            for (final s in store.sections)
              if (allowedSections.contains(s.id)) ...s.records,
          };
          records = records
              .where((r) => allowedRecords.contains(r.id))
              .toList();
          sectionsSource = sectionsSource
              .where((s) => allowedSections.contains(s.id))
              .toList();
        }

        final searchQuery = _tableController.searchQuery.toLowerCase();
        final byId = {for (final r in records) r.id: r};
        final visibleSections = <(Section, List<models.Record>)>[];
        for (final section in sectionsSource) {
          final sectionRecords = [
            for (final id in section.records)
              if (byId[id] != null) byId[id]!,
          ];
          final matchesSection =
              filter == _VaultFilter.all &&
              (section.name.toLowerCase().contains(searchQuery) ||
                  section.key.toLowerCase().contains(searchQuery));
          if (matchesSection || sectionRecords.isNotEmpty) {
            visibleSections.add((section, sectionRecords));
          }
        }

        // Sort sections if active sort applies to them
        final sortBy = _tableController.sortBy;
        final parts = sortBy.split('_');
        if (parts.length >= 2) {
          final col = parts.sublist(0, parts.length - 1).join('_');
          final asc = parts.last == 'asc';
          String field(Section s) => switch (col) {
            'label' => s.name,
            'key' => s.key,
            'created' => s.created ?? '',
            _ => '',
          };
          if (col == 'label' || col == 'key' || col == 'created') {
            visibleSections.sort((a, b) {
              final comp = field(
                a.$1,
              ).toLowerCase().compareTo(field(b.$1).toLowerCase());
              return asc ? comp : -comp;
            });
          }
        }

        final filed = store.sections.expand((s) => s.records).toSet();
        final unsorted = records.where((r) => !filed.contains(r.id)).toList();

        Widget row(models.Record r) => _recordRow(
          r,
          links: links[r.id]!,
          selected: shareEdit?.records.contains(r.id),
          onToggle: shareEdit == null
              ? null
              : (on) => _toggleShareRecord(shareEdit, r, on),
        );

        final groups = <Widget>[
          for (final (section, sectionRecords) in visibleSections)
            AppListGroup(
              key: ValueKey('${section.id}-$filter'),
              title: section.isRequested
                  ? '${_sectionName(section)} · requested by '
                        '${section.requestedBy}'
                  : _sectionName(section),
              noun: 'records',
              previewCount: 5,
              trailing: shareEdit != null
                  ? _WholeSectionToggle(
                      selected: shareEdit.sections.contains(section.id),
                      onChanged: (on) =>
                          _toggleShareSection(shareEdit, section, on),
                    )
                  : _sectionMenu(context, section, sectionRecords.length),
              children: sectionRecords.isEmpty
                  ? const [
                      AppDetailRow(
                        icon: AppIcons.info,
                        label: 'No records in this section yet',
                      ),
                    ]
                  : [for (final r in sectionRecords) row(r)],
            ),
          if (unsorted.isNotEmpty)
            AppListGroup(
              key: ValueKey('unsorted-$filter'),
              title: visibleSections.isEmpty ? 'Records' : 'Not in a section',
              noun: 'records',
              previewCount: visibleSections.isEmpty ? 0 : 5,
              children: [for (final r in unsorted) row(r)],
            ),
        ];

        return AppListPage(
          banners: [
            if (shareFilter != null)
              AppListBanner(
                icon: AppIcons.funnel,
                message: 'Showing what "${shareFilter.label}" shares.',
                action: AppButton(
                  icon: AppIcons.x,
                  label: 'Clear',
                  style: AppButtonStyle.accent,
                  size: AppButtonSize.small,
                  onTap: () => context.go(AppRoutes.vault),
                ),
              ),
            if (shareEdit != null)
              AppListBanner(
                icon: AppIcons.plusSlashMinus,
                message:
                    'Choosing what "${shareEdit.label}" shares. Tick whole '
                    'sections or single records.',
              ),
          ],
          filters: chips,
          emptyMessage: groups.isEmpty ? 'No items match your filters.' : null,
          groups: groups,
        );
      },
    );
  }

  Link? _shareById(String? id) {
    if (id == null) return null;
    for (final s in Stores.shares.shares) {
      if (s.id == id) return s;
    }
    return null;
  }

  String _sectionName(Section s) => s.name.isEmpty ? s.key : s.name;

  /// A record as one line. While picking (a section's records, a share's
  /// contents) [selected] is set and the row ticks in place; otherwise it
  /// opens the record's page.
  Widget _recordRow(
    models.Record r, {
    required int links,
    bool? selected,
    ValueChanged<bool>? onToggle,
  }) {
    final picking = selected != null && onToggle != null;
    return AppListRow(
      icon: RecordTypeUtils.icon(r.type),
      leading: picking
          ? Center(
              child: AppCheckbox(
                value: selected,
                onChanged: (v) => onToggle(v ?? false),
              ),
            )
          : null,
      title: r.label.isEmpty ? r.key : r.label,
      subtitle: _preview(r),
      // Quiet text, not a badge: most records are shared somewhere, and a
      // badge on every row is the noise this list is meant to be rid of.
      trailing: links > 0
          ? AppText('$links ${links == 1 ? 'link' : 'links'}').small.muted
          : null,
      showChevron: !picking,
      onTap: picking
          ? () => onToggle(!selected)
          : () => context.go(AppRoutes.recordDetailFor(r.id)),
    );
  }

  /// One line of the value, masked while the record is hidden.
  String _preview(models.Record r) {
    final hidden = r.isHidden && !Stores.vault.isRevealed(r.id);
    if (r.isFile) {
      final name = hidden ? '••••••••' : r.displayName;
      return '$name · ${formatBytes(r.size)}';
    }
    if (hidden) return '••••••••••••';
    var value = r.value;
    if (r.isAlias) {
      for (final p in Stores.vault.records) {
        if (p.id == r.aliasOf) value = p.value;
      }
      value = 'Alias · $value';
    }
    value = value.replaceAll('\n', ' ');
    return value.isEmpty ? '—' : value;
  }

  Widget _sectionMenu(BuildContext context, Section section, int shown) {
    final store = Stores.vault;
    final access = Stores.shares.linksForSection(section.id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppText('${section.records.length}').small.muted,
        AppSpacing.gapXs,
        AppMenuButton(
          icon: AppIcons.threeDotsVertical,
          tooltip: 'Section actions',
          style: AppButtonStyle.ghost,
          size: AppButtonSize.small,
          chevron: false,
          items: [
            AppMenuItem(
              icon: AppIcons.plusSlashMinus,
              label: 'Add or remove records',
              onSelected: () => store.editSection(section.id),
            ),
            if (access.isNotEmpty)
              AppMenuItem(
                icon: AppIcons.share,
                label: 'Who has access · ${access.length}',
                onSelected: () => _showVaultAccessSheet(
                  context,
                  title: _sectionName(section),
                  links: access,
                ),
              ),
            AppMenuItem(
              icon: AppIcons.pen,
              label: 'Rename',
              onSelected: () => openSectionRenameSheet(
                context: context,
                store: store,
                section: section,
              ),
            ),
            AppMenuItem(
              icon: AppIcons.duplicate,
              label: 'Duplicate',
              onSelected: () => openSectionCreateSheet(
                context: context,
                store: store,
                authStore: Stores.auth,
                initialSection: section,
              ),
            ),
            null,
            AppMenuItem(
              icon: AppIcons.trash,
              label: 'Delete',
              destructive: true,
              onSelected: () =>
                  _confirmDeleteSection(context, store, section.id),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _toggleSectionRecord(
    Section section,
    models.Record record,
    bool selected,
  ) async {
    final newRecords = List<String>.from(section.records);
    if (selected && !newRecords.contains(record.id)) {
      newRecords.add(record.id);
    } else if (!selected) {
      newRecords.remove(record.id);
    }
    final ok = await Stores.vault.updateSection(section.id, {
      'records': newRecords,
    });
    if (ok && mounted) {
      AppToast.success(
        context,
        selected ? 'Added record to section' : 'Removed record from section',
      );
    }
  }

  Future<void> _toggleShareRecord(
    Link share,
    models.Record record,
    bool selected,
  ) async {
    final newRecords = List<String>.from(share.records);
    if (selected) {
      if (!newRecords.contains(record.id)) newRecords.add(record.id);
    } else {
      newRecords.remove(record.id);
    }
    await Stores.shares.updateShare(share.id, {'records': newRecords});
    if (mounted) {
      AppToast.success(
        context,
        selected
            ? 'Added record to public share'
            : 'Removed record from public share',
      );
    }
  }

  /// Sharing a whole section also lists its records on the link, as the old
  /// section toggle did, so the share's record list stays complete.
  Future<void> _toggleShareSection(
    Link share,
    Section section,
    bool selected,
  ) async {
    final newSections = List<String>.from(share.sections);
    final newRecords = List<String>.from(share.records);
    if (selected) {
      if (!newSections.contains(section.id)) newSections.add(section.id);
      for (final rId in section.records) {
        if (!newRecords.contains(rId)) newRecords.add(rId);
      }
    } else {
      newSections.remove(section.id);
      for (final rId in section.records) {
        newRecords.remove(rId);
      }
    }
    await Stores.shares.updateShare(share.id, {
      'sections': newSections,
      'records': newRecords,
    });
  }

  Future<void> _confirmDeleteSection(
    BuildContext context,
    VaultStore store,
    String id,
  ) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete section',
      message:
          'This action cannot be undone. This will permanently delete '
          'the section.',
      content: ApiPreview(
        spec: VaultStore.deleteSectionSpec(id),
        title: 'API request · delete',
      ),
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await store.deleteSection(id);
    if (ok && context.mounted) {
      AppToast.success(context, 'Section deleted successfully');
    }
  }
}

/// Bottom sheet listing the active links that expose a vault entry or section,
/// showing the domain behind each and a jump to manage it.
void _showVaultAccessSheet(
  BuildContext context, {
  required String title,
  required List<Link> links,
}) {
  final base = Stores.api.baseUrl;
  final host = Uri.tryParse(base)?.host ?? '';
  showAppSheet(
    context: context,
    builder: (sheetCtx) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxs,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Who has access').header,
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${links.length} active link${links.length == 1 ? '' : 's'} '
            'expose "$title".',
          ).muted.small,
          const SizedBox(height: AppSpacing.md),
          for (final l in links)
            _VaultAccessRow(
              link: l,
              host: host.isEmpty ? base : host,
              onOpen: () {
                Navigator.of(sheetCtx).pop();
                context.go(AppRoutes.shareDetailFor(l.id));
              },
            ),
        ],
      ),
    ),
  );
}

class _VaultAccessRow extends StatelessWidget {
  final Link link;
  final String host;
  final VoidCallback onOpen;
  const _VaultAccessRow({
    required this.link,
    required this.host,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = link.label.isEmpty ? link.slug : link.label;
    final kind = link.request.isEmpty ? 'Manual share' : 'From a request';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: AppRadius.allMd,
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: AppRadius.allMd,
                ),
                child: Icon(AppIcons.link, size: 18, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).small,
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '$kind · $host/s/${link.slug}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).mono.muted.small,
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                AppIcons.chevronRight,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The share-picking control on a section's header: shares the whole section.
class _WholeSectionToggle extends StatelessWidget {
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _WholeSectionToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.allMd,
      onTap: () => onChanged(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Whole section').small.muted,
            AppSpacing.gapXs,
            AppCheckbox(
              value: selected,
              onChanged: (v) => onChanged(v ?? false),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tinted square behind each choice in the "Create New" sheet.
