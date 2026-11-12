import 'package:flutter/material.dart';
import 'package:revoked_app/core/widgets/app_collection_header.dart';
import 'package:revoked_app/features/vault/view/record_actions.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/utils/value_kind.dart';
import 'package:revoked_app/features/shares/utils/record_access.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/files/file_saver.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/features/settings/view/settings_pages.dart';
import 'package:revoked_app/core/state/refresh_on_entry.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_edit_sheet.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/audience_tag.dart';
import 'package:revoked_app/core/models/connection.dart';
import 'package:revoked_app/core/utils/people.dart';
import 'package:revoked_app/core/widgets/app_menu_button.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_filter_menu.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/redacted_value.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';
import 'package:revoked_app/features/sealing/view/sealing_section.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/features/vault/tool_reach_confirm.dart';
import 'package:revoked_app/features/vault/view/section_create_sheet.dart';
import 'package:revoked_app/core/widgets/access_sheet.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/features/vault/view/vault_create_sheet.dart';

class VaultScreen extends StatefulWidget {
  final String? editingShareId;
  final String? shareFilterId;

  const VaultScreen({super.key, this.editingShareId, this.shareFilterId});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

/// What the Filter above the list lets through. None ticked lets everything
/// through; several let through a record that is any of them.
enum _VaultFilter { shared, files, hidden }

/// Which section or item view is selected in the library.
sealed class _Pane {
  const _Pane();
}

/// Every own record, in one list.
class _AllPane extends _Pane {
  const _AllPane();
}

/// One of this person's sections.
class _SectionPane extends _Pane {
  final String id;
  const _SectionPane(this.id);
}

/// A section another member shared.
class _SharedPane extends _Pane {
  final String id;
  const _SharedPane(this.id);
}

/// The own records no section holds.
class _UnsortedPane extends _Pane {
  const _UnsortedPane();
}

class _VaultScreenState extends State<VaultScreen> with RefreshOnEntry {
  late TableStore<models.Record> _tableController;
  final Local<Set<_VaultFilter>> _filters = Local(const {});

  /// Who sees a record, as the Filter's "Visible to" ticks it (`private`,
  /// `workspace`, `group:<id>`); none ticked lets all through. A record
  /// counts as seen by its own audience and by each section holding it.
  final Local<Set<String>> _audiences = Local(const {});

  static Audience _sectionAudience(Section s) =>
      Audience(s.audienceKind, s.audienceGroups);

  static Audience _recordAudience(models.Record r) =>
      Audience(r.audienceKind, r.audienceGroups);

  /// A record's own audience and those of the sections holding it.
  List<Audience> _audiencesOf(models.Record r) => [
    _recordAudience(r),
    for (final s in Stores.vault.sections)
      if (s.records.contains(r.id)) _sectionAudience(s),
  ];

