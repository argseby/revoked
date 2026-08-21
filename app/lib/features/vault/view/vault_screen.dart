import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_entity_card.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_screen_header.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/data_table/filter_bar.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:revoked_app/features/vault/utils/record_type_utils.dart';
import 'package:revoked_app/features/vault/view/record_create_sheet.dart';
import 'package:revoked_app/features/vault/view/section_create_sheet.dart';

class VaultScreen extends StatefulWidget {
  final String? editingShareId;
  final String? shareFilterId;

  const VaultScreen({super.key, this.editingShareId, this.shareFilterId});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  late TableStore<models.Record> _tableController;

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
      if (mounted) ShellSlots.setFilter(_filterButton);
      store.loadRecords();
      if (widget.editingShareId != null || widget.shareFilterId != null) {
        Stores.shares.loadShares();
      }
    });
  }

  @override
  void dispose() {
    ShellSlots.clearFilter(_filterButton);
    _tableController.dispose();
    super.dispose();
  }

  Widget _filterButton(BuildContext context) {
    return FilterButton<models.Record>(
      controller: _tableController,
      columns: const [
        DataTableColumn(value: 'label', label: 'Label'),
        DataTableColumn(value: 'key', label: 'Key'),
        DataTableColumn(value: 'value', label: 'Value'),
        DataTableColumn(value: 'type', label: 'Type'),
        DataTableColumn(value: 'format', label: 'Format'),
      ],
      helper: Row(
        children: [
          Icon(
            AppIcons.info,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: const Text(
              'Filters on Value, Type, or Format only apply to Records, while Label and Key apply to both.',
            ).muted.small,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.vault;
    final authStore = Stores.auth;

    final outerPad = AppSpacing.screenH(context);
    final scrollbarMargin = AppSpacing.scrollbarMargin(context);
    final innerPad = outerPad - scrollbarMargin;
    final horizontalPad = EdgeInsets.symmetric(horizontal: outerPad);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: horizontalPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.md),
              Observer(
                builder: (_) {
                  final count = store.recordCount;
                  final Widget? primaryAction;
                  if (store.editingSectionId != null) {
                    primaryAction = AppButton(
                      label: 'Done',
                      onTap: () => store.editSection(null),
                    );
                  } else if (widget.editingShareId != null ||
                      widget.shareFilterId != null) {
                    primaryAction = AppButton(
                      label: 'Done',
                      onTap: () => context.go(AppRoutes.shares),
                    );
                  } else {
                    // Creation lives on the shell's floating button now.
                    primaryAction = null;
                  }
                  return AppScreenHeader(
                    title: 'Vault',
                    badgeLabel: '$count ${count == 1 ? 'record' : 'records'}',
                    actions: [?primaryAction],
                  );
                },
              ),
            ],
          ),
        ),

        Expanded(
          child: Observer(
            builder: (_) {
              if (store.isLoading &&
                  store.records.isEmpty &&
                  store.sections.isEmpty) {
                return const Center(child: AppSpinner(large: true));
              }

              if (store.errorMessage != null) {
                return Padding(
                  padding: horizontalPad,
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

              if (store.editingSectionId != null) {
                // Render standard Record selection mode!
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: scrollbarMargin),
                  child: ListView(
                    padding: EdgeInsets.only(
                      left: innerPad,
                      right: innerPad,
                      bottom: 120,
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: AppRadius.allMd,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              AppIcons.plusSlashMinus,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Editing section: ${store.sections.firstWhere((s) => s.id == store.editingSectionId).name}. Select entries below to include them in this section.',
                              ).small,
                            ),
                          ],
                        ),
                      ),
                      if (store.records.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xxl),
                          child: Center(
                            child: const Text('No records created yet.').muted,
                          ),
                        )
                      else if (_tableController.filteredItems.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xxl),
                          child: Center(
                            child: const Text(
                              'No records match your filters.',
                            ).muted,
                          ),
                        )
                      else
                        ..._tableController.filteredItems.map((record) {
                          Section? editingSection = store.sections.firstWhere(
                            (s) => s.id == store.editingSectionId,
                          );

                          return _RecordCard(
                            record: record,
                            isSelectableMode: true,
                            isSelected: editingSection.records.contains(
                              record.id,
                            ),
                            onToggleSelect: (bool selected) async {
                              final newRecords = List<String>.from(
                                editingSection.records,
                              );
                              if (selected && !newRecords.contains(record.id)) {
                                newRecords.add(record.id);
                              } else if (!selected) {
                                newRecords.remove(record.id);
                              }
                              final ok = await store.updateSection(
                                editingSection.id,
                                {'records': newRecords},
                              );
                              if (ok && context.mounted) {
                                AppToast.success(
                                  context,
                                  selected
                                      ? 'Added record to section'
                                      : 'Removed record from section',
                                );
                              }
                            },
                            onCopy: () {
                              Clipboard.setData(
                                ClipboardData(text: record.value),
                              );
                              AppToast.success(context, 'Copied to clipboard');
                            },
                            onEdit: () {},
                            onDelete: () =>
                                _confirmDeleteRecord(context, store, record.id),
                            onDuplicate: () => _showCreateSheet(
                              context,
                              store,
                              authStore,
                              initialRecord: record,
                            ),
                          );
                        }),
                    ],
                  ),
                );
              }

              // Render beautiful unified view!
              final rawFilteredRecords = _tableController.filteredItems;

              final sharesStore = Stores.shares;
              Link? activeShareFilter;
              if (widget.shareFilterId != null &&
                  sharesStore.shares.isNotEmpty) {
                try {
                  activeShareFilter = sharesStore.shares.firstWhere(
                    (s) => s.id == widget.shareFilterId,
                  );
                } catch (_) {}
              }

              Link? activeShareEdit;
              if (widget.editingShareId != null &&
                  sharesStore.shares.isNotEmpty) {
                try {
                  activeShareEdit = sharesStore.shares.firstWhere(
                    (s) => s.id == widget.editingShareId,
                  );
                } catch (_) {}
              }

              // Let's filter records and sections if shareFilterId is active!
              List<models.Record> filteredRecords = rawFilteredRecords;
              List<Section> sectionsSource = store.sections.toList();

              if (activeShareFilter != null) {
                final allowedSectionIds = activeShareFilter.sections.toSet();
                final allowedRecordIdsFromSections = store.sections
                    .where((s) => allowedSectionIds.contains(s.id))
                    .expand((s) => s.records)
                    .toSet();
                final allowedRecordIds = activeShareFilter.records
                    .toSet()
                    .union(allowedRecordIdsFromSections);

                filteredRecords = rawFilteredRecords
                    .where((r) => allowedRecordIds.contains(r.id))
                    .toList();
                sectionsSource = store.sections
                    .where((s) => allowedSectionIds.contains(s.id))
                    .toList();
              }

              // Find which sections are visible
              final searchQuery = _tableController.searchQuery.toLowerCase();
              final visibleSections = sectionsSource.where((section) {
                // Get records in this section that also match the filters
                final sectionRecords = section.records
                    .map((id) {
                      try {
                        return filteredRecords.firstWhere((r) => r.id == id);
                      } catch (_) {
                        return null;
                      }
                    })
                    .whereType<models.Record>()
                    .toList();

                final matchesSearch =
                    section.name.toLowerCase().contains(searchQuery) ||
                    section.key.toLowerCase().contains(searchQuery);
                final matchesFilters = _sectionMatchesFilters(
                  section,
                  _tableController.filters,
                );
                return (matchesSearch && matchesFilters) ||
                    sectionRecords.isNotEmpty;
              }).toList();

              // Sort sections if active sort applies to them
              final sortBy = _tableController.sortBy;
              if (sortBy.isNotEmpty) {
                final parts = sortBy.split('_');
                if (parts.length >= 2) {
                  final col = parts.sublist(0, parts.length - 1).join('_');
                  final dir = parts.last;

                  if (col == 'label' || col == 'key' || col == 'created') {
                    visibleSections.sort((a, b) {
                      String valA = '';
                      String valB = '';
                      if (col == 'label') {
                        valA = a.name;
                        valB = b.name;
                      } else if (col == 'key') {
                        valA = a.key;
                        valB = b.key;
                      } else if (col == 'created') {
                        valA = a.created ?? '';
                        valB = b.created ?? '';
                      }

                      final comp = valA.toLowerCase().compareTo(
                        valB.toLowerCase(),
                      );
                      return dir == 'asc' ? comp : -comp;
                    });
                  }
                }
              }

              final assignedRecordIds = store.sections
                  .expand((s) => s.records)
                  .toSet();
              final ungroupedRecords = filteredRecords
                  .where((r) => !assignedRecordIds.contains(r.id))
                  .toList();

              // If absolutely nothing matches the filter anywhere in the sections or ungrouped lists, show search empty state
              final hasAnyMatching =
                  visibleSections.isNotEmpty || ungroupedRecords.isNotEmpty;

              if (!hasAnyMatching) {
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxl),
                  child: Center(
                    child: const Text('No items match your filters.').muted,
                  ),
                );
              }

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: scrollbarMargin),
                child: ListView(
                  padding: EdgeInsets.only(
                    left: innerPad,
                    right: innerPad,
                    bottom: 120,
                  ),
                  children: [
                    if (activeShareFilter != null)
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: AppRadius.allMd,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              AppIcons.funnel,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Filtering by public share: "${activeShareFilter.label}". Only items shared are displayed.',
                              ).small,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            AppButton(
                              label: 'Clear',
                              onTap: () => context.go(AppRoutes.vault),
                              style: AppButtonStyle.accent,
                            ),
                          ],
                        ),
                      ),
                    if (activeShareEdit != null)
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: AppRadius.allMd,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              AppIcons.plusSlashMinus,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Editing public share: "${activeShareEdit.label}". Select sections and records below to include them in this public share.',
                              ).small,
                            ),
                          ],
                        ),
                      ),
                    ...visibleSections.map((section) {
                      final sectionRecords = section.records
                          .map((id) {
                            try {
                              return filteredRecords.firstWhere(
                                (r) => r.id == id,
                              );
                            } catch (_) {
                              return null;
                            }
                          })
                          .whereType<models.Record>()
                          .toList();

                      return _SectionCard(
                        section: section,
                        sectionRecords: sectionRecords,
                        onAddRecords: () => store.editSection(section.id),
                        onRename: () => openSectionRenameSheet(
                          context: context,
                          store: store,
                          section: section,
                        ),
                        onDelete: () =>
                            _confirmDeleteSection(context, store, section.id),
                        onDuplicate: () => openSectionCreateSheet(
                          context: context,
                          store: store,
                          authStore: authStore,
                          initialSection: section,
                        ),
                        isSelectableMode: activeShareEdit != null,
                        isSelected:
                            activeShareEdit != null &&
                            activeShareEdit.sections.contains(section.id),
                        onToggleSelect: activeShareEdit == null
                            ? null
                            : (selected) async {
                                final share = activeShareEdit;
                                if (share == null) return;
                                final newSections = List<String>.from(
                                  share.sections,
                                );
                                final newRecords = List<String>.from(
                                  share.records,
                                );
                                if (selected) {
                                  if (!newSections.contains(section.id)) {
                                    newSections.add(section.id);
                                  }
                                  for (final rId in section.records) {
                                    if (!newRecords.contains(rId)) {
                                      newRecords.add(rId);
                                    }
                                  }
                                } else {
                                  newSections.remove(section.id);
                                  for (final rId in section.records) {
                                    newRecords.remove(rId);
                                  }
                                }
                                await sharesStore.updateShare(share.id, {
                                  'sections': newSections,
                                  'records': newRecords,
                                });
                                if (context.mounted) {
                                  AppToast.success(
                                    context,
                                    selected
                                        ? 'Added section to public share'
                                        : 'Removed section from public share',
                                  );
                                }
                              },
                        recordCardBuilder: (record) {
                          return _RecordCard(
                            record: record,
                            isSelectableMode: activeShareEdit != null,
                            isSelected:
                                activeShareEdit != null &&
                                activeShareEdit.records.contains(record.id),
                            onToggleSelect: activeShareEdit == null
                                ? null
                                : (selected) async {
                                    final share = activeShareEdit;
                                    if (share == null) return;
                                    final newRecords = List<String>.from(
                                      share.records,
                                    );
                                    if (selected) {
                                      if (!newRecords.contains(record.id)) {
                                        newRecords.add(record.id);
                                      }
                                    } else {
                                      newRecords.remove(record.id);
                                    }
                                    await sharesStore.updateShare(share.id, {
                                      'records': newRecords,
                                    });
                                    if (context.mounted) {
                                      AppToast.success(
                                        context,
                                        selected
                                            ? 'Added record to public share'
                                            : 'Removed record from public share',
                                      );
                                    }
                                  },
                            onCopy: () {
                              Clipboard.setData(
                                ClipboardData(text: record.value),
                              );
                              AppToast.success(context, 'Copied to clipboard');
                            },
                            onEdit: () =>
                                _showEditRecordSheet(context, store, record),
                            onDelete: () =>
                                _confirmDeleteRecord(context, store, record.id),
                            onDuplicate: () => _showCreateSheet(
                              context,
                              store,
                              authStore,
                              initialRecord: record,
                            ),
                          );
                        },
                      );
                    }),

                    if (ungroupedRecords.isNotEmpty) ...[
                      if (visibleSections.isNotEmpty)
                        const SizedBox(height: AppSpacing.xxl),
                      Row(
                        children: [
                          Icon(
                            AppIcons.folder,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          const Text('Ungrouped Records').muted,
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ...ungroupedRecords.map((record) {
                        return _RecordCard(
                          record: record,
                          isSelectableMode: activeShareEdit != null,
                          isSelected:
                              activeShareEdit != null &&
                              activeShareEdit.records.contains(record.id),
                          onToggleSelect: activeShareEdit == null
                              ? null
                              : (selected) async {
                                  final share = activeShareEdit;
                                  if (share == null) return;
                                  final newRecords = List<String>.from(
                                    share.records,
                                  );
                                  if (selected) {
                                    if (!newRecords.contains(record.id)) {
                                      newRecords.add(record.id);
                                    }
                                  } else {
                                    newRecords.remove(record.id);
                                  }
                                  await sharesStore.updateShare(share.id, {
                                    'records': newRecords,
                                  });
                                  if (context.mounted) {
                                    AppToast.success(
                                      context,
                                      selected
                                          ? 'Added record to public share'
                                          : 'Removed record from public share',
                                    );
                                  }
                                },
                          onCopy: () {
                            Clipboard.setData(
                              ClipboardData(text: record.value),
                            );
                            AppToast.success(context, 'Copied to clipboard');
                          },
                          onEdit: () =>
                              _showEditRecordSheet(context, store, record),
                          onDelete: () =>
                              _confirmDeleteRecord(context, store, record.id),
                          onDuplicate: () => _showCreateSheet(
                            context,
                            store,
                            authStore,
                            initialRecord: record,
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(
    BuildContext context,
    String text, {
    bool isRequired = false,
    String? explanation,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text),
            if (isRequired)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xxs),
                child: const AppErrorText('*'),
              ),
          ],
        ),
        if (explanation != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(explanation).muted.small,
        ],
      ],
    );
  }

  // Record-create / duplicate moved to a 2-step bottom sheet
  // (record_create_sheet.dart) so the form no longer overflows on phones.
  void _showCreateSheet(
    BuildContext context,
    VaultStore store,
    AuthStore authStore, {
    models.Record? initialRecord,
  }) {
    openRecordCreateSheet(
      context: context,
      store: store,
      authStore: authStore,
      initialRecord: initialRecord,
    );
  }

  bool _sectionMatchesFilters(Section section, List<DataTableFilter> filters) {
    for (final f in filters) {
      if (f.value.isEmpty) continue;
      String? val;
      if (f.column == 'label') {
        val = section.name;
      } else if (f.column == 'key') {
        val = section.key;
      } else if (f.column == 'created') {
        val = section.created ?? '';
      }

      if (val != null) {
        final target = f.value.toLowerCase();
        final source = val.toLowerCase();
        bool match = true;
        switch (f.operator) {
          case 'equals':
            match = source == target;
            break;
          case 'contains':
            match = source.contains(target);
            break;
          case 'starts_with':
            match = source.startsWith(target);
            break;
          case 'ends_with':
            match = source.endsWith(target);
            break;
        }
        if (!match) return false;
      }
    }
    return true;
  }

  void _showEditRecordSheet(
    BuildContext context,
    VaultStore store,
    models.Record record,
  ) {
    store.clearError();
    store.startRecordEdit(record);

    showAppSheet(
      context: context,
      builder: (sheetContext) {
        return Builder(
          builder: (ctx) {
            void validateAndDetectType(String value) {
              final detected = RecordTypeUtils.detectType(value);
              store.setEditRecordTypeCheck(
                warning: RecordTypeUtils.validateValue(
                  store.editRecordType,
                  value,
                ),
                detected: detected != 'text' && detected != store.editRecordType
                    ? detected
                    : null,
              );
            }

            final isFile = record.isFile;

            return Observer(
              builder: (observerContext) {
                final _ = store.errorMessage;
                final theme = Theme.of(ctx);

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
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Edit record').header,
                                const SizedBox(height: AppSpacing.xxs),
                                const Text(
                                  'Modify record parameters in your workspace.',
                                ).muted.small,
                              ],
                            ),
                          ),
                          AppButton(
                            icon: AppIcons.x,
                            tooltip: 'Close',
                            style: AppButtonStyle.accent,
                            onTap: store.isSubmittingEditRecord
                                ? null
                                : () => Navigator.of(sheetContext).pop(),
                          ),
                        ],
                      ),
                    ),
                    const AppDivider(),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.xxl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildFieldLabel(
                              ctx,
                              'Label',
                              isRequired: true,
                              explanation:
                                  'A friendly display name for this record.',
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            AppTextField(
                              controller: store.editRecordLabel,
                              hint: 'My Secret',
                            ),
                            const SizedBox(height: AppSpacing.lg),

                            _buildFieldLabel(
                              ctx,
                              'Key',
                              isRequired: true,
                              explanation:
                                  'A stable identifier for sharing and templates.',
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: AppRadius.allMd,
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              child: Text(record.key).mono.muted.small,
                            ),
                            const SizedBox(height: AppSpacing.lg),

                            if (isFile) ...[
                              _buildFieldLabel(
                                ctx,
                                'File name',
                                isRequired: true,
                                explanation:
                                    'What a recipient downloads this file as. '
                                    'Renaming never touches the file itself.',
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              AppTextField(
                                controller: store.editRecordFilename,
                                hint: 'Lebenslauf.pdf',
                              ),
                              const SizedBox(height: AppSpacing.lg),

                              _buildFieldLabel(
                                ctx,
                                'File',
                                explanation:
                                    'Replacing it updates every active share '
                                    'on its next read.',
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      store.editPickedFileName ??
                                          '${record.displayName} · ${formatBytes(record.size)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ).mono.muted.small,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  AppButton(
                                    icon: AppIcons.arrowRepeat,
                                    label: 'Replace',
                                    size: AppButtonSize.small,
                                    style: AppButtonStyle.accent,
                                    onTap: () async {
                                      final picked =
                                          await FilePicker.pickFile();
                                      if (picked == null) return;
                                      final bytes = await picked.readAsBytes();
                                      store.setEditPickedFile(
                                        picked.name,
                                        bytes,
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.lg),
                            ] else ...[
                              _buildFieldLabel(
                                ctx,
                                'Value',
                                isRequired: true,
                                explanation:
                                    'The actual sensitive data or configuration value.',
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              AppTextField(
                                controller: store.editRecordValue,
                                hint: 'sk-1234...',
                                onChanged: (v) => validateAndDetectType(v),
                              ),
                              if (store.editRecordTypeWarning != null) ...[
                                const SizedBox(height: AppSpacing.xs),
                                AppErrorText(store.editRecordTypeWarning!),
                              ],
                              const SizedBox(height: AppSpacing.lg),
                            ],

                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: isFile
                                        ? [
                                            _buildFieldLabel(
                                              ctx,
                                              'Type',
                                              explanation:
                                                  'A file record stays a file. '
                                                  'To store something else, '
                                                  'make a new record.',
                                            ),
                                            const SizedBox(
                                              height: AppSpacing.xs,
                                            ),
                                            const Align(
                                              alignment: Alignment.centerLeft,
                                              child: AppBadge(label: 'FILE'),
                                            ),
                                          ]
                                        : [
                                            _buildFieldLabel(
                                              ctx,
                                              'Type',
                                              explanation:
                                                  'How this data should be interpreted.',
                                            ),
                                            const SizedBox(
                                              height: AppSpacing.xs,
                                            ),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                if (store
                                                        .editRecordDetectedType !=
                                                    null)
                                                  AppButton(
                                                    icon: AppIcons.stars,
                                                    label:
                                                        'Auto: ${store.editRecordDetectedType!.toUpperCase()}',
                                                    size: AppButtonSize.small,
                                                    onTap: () {
                                                      store.setEditRecordType(
                                                        store
                                                            .editRecordDetectedType!,
                                                      );
                                                      validateAndDetectType(
                                                        store
                                                            .editRecordValue
                                                            .text,
                                                      );
                                                    },
                                                  ),
                                                ...RecordTypeUtils.supportedTypes.map((
                                                  type,
                                                ) {
                                                  final isSelected =
                                                      store.editRecordType ==
                                                      type;
                                                  return isSelected
                                                      ? AppButton(
                                                          label: type
                                                              .toUpperCase(),
                                                          onTap: () {},
                                                        )
                                                      : AppButton(
                                                          label: type
                                                              .toUpperCase(),
                                                          onTap: () {
                                                            store
                                                                .setEditRecordType(
                                                                  type,
                                                                );
                                                            validateAndDetectType(
                                                              store
                                                                  .editRecordValue
                                                                  .text,
                                                            );
                                                          },
                                                          style: AppButtonStyle
                                                              .accent,
                                                        );
                                                }),
                                              ],
                                            ),
                                          ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildFieldLabel(
                                        ctx,
                                        isFile ? 'Hidden name' : 'Hidden Value',
                                        explanation: isFile
                                            ? 'Mask the file name on screen — '
                                                  'a name is content too.'
                                            : 'Mask value on screen.',
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      AppButton(
                                        icon: store.editRecordFormat == 'hidden'
                                            ? AppIcons.eyeSlash
                                            : AppIcons.eye,
                                        label:
                                            store.editRecordFormat == 'hidden'
                                            ? 'Hidden'
                                            : 'Visible',
                                        style: AppButtonStyle.accent,
                                        onTap: () => store.setEditRecordFormat(
                                          store.editRecordFormat == 'hidden'
                                              ? 'default'
                                              : 'hidden',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xl),

                            if (store.errorMessage != null) ...[
                              AppAlert(
                                destructive: true,
                                leading: const Icon(AppIcons.exclamation),
                                title: const Text('Error'),
                                content: Text(store.errorMessage!),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                            ],

                            if (isFile)
                              const Text(
                                'Renaming is a normal record update; replacing '
                                'the file sends the same fields as '
                                'multipart/form-data with a "file" part.',
                              ).muted.small
                            else
                              ApiPreview(
                                spec: VaultStore.updateRecordSpec(record.id, {
                                  'value': store.editRecordValue.text.trim(),
                                  'label': store.editRecordLabel.text.trim(),
                                  'type': store.editRecordType,
                                  'format': store.editRecordFormat,
                                }),
                                title: 'API request · update',
                              ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                        ),
                      ),
                    ),
                    const AppDivider(),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AppButton(
                            label: 'Cancel',
                            onTap: store.isSubmittingEditRecord
                                ? null
                                : () => Navigator.of(sheetContext).pop(),
                            style: AppButtonStyle.accent,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          AppButton(
                            label: 'Save Changes',
                            busy: store.isSubmittingEditRecord,
                            onTap:
                                (store.editRecordLabel.text.trim().isEmpty ||
                                    (isFile
                                        ? store.editRecordFilename.text
                                              .trim()
                                              .isEmpty
                                        : store.editRecordValue.text
                                                  .trim()
                                                  .isEmpty ||
                                              store.editRecordTypeWarning !=
                                                  null))
                                ? null
                                : () async {
                                    store.setSubmittingEditRecord(true);

                                    final bool ok;
                                    if (isFile) {
                                      final fields = {
                                        'filename': store
                                            .editRecordFilename
                                            .text
                                            .trim(),
                                        'label': store.editRecordLabel.text
                                            .trim(),
                                        'format': store.editRecordFormat,
                                      };
                                      final bytes = store.editPickedFileBytes;
                                      // One write: a rename and a replacement
                                      // must not be able to half-apply.
                                      ok = bytes == null
                                          ? await store.updateRecord(
                                              record.id,
                                              fields,
                                            )
                                          : await store.updateRecordFile(
                                              record.id,
                                              store.editPickedFileName!,
                                              bytes,
                                              fields: fields,
                                            );
                                    } else {
                                      ok = await store.updateRecord(record.id, {
                                        'value': store.editRecordValue.text
                                            .trim(),
                                        'label': store.editRecordLabel.text
                                            .trim(),
                                        'type': store.editRecordType,
                                        'format': store.editRecordFormat,
                                      });
                                    }

                                    if (ok && ctx.mounted) {
                                      Navigator.of(sheetContext).pop();
                                      AppToast.success(
                                        context,
                                        'Record updated successfully',
                                      );
                                    } else {
                                      store.setSubmittingEditRecord(false);
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteRecord(
    BuildContext context,
    VaultStore store,
    String id,
  ) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete record',
      message:
          'This action cannot be undone. This will permanently delete the record.',
      content: ApiPreview(
        spec: VaultStore.deleteRecordSpec(id),
        title: 'API request · delete',
      ),
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await store.deleteRecord(id);
    if (ok && context.mounted) {
      AppToast.success(context, 'Record deleted successfully');
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

/// A tappable "N shares" pill that opens the who-has-access sheet.
class _AccessTag extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _AccessTag({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.allPill,
      onTap: onTap,
      child: AppBadge(
        icon: AppIcons.share,
        label: '$count ${count == 1 ? 'share' : 'shares'}',
        accent: Theme.of(context).colorScheme.primary,
      ),
    );
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
                context.go('${AppRoutes.shares}?filterSlug=${l.slug}');
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

class _SectionCard extends StatelessWidget {
  final Section section;
  final List<models.Record> sectionRecords;
  final VoidCallback onAddRecords;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final bool isSelectableMode;
  final bool isSelected;
  final ValueChanged<bool>? onToggleSelect;
  final Widget Function(models.Record) recordCardBuilder;

  const _SectionCard({
    required this.section,
    required this.sectionRecords,
    required this.onAddRecords,
    required this.onRename,
    required this.onDelete,
    required this.onDuplicate,
    required this.recordCardBuilder,
    this.isSelectableMode = false,
    this.isSelected = false,
    this.onToggleSelect,
  });

  List<AppSheetAction> _sectionActions() => [
    AppSheetAction(
      icon: AppIcons.plusSlashMinus,
      label: 'Add or remove records',
      primary: true,
      onTap: onAddRecords,
    ),
    AppSheetAction(icon: AppIcons.pen, label: 'Rename', onTap: onRename),
    AppSheetAction(
      icon: AppIcons.nodePlus,
      label: 'Duplicate',
      onTap: onDuplicate,
    ),
    AppSheetAction(
      icon: AppIcons.trash,
      label: 'Delete',
      destructive: true,
      onTap: onDelete,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tags = <Widget>[
      AppBadge(
        icon: AppIcons.cardList,
        label: '${section.records.length} records',
      ),
      if (section.isRequested)
        AppBadge(
          icon: AppIcons.inboxFill,
          label: 'Requested by ${section.requestedBy}',
        ),
    ];

    final accessLinks = Stores.shares.linksForSection(section.id);
    if (accessLinks.isNotEmpty) {
      tags.add(
        _AccessTag(
          count: accessLinks.length,
          onTap: () => _showVaultAccessSheet(
            context,
            title: section.name.isEmpty ? section.key : section.name,
            links: accessLinks,
          ),
        ),
      );
    }

    return AppEntityCard(
      icon: AppIcons.folder,
      onTap: isSelectableMode ? () => onToggleSelect?.call(!isSelected) : null,
      leading: isSelectableMode
          ? AppCheckbox(
              value: isSelected,
              onChanged: (value) => onToggleSelect?.call(value ?? false),
            )
          : null,
      title: section.name,
      subtitle: section.key,
      subtitleMono: true,
      date: AppEntityCard.formatDate(section.created),
      tags: tags,
      expandedBody: sectionRecords.isEmpty
          ? const Text('No records in this section yet.').muted.small
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final record in sectionRecords) recordCardBuilder(record),
              ],
            ),
      actions: isSelectableMode ? const [] : _sectionActions(),
    );
  }
}

class _RecordCard extends StatefulWidget {
  final dynamic record;
  final bool isSelectableMode;
  final bool isSelected;
  final ValueChanged<bool>? onToggleSelect;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;

  const _RecordCard({
    required this.record,
    this.isSelectableMode = false,
    this.isSelected = false,
    this.onToggleSelect,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
  });

  @override
  State<_RecordCard> createState() => _RecordCardState();
}

class _RecordCardState extends State<_RecordCard> {
  /// Hidden records start masked; the store remembers the ones the user chose
  /// to reveal, so the card itself holds nothing.
  bool get _isObscured =>
      widget.record.isHidden && !Stores.vault.isRevealed(widget.record.id);

  Future<void> _downloadFile() async {
    final r = widget.record;
    final bytes = await Stores.vault.fetchRecordFileBytes(r);
    if (bytes == null) {
      if (mounted) {
        AppToast.error(
          context,
          'Could not download file',
          subtitle: Stores.vault.errorMessage,
        );
      }
      return;
    }
    final ok = await saveFileToDevice(
      bytes: bytes,
      filename: r.displayName,
      mime: r.mime,
    );
    if (ok && mounted) AppToast.success(context, 'File saved');
  }

  List<AppSheetAction> _recordActions() {
    if (widget.record.isFile) {
      return [
        AppSheetAction(
          icon: AppIcons.download,
          label: 'Download',
          primary: true,
          onTap: _downloadFile,
        ),
        AppSheetAction(icon: AppIcons.pen, label: 'Edit', onTap: widget.onEdit),
        AppSheetAction(
          icon: AppIcons.trash,
          label: 'Delete',
          destructive: true,
          onTap: widget.onDelete,
        ),
      ];
    }
    return [
      AppSheetAction(
        icon: AppIcons.copy,
        label: 'Copy value',
        primary: true,
        onTap: widget.onCopy,
      ),
      AppSheetAction(icon: AppIcons.pen, label: 'Edit', onTap: widget.onEdit),
      AppSheetAction(
        icon: AppIcons.nodePlus,
        label: 'Duplicate',
        onTap: widget.onDuplicate,
      ),
      AppSheetAction(
        icon: AppIcons.trash,
        label: 'Delete',
        destructive: true,
        onTap: widget.onDelete,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSelectableMode) return _buildSelectable(context);

    final r = widget.record;
    final tags = <Widget>[AppBadge(label: r.type)];
    if (r.isFile) {
      tags.add(AppBadge(label: formatBytes(r.size)));
      final mime = ((r.mime ?? '') as String).split(';').first;
      if (mime.isNotEmpty) tags.add(AppBadge(label: mime));
    }
    if (r.isHidden) {
      tags.add(const AppBadge(icon: AppIcons.eyeSlash, label: 'Hidden'));
    }
    if (r.isAlias) {
      tags.add(const AppBadge(icon: AppIcons.link, label: 'Alias'));
    }
    if (r.isRequested) {
      tags.add(
        AppBadge(
          icon: AppIcons.inboxFill,
          label: 'Requested by ${r.requestedBy}',
        ),
      );
    }

    final accessLinks = Stores.shares.linksForRecord(r.id);
    if (accessLinks.isNotEmpty) {
      tags.add(
        _AccessTag(
          count: accessLinks.length,
          onTap: () => _showVaultAccessSheet(
            context,
            title: r.label.isEmpty ? r.key : r.label,
            links: accessLinks,
          ),
        ),
      );
    }

    return AppEntityCard(
      icon: AppIcons.key,
      title: r.label,
      subtitle: r.key,
      subtitleMono: true,
      date: AppEntityCard.formatDate(r.created),
      body: _valueBox(context),
      tags: tags,
      actions: _recordActions(),
    );
  }

  /// Resolves an alias record to its parent (value carrier) within the loaded
  /// vault, so the value box shows the forwarded value instead of nothing.
  models.Record? _aliasParent(BuildContext context) {
    final id = widget.record.aliasOf as String?;
    if (id == null || id.isEmpty) return null;
    for (final p in Stores.vault.records) {
      if (p.id == id) return p;
    }
    return null;
  }

  Widget _valueBox(BuildContext context) {
    return Observer(builder: (_) => _valueBoxBody(context));
  }

  Widget _valueBoxBody(BuildContext context) {
    final r = widget.record;
    if (r.isFile) {
      return _valueLine(
        context,
        text: _isObscured ? '••••••••••••' : r.displayName as String,
        leadingIcon: AppIcons.fileText,
      );
    }
    // Aliases carry no value of their own — show the parent's (forwarded) value.
    final value = r.isAlias
        ? (_aliasParent(context)?.value ?? '')
        : r.value as String;
    return _valueLine(
      context,
      text: _isObscured ? '••••••••••••••••' : (value.isEmpty ? '—' : value),
    );
  }

  /// One text line tall. A hidden record's box is itself the reveal control —
  /// tapping toggles the mask — so no button inflates its height.
  Widget _valueLine(
    BuildContext context, {
    required String text,
    IconData? leadingIcon,
  }) {
    final theme = Theme.of(context);
    final r = widget.record;
    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.allSm,
      ),
      child: Row(
        children: [
          if (leadingIcon != null) ...[
            Icon(
              leadingIcon,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ).mono.muted.small,
          ),
          if (r.isHidden) ...[
            const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: _isObscured ? 'Show' : 'Hide',
              child: Icon(
                _isObscured ? AppIcons.eye : AppIcons.eyeSlash,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
    if (!r.isHidden) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.allSm,
        onTap: () => Stores.vault.toggleRevealed(r.id),
        child: box,
      ),
    );
  }

  Widget _buildSelectable(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: () => widget.onToggleSelect?.call(!widget.isSelected),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCheckbox(
              value: widget.isSelected,
              onChanged: (value) => widget.onToggleSelect?.call(value ?? false),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.record.label),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(widget.record.key).mono.muted.small,
                ],
              ),
            ),
            AppBadge(label: widget.record.type),
            if (widget.record.isHidden) ...[
              const SizedBox(width: AppSpacing.xs),
              const AppBadge(label: 'hidden', variant: AppBadgeVariant.outline),
            ],
            if (widget.record.isAlias) ...[
              const SizedBox(width: AppSpacing.xs),
              const AppBadge(label: 'alias', variant: AppBadgeVariant.outline),
            ],
          ],
        ),
      ),
    );
  }
}

/// The tinted square behind each choice in the "Create New" sheet.