  /// The section selected in the library, preserved while searching.
  final Local<_Pane> _pane = Local(const _AllPane());

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
      searchFields: const ['label', 'key'],
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellSlots.action.claim(_primaryAction);
      // Which tool keeps or reads a section is said on the section itself.
      if (Stores.connections.connections.isEmpty) Stores.connections.load();
      Stores.shares.loadIfDue();
    });
  }

  @override
  void dispose() {
    ShellSlots.action.release(_primaryAction);
    _tableController.dispose();
    super.dispose();
  }

  @override
  void refresh() {
    Stores.vault.loadIfDue();
    Stores.shares.loadIfDue();
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

  /// Search, Show and Sort for the records; [links] says how many links
  /// reach each of [matches], for the Shared count.
  AppListToolbar _toolbar(List<models.Record> matches, Map<String, int> links) {
    final filed = Stores.vault.sections
        .expand((section) => section.records)
        .toSet();
    return AppListToolbar(
      key: const ValueKey('vault-toolbar'),
      totalCount: matches.length,
      allLabel: 'All items',
      isAllSelected: () => _pane.value is _AllPane,
      quickSections: const ['View', 'Show'],
      query: _tableController.query,
      onQueryChanged: _tableController.setQuery,
      searchHint: 'Find an item',
      onClearFilters: () {
        _pane.value = const _AllPane();
        _filters.value = const {};
        _audiences.value = const {};
      },
      sections: () => [
        if (filed.isNotEmpty)
          AppChecklistSection(
            title: 'View',
            selected: {if (_pane.value is _UnsortedPane) 'unfiled'},
            onToggle: (_, on) =>
                _pane.value = on ? const _UnsortedPane() : const _AllPane(),
            items: [
              AppChecklistItem(
                id: 'unfiled',
                label: 'Not in a section',
                count: matches.where((r) => !filed.contains(r.id)).length,
              ),
            ],
          ),
        AppChecklistSection(
          title: 'Show',
          selected: {for (final f in _filters.value) f.name},
          onToggle: (id, on) {
            final f = _VaultFilter.values.byName(id);
            _filters.value = on
                ? {..._filters.value, f}
                : ({..._filters.value}..remove(f));
          },
          items: [
            AppChecklistItem(
              id: _VaultFilter.shared.name,
              label: 'Shared by you',
              count: matches.where((r) => links[r.id]! > 0).length,
            ),
            AppChecklistItem(
              id: _VaultFilter.files.name,
              label: 'Files',
              count: matches.where((r) => r.isFile).length,
            ),
            AppChecklistItem(
              id: _VaultFilter.hidden.name,
              label: 'Hidden',
              count: matches.where((r) => r.isHidden).length,
            ),
          ],
        ),
        ?audienceFilterSection(
          items: [for (final r in matches) _audiencesOf(r)],
          selected: _audiences.value,
          onToggle: (id, on) => _audiences.value = on
              ? {..._audiences.value, id}
              : ({..._audiences.value}..remove(id)),
        ),
      ],
      sort: () => _tableController.sortBy,
      onSort: _tableController.setSort,
      defaultSort: _tableController.defaultSort,
      sortOptions: const [
        AppSortOption('created_desc', 'Newest first'),
        AppSortOption('created_asc', 'Oldest first'),
        AppSortOption('label_asc', 'Label A–Z'),
        AppSortOption('type_asc', 'Type'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => _body(context);

  Widget _collectionHeader(BuildContext context) => AppCollectionHeader(
    title: 'Your vault',
    description: 'Keep your information here. Choose what you share.',
    action: AppButton(
      icon: AppIcons.plus,
      label: 'Add item',
      onTap: () => openVaultCreateSheet(context),
    ),
  );

  Widget _body(BuildContext context) {
    final store = Stores.vault;

    return AppLoadFade(
      loading: () =>
          store.loadState.isFirstLoad &&
          store.records.isEmpty &&
          store.sections.isEmpty &&
          store.sharedSections.isEmpty,
      skeleton: AppPageBody(
        children: [
          _collectionHeader(context),
          const AppListSkeleton(group: 'Records', embedded: true),
        ],
      ),
      builder: (_) {
        if (store.records.isEmpty &&
            store.sections.isEmpty &&
            store.sharedSections.isEmpty) {
          final failure = store.loadState.error;
          // Nothing to list still keeps Search and filter in the top bar.
          Widget bare(Widget child) =>
              AppPageBody(children: [_collectionHeader(context), child]);
          if (failure != null) {
            return bare(
              AppLoadError(
                title: 'The vault could not be loaded',
                message: failure,
                onRetry: store.loadRecords,
              ),
            );
          }
          return bare(
            AppEmptyState(
              icon: AppIcons.safe,
              title: 'No records',
              subtitle:
                  'A record holds a single value, such as an IBAN or a password. '
                  'Changes apply to every link that shares it.',
              example: const AppEmptyExample(
                title: 'IBAN',
                detail: 'DE89 •••• •••• 3000',
                badge: 'hidden',
              ),
              steps: const [
                AppEmptyStep('Record', 'A single value, optionally hidden'),
                AppEmptyStep('Section', 'Records shared together'),
                AppEmptyStep('Link', 'Shows the current value until revoked'),
              ],
              learnMoreLabel: 'How the vault works',
              learnMoreUrl: '${AppConfig.docsUrl}/guide/vault/',
            ),
          );
        }

        final shareFilter = _shareById(widget.shareFilterId);
        final shareEdit = _shareById(widget.editingShareId);
        Section? editingSection;
        for (final s in store.sections) {
          if (s.id == store.editingSectionId) editingSection = s;
        }

        // Use the same access rules as the detail page, including aliases
        // and encrypted records that cannot be read through a section.
        int linkCount(models.Record r) => accessForRecord(
          r.id,
          links: Stores.shares.shares,
          sections: store.sections,
          records: store.records,
        ).where((access) => access.isOpen).length;

        final matches = _tableController.filteredItems;
        final links = {for (final r in matches) r.id: linkCount(r)};
        final filters = _filters.value;
        bool kind(models.Record r) =>
            filters.isEmpty ||
            (filters.contains(_VaultFilter.shared) && links[r.id]! > 0) ||
            (filters.contains(_VaultFilter.files) && r.isFile) ||
            (filters.contains(_VaultFilter.hidden) && r.isHidden);

        final audiences = _audiences.value;
        final toolbar = _toolbar(matches, links);
        final searching = _tableController.query.trim().isNotEmpty;

        var records = matches
            .where(
              (r) => kind(r) && audienceMatches(audiences, _audiencesOf(r)),
            )
            .toList();

        // Picking a section's records: every record once, ticked if the
        // section holds it.
        if (editingSection != null) {
          final section = editingSection;
          return AppListPage(
            banners: [
              AppListBanner(
                icon: AppIcons.plusSlashMinus,
                message:
                    'Editing "${_sectionName(section)}". Ticked records belong '
                    'to it.',
              ),
            ],
            toolbar: toolbar,
            emptyMessage: records.isEmpty
                ? 'No records match the search or filters.'
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

        final banners = [
          if (store.loadState.error != null)
            AppRefreshFailed(onRetry: store.loadRecords),
          if (SealingAlarm.shows) const SealingAlarm(),
        ];

        // Normal browsing uses a section library. Share picking keeps the
        // checkbox list, including whole-section selection.
        if (shareFilter == null && shareEdit == null) {
          return _library(
            context,
            records: records,
            links: links,
            banners: banners,
            toolbar: toolbar,
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

        final byId = {for (final r in records) r.id: r};
        final visibleSections = <(Section, List<models.Record>)>[];
        for (final section in sectionsSource) {
          // Under "Visible to", a record shows in a section when the section
          // or the record itself is seen by the ticked audience.
          final sectionRecords = [
            for (final id in section.records)
              if (byId[id] case final r?)
                if (audienceMatches(audiences, [
                  _sectionAudience(section),
                  _recordAudience(r),
                ]))
                  r,
          ];
          // Unfiltered, a section shows even when empty, so the vault's shape
          // stays visible; a search or filter narrows to the ones holding a
          // match.
          final unfiltered =
              filters.isEmpty &&
              !searching &&
              audienceMatches(audiences, [_sectionAudience(section)]);
          if (unfiltered || sectionRecords.isNotEmpty) {
            visibleSections.add((section, sectionRecords));
          }
        }
        _sortSections(visibleSections);

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

        final filterKey = [
          ...(filters.map((f) => f.name).toList()..sort()),
          ...(audiences.toList()..sort()),
          if (searching) 'q',
        ].join();
        final groups = <Widget>[
          for (final (section, sectionRecords) in visibleSections)
            AppListGroup(
              key: ValueKey('${section.id}-$filterKey'),
              title: _sectionName(section),
              badge: _sectionBadges(context, section),
              noun: 'records',
              previewCount: 5,
              trailing: shareEdit != null
                  ? _WholeSectionToggle(
                      selected: shareEdit.sections.contains(section.id),
                      onChanged: (on) =>
                          _toggleShareSection(shareEdit, section, on),
                    )
                  : _sectionMenu(context, section, sectionRecords.length),
              children: [
                ...?_sectionSource(context, section),
                if (sectionRecords.isEmpty)
                  const AppDetailRow(
                    icon: AppIcons.info,
                    label: 'No records in this section',
                  )
                else
                  for (final r in sectionRecords) row(r),
              ],
            ),
          if (unsorted.isNotEmpty)
            AppListGroup(
              key: ValueKey('unsorted-$filterKey'),
              title: visibleSections.isEmpty ? 'Records' : 'Not in a section',
              noun: 'records',
              previewCount: visibleSections.isEmpty ? 0 : 5,
              children: [for (final r in unsorted) row(r)],
            ),
          // What other members shared: read-only, below this person's own.
          // Left out while picking, which works on their own records; a
          // search keeps only the sections holding a match.
          if (shareFilter == null &&
              shareEdit == null &&
              _sharedVisible(filters))
            for (final section in store.sharedSections)
              if (audienceMatches(audiences, [_sectionAudience(section)]))
                ?_sharedGroup(
                  context,
                  section,
                  filters,
                  filterKey,
                  searching: searching,
                ),
        ];

        return AppListPage(
          banners: [
            ...banners,
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
                    'Editing what "${shareEdit.label}" shares. Whole sections '
                    'or single records can be ticked.',
              ),
          ],
          toolbar: toolbar,
          emptyMessage: groups.isEmpty
              ? 'Nothing matches the search or filters.'
              : null,
          groups: groups,
        );
      },
    );
  }

  /// Orders sections by the active sort, when it is one sections have.
  void _sortSections(List<(Section, List<models.Record>)> sections) {
    final parts = _tableController.sortBy.split('_');
    if (parts.length < 2) return;
    final col = parts.sublist(0, parts.length - 1).join('_');
    final asc = parts.last == 'asc';
    String field(Section s) => switch (col) {
      'label' => s.name,
      'key' => s.key,
      'created' => s.created ?? '',
      _ => '',
    };
    if (col == 'label' || col == 'key' || col == 'created') {
      sections.sort((a, b) {
        final comp = field(
          a.$1,
        ).toLowerCase().compareTo(field(b.$1).toLowerCase());
        return asc ? comp : -comp;
      });
    }
  }

  /// Members' shared sections are read-only and never on a link, so a
  /// Shared-only filter leaves them out; Files and Hidden look inside them.
  bool _sharedVisible(Set<_VaultFilter> filters) =>
      filters.isEmpty ||
      filters.contains(_VaultFilter.files) ||
      filters.contains(_VaultFilter.hidden);

  bool _sharedMatches(models.Record r, Set<_VaultFilter> filters) =>
      filters.isEmpty ||
      (filters.contains(_VaultFilter.files) && r.isFile) ||
      (filters.contains(_VaultFilter.hidden) && r.isHidden);

  /// A section library above one item list, at every window size.
  Widget _library(
    BuildContext context, {
    required List<models.Record> records,
    required Map<String, int> links,
    required List<Widget> banners,
    required AppListToolbar toolbar,
  }) {
    final store = Stores.vault;
    final scheme = Theme.of(context).colorScheme;
    final audiences = _audiences.value;
    var pane = _pane.value;
    Section? section;
    Section? shared;
    if (pane is _SectionPane) {
      final id = pane.id;
      section = store.sections.where((s) => s.id == id).firstOrNull;
      if (section == null) pane = const _AllPane();
    } else if (pane is _SharedPane) {
      final id = pane.id;
      shared = store.sharedSections.where((s) => s.id == id).firstOrNull;
      if (shared == null) pane = const _AllPane();
    }
    final filed = store.sections.expand((s) => s.records).toSet();
    final sections = [
      for (final s in store.sections) (s, const <models.Record>[]),
    ];
    _sortSections(sections);
    final shown = [
      for (final r in records)
        if (pane is _AllPane ||
            (pane is _UnsortedPane && !filed.contains(r.id)) ||
            (section != null && section.records.contains(r.id)))
          r,
    ];
    final sharedById = {for (final r in store.sharedRecords) r.id: r};
    final sharedShown = [
      if (shared != null && _sharedVisible(_filters.value))
        for (final id in shared.records)
          if (sharedById[id] case final r?)
            if (_sharedMatches(r, _filters.value) &&
                audienceMatches(audiences, [_sectionAudience(shared)]) &&
                _tableController.matchesQuery(r))
              r,
    ];
    final title = section != null
        ? _sectionName(section)
        : shared != null
        ? _sectionName(shared)
        : pane is _UnsortedPane
        ? 'Not in a section'
        : 'All items';
    final count = shared != null ? sharedShown.length : shown.length;
    final sectionWidgets = <Widget>[
      for (final (s, _) in sections)
        _VaultSectionTile(
          key: ValueKey('vault-section-${s.id}'),
          icon: _originOf(s)?.icon ?? AppIcons.folder,
          title: _sectionName(s),
          subtitle:
              _originOf(s)?.label ??
              '${s.records.length} ${s.records.length == 1 ? 'item' : 'items'}',
          audience: _sectionAudience(s),
          selected: section?.id == s.id,
          onTap: () => _pane.value = section?.id == s.id
              ? const _AllPane()
              : _SectionPane(s.id),
        ),
      for (final s in store.sharedSections)
        _VaultSectionTile(
          key: ValueKey('vault-section-${s.id}'),
          icon: AppIcons.personWorkspace,
          title: _sectionName(s),
          subtitle: 'Shared by ${s.ownerEmail ?? 'another member'}',
          audience: _sectionAudience(s),
          selected: shared?.id == s.id,
          onTap: () => _pane.value = shared?.id == s.id
              ? const _AllPane()
              : _SharedPane(s.id),
        ),
    ];
    return AppPageBody(
      bottomPadding: AppSpacing.gigantic,
      children: [
        _collectionHeader(context),
        for (final banner in banners) ...[banner, AppSpacing.gapLg],
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const AppText('Your sections').bold,
            AppButton(
              label: 'New section',
              emphasizeLabel: false,
              icon: AppIcons.folderPlus,
              size: AppButtonSize.small,
              style: AppButtonStyle.outline,
              onTap: () => openVaultCreateSheet(
                context,
                initialTab: VaultCreateTab.section,
              ),
            ),
          ],
        ),
        AppSpacing.gapMd,
        if (sectionWidgets.isNotEmpty)
          LayoutBuilder(
            builder: (context, box) {
              final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final columns = (box.maxWidth / (220 * scale)).floor().clamp(
                1,
                3,
              );
              final width =
                  (box.maxWidth - AppSpacing.md * (columns - 1)) / columns;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final tile in sectionWidgets)
                    SizedBox(width: width, child: tile),
                ],
              );
            },
          )
        else
          const AppText(
            'Create a section to keep related items together.',
          ).small.muted,
        AppSpacing.gapXxl,
        toolbar,
        AppSpacing.gapXl,
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppText('$title · $count').header,
            if (section != null) ...[
              _sectionBadges(context, section),
              _sectionMenu(context, section, shown.length),
            ],
          ],
        ),
        if (section != null) ...?_sectionSource(context, section),
        if (shared != null) ...[
          AppSpacing.gapSm,
          AppText(
            shared.id == VaultStore.sharedEntriesId
                ? 'Published to the workspace'
                : 'Shared by ${shared.ownerEmail ?? 'another member'}',
          ).small.muted,
        ],
        AppSpacing.gapMd,
        Divider(height: 1, color: scheme.outlineVariant),
        if (count == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.huge),
            child: const AppText(
              'No items match this view. Try another section or clear the filters.',
            ).muted,
          )
        else if (shared != null)
          for (final r in sharedShown) ...[
            _sharedRow(context, shared, r),
            Divider(height: 1, color: scheme.outlineVariant),
          ]
        else
          for (final r in shown) ...[
            _libraryRow(r, links: links[r.id]!),
            Divider(height: 1, color: scheme.outlineVariant),
          ],
        AppSpacing.gapLg,
        const AppText(
          'Open an item to view its contents or manage access.',
        ).small.muted,
      ],
    );
  }

  /// Metadata rather than values: browsing never exposes a saved secret.
  Widget _libraryRow(models.Record r, {required int links}) {
    final audience = Audience.combined(_audiencesOf(r));
    final shared = links > 0 || !audience.isPrivate;
    final scheme = Theme.of(context).colorScheme;
    final kind = valueKindOf(
      type: r.type,
      value: r.isHidden || r.isLocked ? '' : r.value,
      key: r.key,
      label: r.label,
      mime: r.mime ?? '',
      filename: r.displayName,
    );
    final icon = switch (kind) {
      ValueKind.email => AppIcons.mail,
      ValueKind.phone => AppIcons.phone,
      ValueKind.person => AppIcons.person,
      ValueKind.place => AppIcons.place,
      ValueKind.work => AppIcons.work,
      ValueKind.pdf => AppIcons.fileText,
      _ => RecordTypeUtils.icon(r.type),
    };
    final detail = [
      if (r.isLocked)
        'Not readable on this device'
      else if (r.isFile)
        '${RecordTypeUtils.label(r.type)} · ${formatBytes(r.size)}'
      else if (r.isHidden)
        'Hidden value'
      else
        RecordTypeUtils.label(r.type),
      if (r.isAlias) 'Alias',
      if (r.sealed) 'Encrypted',
      if (r.isWrittenByTool) 'From ${r.writerName}',
    ].join(' · ');
    return LayoutBuilder(
      builder: (context, box) {
        final narrow =
            box.maxWidth < 520 ||
            MediaQuery.textScalerOf(context).scale(16) > 24;
        final access =
            !Stores.shares.loadState.hasLoaded ||
                Stores.shares.loadState.error != null
            ? 'Access not confirmed'
            : links > 0
            ? 'Shared · $links ${links == 1 ? 'link' : 'links'}'
            : audience.isPrivate
            ? 'Only you'
            : audience.effectiveKind == 'workspace'
            ? 'Workspace'
            : 'Shared with groups';
        return AppListRow(
          icon: icon,
          title: r.label.isEmpty ? r.key : r.label,
          subtitle: narrow ? '$detail · $access' : detail,
          trailing: narrow
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      shared ? AppIcons.personWorkspace : AppIcons.lock,
                      size: 14,
                      color: shared ? scheme.success : scheme.onSurfaceVariant,
                    ),
                    AppSpacing.gapXs,
                    AppText(access).small,
                  ],
                ),
          audience: audience.isPrivate ? null : AudienceTag(audience),
          onTap: () => context.go(AppRoutes.recordDetailFor(r.id)),
          contextActions: () => RecordActions(context).forRecord(r),
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
      subtitleWidget: _hiddenPreview(r),
      // Everyone who sees it: its own audience and its sections' together,
      // so a private record in a workspace section reads as the workspace's.
      audience: AudienceTag(Audience.combined(_audiencesOf(r))),
      // Text, not a badge: most records are shared somewhere, and a badge on
      // every row is the noise this list is meant to be rid of. But who can
      // read a record is the vault's one question, so it is not muted.
      // A record a tool or key wrote is the exception: its name has to show,
      // or a record it made could pass as the owner's own.
      trailing: r.sealed
          ? const _EncryptedMark()
          : r.isWrittenByTool
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: AppBadge(icon: AppIcons.plug, label: r.writerName),
            )
          : links > 0
          ? _LinkCount(links)
          : null,
      showChevron: !picking,
      contextActions: picking
          ? null
          : () => RecordActions(context).forRecord(r),
      onTap: picking
          ? () => onToggle(!selected)
          : () => context.go(AppRoutes.recordDetailFor(r.id)),
    );
  }

  /// A hidden record's line: the redaction bar, and a file's size beside it.
  /// Null for a record whose value is on show.
  Widget? _hiddenPreview(models.Record r) {
    if (!r.isHidden || r.isLocked || Stores.vault.isRevealed(r.id)) return null;
    final length = r.isFile ? r.displayName.length : r.value.length;
    return Row(
      children: [
        RedactionBar(width: (length * 7.0).clamp(40.0, 160.0), small: true),
        if (r.isFile) ...[
          AppSpacing.gapXs,
          AppText(formatBytes(r.size)).small.muted,
        ],
      ],
    );
  }

  /// One line of the value, masked while the record is hidden.
  String _preview(models.Record r) {
    if (r.isLocked) return 'Not readable on this device';
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

  /// Where a section comes from and who else reaches it, as rows at the top
  /// of its group: the tool that keeps it, the tools that read it, the
  /// service it was made for at sign-in, or who asked for it. Each opens the
  /// thing it names. Null for a section that is simply the person's own.
  List<Widget>? _sectionSource(BuildContext context, Section section) {
    final rows = <Widget>[];
    if (section.isSignIn) {
      rows.add(
        AppListRow(
          icon: AppIcons.globe,
          title: 'From signing in to ${section.requestedBy}',
          subtitle: 'Shared with this service at sign-in',
          onTap: () => _openSignInService(context, section),
        ),
      );
    } else if (section.isRequested) {
      rows.add(
        AppListRow(
          icon: AppIcons.inboxFill,
          title: 'Requested by ${section.requestedBy}',
          subtitle: 'Sent in response to the request',
          onTap: () => context.go(AppRoutes.requestsReceived),
        ),
      );
    }
    // The tool that manages it, and those that read it, each with what it may
    // do here; the row opens the tool's page.
    final manager = _managerOf(section);
    if (manager != null) {
      final email = memberEmail(manager.user);
      rows.add(
        AppListRow(
          icon: AppIcons.plug,
          title: 'Managed by ${manager.name}',
          subtitle: [
            _managerDoes(manager),
            'ID ${manager.shortId}',
            if (email != null) 'connected by $email',
          ].join(' · '),
          onTap: () => context.go(AppRoutes.connectedToolFor(manager.id)),
        ),
      );
    }
    for (final c in Stores.connections.connections) {
      if (c.section == section.id || !c.reaches(section.id)) continue;
      rows.add(
        AppListRow(
          icon: AppIcons.eye,
          title: 'Read by ${c.name}',
          subtitle: 'Reads its records, never changes them · ID ${c.shortId}',
          onTap: () => context.go(AppRoutes.connectedToolFor(c.id)),
        ),
      );
    }
    return rows.isEmpty ? null : rows;
  }

  /// Goes to the service this section's entries were made for, or to the list
  /// of services when its row is gone.
  Future<void> _openSignInService(BuildContext context, Section section) async {
    await Stores.signIns.loadIfDue();
    if (!context.mounted) return;
    for (final s in Stores.signIns.services) {
      if (Uri.tryParse(s.clientId)?.host == section.requestedBy) {
        context.go(AppRoutes.signInServiceFor(s.id));
        return;
      }
    }
    context.go(AppRoutes.settingsPage(SettingsPage.connectedTools.slug));
  }

  /// The tool that manages [section] as its own, if one does.
  static Connection? _managerOf(Section section) {
    for (final c in Stores.connections.connections) {
      if (c.section == section.id) return c;
    }
    return null;
  }

  /// What the managing tool does here, in a few words.
  static String _managerDoes(Connection c) => c.sectionOff
      ? 'Switched off for this section'
      : c.vaultAccess == 'read'
      ? 'Reads this section'
      : 'Adds records here and changes only its own';

  /// Where a section came from when it was not made by hand: a tool that
  /// manages it, a sign-in at a service, or a request answered. Null for one
  /// made by hand. The same icon stands in the pane and before its title.
  static _SectionOrigin? _originOf(Section section) {
    final manager = _managerOf(section);
    if (manager != null) {
      final name = manager.name.isEmpty ? manager.shortId : manager.name;
      return _SectionOrigin(
        icon: AppIcons.plug,
        label: 'Managed by $name${manager.sectionOff ? ' · off' : ''}',
        tooltip: '${_managerDoes(manager)} · ID ${manager.id}',
        muted: manager.sectionOff,
      );
    }
    if (section.isSignIn) {
      return _SectionOrigin(
        icon: AppIcons.globe,
        label: 'Sign-in · ${section.requestedBy}',
        tooltip: 'Shared with ${section.requestedBy} when signing in there',
      );
    }
    if (section.isRequested) {
      return _SectionOrigin(
        icon: AppIcons.inboxFill,
        label: 'Requested by ${section.requestedBy}',
        tooltip: 'Sent in response to a request',
      );
    }
    return null;
  }

  /// Opens what a section came from: the tool's page, the service signed in
  /// to, or the requests answered.
  void _openOrigin(BuildContext context, Section section) {
    final manager = _managerOf(section);
    if (manager != null) {
      context.go(AppRoutes.connectedToolFor(manager.id));
    } else if (section.isSignIn) {
      _openSignInService(context, section);
    } else if (section.isRequested) {
      context.go(AppRoutes.requestsReceived);
    }
  }

  /// Beside a section's title: where it came from, when not made by hand,
  /// and who sees it — so a tool's or a sign-in's section never reads like
  /// one made by hand.
  Widget _sectionBadges(BuildContext context, Section section) {
    final origin = _originOf(section);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (origin != null) ...[
          Flexible(
            child: _OriginBadge(
              origin,
              onTap: () => _openOrigin(context, section),
            ),
          ),
          AppSpacing.gapXs,
        ],
        AudienceTag(_sectionAudience(section)),
      ],
    );
  }

  /// A section another member shared: its records, read-only.
  /// A member's shared section in the single list; null while a search finds
  /// nothing in it.
  Widget? _sharedGroup(
    BuildContext context,
    Section section,
    Set<_VaultFilter> filters,
    String filterKey, {
    required bool searching,
  }) {
    final byId = {for (final r in Stores.vault.sharedRecords) r.id: r};
    final shown = [
      for (final id in section.records)
        if (byId[id] case final r?)
          if (_sharedMatches(r, filters) && _tableController.matchesQuery(r)) r,
    ];
    if (searching && shown.isEmpty) return null;
    return AppListGroup(
      key: ValueKey('shared-${section.id}-$filterKey'),
      title: _sectionName(section),
      badge: AudienceTag(_sectionAudience(section)),
      noun: 'records',
      previewCount: 5,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: AppBadge(
          icon: AppIcons.person,
          label: section.id == VaultStore.sharedEntriesId
              ? 'Published to the workspace'
              : 'Shared by ${section.ownerEmail ?? 'another member'}',
        ),
      ),
      children: [
        if (shown.isEmpty)
          const AppDetailRow(
            icon: AppIcons.info,
            label: 'No records in this section',
          )
        else
          for (final r in shown) _sharedRow(context, section, r),
      ],
    );
  }

  /// One record of a member's shared section; it opens read-only.
  Widget _sharedRow(BuildContext context, Section section, models.Record r) =>
      AppListRow(
        icon: RecordTypeUtils.icon(r.type),
        title: r.label.isEmpty ? r.key : r.label,
        subtitle: _preview(r),
        subtitleWidget: _hiddenPreview(r),
        audience: AudienceTag(
          Audience.combined([_sectionAudience(section), _recordAudience(r)]),
        ),
        trailing: r.sealed ? const _EncryptedMark() : null,
        onTap: () => _openSharedRecord(context, section, r),
        contextActions: () => [
          if (!r.isLocked)
            AppSheetAction(
              icon: AppIcons.copy,
              label: 'Copy value',
              onTap: () {
                Clipboard.setData(ClipboardData(text: r.value));
                AppToast.success(context, 'Copied to clipboard');
              },
            ),
          if (!r.isLocked &&
              !r.isFile &&
              Stores.vault.canEditShared(section, r))
            AppSheetAction(
              icon: AppIcons.pencil,
              label: 'Edit value',
              onTap: () => _editSharedRecord(context, r, closeAfterSave: false),
            ),
        ],
      );

  Future<void> _openSharedRecord(
    BuildContext context,
    Section section,
    models.Record r,
  ) => showAppSheet<void>(
    context: context,
    dismissible: true,
    builder: (sheetContext) => Observer(
      builder: (_) {
        final revealed = Stores.vault.isRevealed(r.id);
        return Padding(
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
              Row(
                children: [
                  Expanded(
                    child: Text(r.label.isEmpty ? r.key : r.label).header,
                  ),
                  AppSpacing.gapSm,
                  AudienceTag(
                    Audience.combined([
                      _sectionAudience(section),
                      _recordAudience(r),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                section.id == VaultStore.sharedEntriesId
                    ? 'Published by '
                          '${Stores.vault.sharedEntryOwners[r.id]?.isNotEmpty == true ? Stores.vault.sharedEntryOwners[r.id] : 'another member'}.'
                          '${Stores.vault.canEditShared(section, r) ? ' It can be changed here as well.' : ' Only members who may publish can change it.'}'
                    : 'Shared by ${section.ownerEmail ?? 'another member'} in '
                          '"${_sectionName(section)}".'
                          '${Stores.vault.canEditShared(section, r) ? ' It can be changed here as well.' : ' Only they can change it.'}',
              ).muted.small,
              const SizedBox(height: AppSpacing.lg),
              if (r.isLocked)
                const Text(
                  'Encrypted, and not readable on this device. Someone who '
                  'can invite members can give access under Settings → '
                  'End-to-end encryption.',
                )
              else
                AppText(
                  r.isHidden && !revealed ? '•' * 12 : r.value,
                ).mono.selectable,
              if (!r.isLocked) ...[
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    AppButton(
                      icon: AppIcons.copy,
                      label: 'Copy value',
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: r.value));
                        AppToast.success(sheetContext, 'Copied to clipboard');
                      },
                    ),
                    if (Stores.vault.canEditShared(section, r) &&
                        !r.isFile &&
                        !r.isLocked)
                      AppButton(
                        icon: AppIcons.pencil,
                        label: 'Edit value',
                        onTap: () => _editSharedRecord(sheetContext, r),
                      ),
                    if (r.isHidden)
                      AppButton(
                        icon: revealed ? AppIcons.eyeSlash : AppIcons.eye,
                        label: revealed ? 'Hide' : 'Show',
                        style: AppButtonStyle.accent,
                        onTap: () => Stores.vault.toggleRevealed(r.id),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    ),
  );

  /// Changes the value of a colleague's record, in a section they opened
  /// for editing (VISIBILITY.md). An encrypted one is written encrypted.
  Future<void> _editSharedRecord(
    BuildContext context,
    models.Record r, {
    bool closeAfterSave = true,
  }) async {
    final store = Stores.vault;
    store.sharedEditValue.text = r.value;
    final save = await showAppEditSheet(
      context: context,
      title: 'Edit ${r.label.isEmpty ? r.key : r.label}',
      controller: store.sharedEditValue,
    );
    if (!save || !context.mounted) return;
    final ok = await store.updateRecord(r.id, {
      'value': store.sharedEditValue.text,
    });
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'Value saved');
      if (closeAfterSave) Navigator.of(context).maybePop();
    } else {
      AppToast.error(
        context,
        'The value could not be saved',
        subtitle: store.errorMessage,
      );
    }
  }

  /// Who sees and who edits one of this person's sections (VISIBILITY.md).
  void _openVisibility(BuildContext context, Section section) =>
      openAccessSheet(
        context,
        area: AccessArea.sections,
        id: section.id,
        name: _sectionName(section),
        audienceKind: section.audienceKind,
        editing: section.editing,
        save: (kind, editing, groups) => Stores.vault.setSectionAudience(
          section.id,
          kind: kind,
          editing: editing,
          groups: groups,
        ),
        saveError: () => Stores.vault.errorMessage,
      );

  Widget _sectionMenu(BuildContext context, Section section, int shown) {
    final store = Stores.vault;
    final access = Stores.shares.linksForSection(section.id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Who sees it and where it came from are beside the title; tools
        // reading it are rows at the top of the section.
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
            if (section.isSignIn)
              AppMenuItem(
                icon: AppIcons.globe,
                label: 'Open service',
                onSelected: () => _openSignInService(context, section),
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
            if (!section.isRequested)
              AppMenuItem(
                icon: AppIcons.personWorkspace,
                label: 'Visibility',
                onSelected: () => _openVisibility(context, section),
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
              onSelected: () =>
                  openVaultCreateSheet(context, duplicateSection: section),
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
    if (selected && !await confirmToolsReach(context, section, record)) {
      return;
    }
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
        selected ? 'Record added to section' : 'Record removed from section',
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
    final ok = await Stores.shares.updateShare(share.id, {
      'records': newRecords,
    });
    if (!mounted) return;
    if (!ok) {
      AppToast.error(
        context,
        selected
            ? 'The record could not be added to the share.'
            : 'The record could not be removed from the share.',
        subtitle: Stores.shares.errorMessage,
      );
      return;
    }
    AppToast.success(
      context,
      selected ? 'Record added to the share' : 'Record removed from the share',
      subtitle: _addressNote(share),
    );
  }

  /// A link that just got its first encrypted record has a longer address
  /// from now on, which whoever already holds the old one has to be given.
  String? _addressNote(Link share) => Stores.shares.takeAddressChanged(share.id)
      ? 'The link now ends in a key. Copies handed out earlier do not open '
            'the encrypted records.'
      : null;

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
    final ok = await Stores.shares.updateShare(share.id, {
      'sections': newSections,
      'records': newRecords,
    });
    if (!mounted) return;
    if (!ok) {
      AppToast.error(
        context,
        'The share could not be changed.',
        subtitle: Stores.shares.errorMessage,
      );
      return;
    }
    final note = _addressNote(share);
    if (note != null) {
      AppToast.success(context, 'Section shared', subtitle: note);
    }
  }

  Future<void> _confirmDeleteSection(
    BuildContext context,
    VaultStore store,
    String id,
  ) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete section',
      message: 'The records in it stay in the vault. This cannot be undone.',
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
      AppToast.success(context, 'Section deleted');
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
            'show "$title".',
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
    final kind = link.request.isEmpty ? 'Shared by you' : 'From a request';
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

/// Only this person's devices can read the record, so it takes the place of a
/// link count: the mark identifies end-to-end encrypted records.
class _EncryptedMark extends StatelessWidget {
  const _EncryptedMark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'End-to-end encrypted',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.lock, size: 16),
          AppSpacing.gapXxs,
          const AppText('Encrypted').small,
        ],
      ),
    );
  }
}

/// How many links reach a record: the row's answer to "who can read this".
class _LinkCount extends StatelessWidget {
  final int count;

  const _LinkCount(this.count);

  @override
  Widget build(BuildContext context) {
    final label = '$count ${count == 1 ? 'link' : 'links'}';
    return Semantics(
      label: 'Shared through $label',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.link, size: 16),
          AppSpacing.gapXxs,
          AppText(label).small,
        ],
      ),
    );
  }
}

/// Where a section came from, for [_OriginBadge] and the icons in the pane
/// and before its title.
class _SectionOrigin {
  final IconData icon;
  final String label;
  final String tooltip;

  /// A tool switched off for the section: still named, less loudly.
  final bool muted;

  const _SectionOrigin({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.muted = false,
  });
}

/// "Managed by Claude Desktop" or "Sign-in · shop.example" beside a
/// section's title: what the section came from, by name, so it is told apart
/// from one made by hand at a glance. A tool's tooltip carries its ID, as two
/// tools may share a name. Opens what it names.
class _OriginBadge extends StatelessWidget {
  final _SectionOrigin origin;
  final VoidCallback onTap;

  const _OriginBadge(this.origin, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: origin.tooltip,
      child: Semantics(
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.allMd,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: AppBadge(
                icon: origin.icon,
                label: origin.label,
                variant: origin.muted
                    ? AppBadgeVariant.outline
                    : AppBadgeVariant.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A section is a destination, visually distinct from an individual item.
class _VaultSectionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Audience audience;
  final bool selected;
  final VoidCallback onTap;

  const _VaultSectionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.audience,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.allMd,
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: AppRadius.allMd,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Icon(
                          icon,
                          size: 22,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (!audience.isPrivate)
                      AudienceTag(audience, compact: true),
                    AppSpacing.gapSm,
                    Icon(
                      selected ? AppIcons.checkCircle : AppIcons.arrowRight,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                AppSpacing.gapLg,
                AppText(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ).bold,
                AppSpacing.gapXxs,
                AppText(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ).small.muted,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
