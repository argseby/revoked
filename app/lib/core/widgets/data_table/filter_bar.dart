import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_select.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';

/// Compact filter trigger: a single icon button that shows a badge with the
/// active-filter count and, when tapped, opens ONE bottom drawer containing the
/// search field, the column filters, and the sort options.
///
/// This replaces the old inline [FilterBar] row in screen headers. All
/// [TableStore] behaviour (search, multi-column filters, sort) is
/// preserved — the combined sheet simply collects every control in one place.
class FilterButton<T> extends StatelessWidget {
  final TableStore<T> controller;
  final List<DataTableColumn> columns;

  /// Optional helper text rendered under the search field inside the sheet
  /// (e.g. the Vault note explaining which columns apply to records only).
  final Widget? helper;

  const FilterButton({
    super.key,
    required this.controller,
    required this.columns,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Observer(
      builder: (context) {
        // "Active" = any applied column filter, a search query, or a
        // non-default sort. We badge the column-filter count and treat search
        // as a contributor to the active state so the icon stays filled.
        final activeFilterCount = controller.filters.length;
        final hasSearch = controller.searchQuery.isNotEmpty;
        final hasActive = activeFilterCount > 0 || hasSearch;

        final button = AppButton(
          icon: hasActive ? AppIcons.funnelFill : AppIcons.funnel,
          tooltip: 'Search & filter',
          style: hasActive ? AppButtonStyle.primary : AppButtonStyle.accent,
          onTap: () => showFilterSheet<T>(
            context: context,
            controller: controller,
            columns: columns,
            helper: helper,
          ),
        );

        if (activeFilterCount == 0) return button;

        return Badge.count(
          count: activeFilterCount,
          backgroundColor: theme.colorScheme.primary,
          textColor: theme.colorScheme.onPrimary,
          child: button,
        );
      },
    );
  }
}

/// Opens the single combined search + filter + sort drawer via [showAppSheet].
/// Exposed separately so screens can trigger it from anywhere if needed.
Future<void> showFilterSheet<T>({
  required BuildContext context,
  required TableStore<T> controller,
  required List<DataTableColumn> columns,
  Widget? helper,
}) {
  return showAppSheet(
    context: context,
    builder: (sheetContext) => _FilterSheet<T>(
      controller: controller,
      columns: columns,
      helper: helper,
    ),
  );
}

/// The combined drawer body. Stateful so the search field keeps keyboard focus
/// while the controller mutates (filters added/removed, sort changed).
class _FilterSheet<T> extends StatefulWidget {
  final TableStore<T> controller;
  final List<DataTableColumn> columns;
  final Widget? helper;

  const _FilterSheet({
    required this.controller,
    required this.columns,
    this.helper,
  });

  @override
  State<_FilterSheet<T>> createState() => _FilterSheetState<T>();
}

class _FilterSheetState<T> extends State<_FilterSheet<T>> {
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.controller.searchQuery,
    );
    _searchController.addListener(_onSearchChanged);
    // Keeps the text field in step when the store's query changes elsewhere
    // (e.g. clearFilters); the guard prevents a feedback loop.
    _syncDisposer = reaction<String>((_) => widget.controller.searchQuery, (
      query,
    ) {
      if (_searchController.text != query) {
        _searchController.removeListener(_onSearchChanged);
        _searchController.text = query;
        _searchController.addListener(_onSearchChanged);
      }
    });
  }

  late final ReactionDisposer _syncDisposer;

  void _onSearchChanged() {
    if (widget.controller.searchQuery != _searchController.text) {
      widget.controller.searchQuery = _searchController.text;
    }
  }

  @override
  void dispose() {
    _syncDisposer();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Observer(
      builder: (context) {
        final filters = widget.controller.filters;
        final hasActiveFilters = filters.isNotEmpty;
        final hasSearch = widget.controller.searchQuery.isNotEmpty;

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xxs,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: title + clear-all shortcut.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Search & Filter').header,
                  if (hasActiveFilters || hasSearch)
                    AppButton(
                      icon: AppIcons.x,
                      label: 'Clear all',
                      style: AppButtonStyle.destructive,
                      size: AppButtonSize.small,
                      onTap: () {
                        widget.controller.searchQuery = '';
                        widget.controller.clearFilters();
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Everything scrolls together so a long filter list + sort never
              // overflows on small screens.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Global search box.
                      AppTextField(
                        controller: _searchController,
                        hint: 'Search...',
                        leading: Icon(
                          AppIcons.search,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (widget.helper != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        widget.helper!,
                      ],
                      const SizedBox(height: AppSpacing.xl),

                      // 2. Column filters.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Filters'),
                          AppButton(
                            icon: AppIcons.plus,
                            label: 'Add',
                            style: AppButtonStyle.accent,
                            size: AppButtonSize.small,
                            onTap: () {
                              if (widget.columns.isNotEmpty) {
                                widget.controller.addFilter(
                                  widget.columns.first.value,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (filters.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.lg,
                          ),
                          child: Center(
                            child: const Text('No filters applied').muted.small,
                          ),
                        )
                      else
                        ...filters.map((f) {
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: FilterRowWidget(
                              filter: f,
                              columns: widget.columns,
                              onUpdate: (id, {column, operator, value}) {
                                widget.controller.updateFilter(
                                  id,
                                  column: column,
                                  operator: operator,
                                  value: value,
                                );
                              },
                              onDelete: () =>
                                  widget.controller.removeFilter(f.id),
                            ),
                          );
                        }),

                      const SizedBox(height: AppSpacing.md),
                      const AppDivider(spaced: true),
                      const SizedBox(height: AppSpacing.md),

                      // 3. Sort options.
                      const Text('Sort by'),
                      const SizedBox(height: AppSpacing.sm),
                      _SortOptions<T>(
                        controller: widget.controller,
                        columns: widget.columns,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Sort option list extracted from the old `_showSortSheet`, unchanged in
/// behaviour. Rebuilt by the parent [Observer] so selection updates.
class _SortOptions<T> extends StatelessWidget {
  final TableStore<T> controller;
  final List<DataTableColumn> columns;

  const _SortOptions({required this.controller, required this.columns});

  @override
  Widget build(BuildContext context) {
    final activeSort = controller.sortBy;

    Widget option(String key, String label) {
      final selected = activeSort == key;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: AppButton(
          label: label,
          style: selected ? AppButtonStyle.primary : AppButtonStyle.accent,
          onTap: () => controller.setSort(key),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...columns.expand(
          (col) => [
            option('${col.value}_asc', '${col.label} (A-Z)'),
            option('${col.value}_desc', '${col.label} (Z-A)'),
          ],
        ),
        const AppDivider(spaced: true),
        option('created_desc', 'Newest First'),
        option('created_asc', 'Oldest First'),
      ],
    );
  }
}

/// A single filter row inside the filters sheet. Stateful so the value text
/// field keeps keyboard focus while typing.
class FilterRowWidget extends StatefulWidget {
  final DataTableFilter filter;
  final List<DataTableColumn> columns;
  final Function(String, {String? column, String? operator, String? value})
  onUpdate;
  final VoidCallback onDelete;

  const FilterRowWidget({
    super.key,
    required this.filter,
    required this.columns,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<FilterRowWidget> createState() => _FilterRowWidgetState();
}

class _FilterRowWidgetState extends State<FilterRowWidget> {
  late TextEditingController _valueController;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(text: widget.filter.value);
    _valueController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (widget.filter.value != _valueController.text) {
      widget.onUpdate(widget.filter.id, value: _valueController.text);
    }
  }

  @override
  void didUpdateWidget(covariant FilterRowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter.value != widget.filter.value &&
        _valueController.text != widget.filter.value) {
      _valueController.removeListener(_onTextChanged);
      _valueController.text = widget.filter.value;
      _valueController.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    _valueController.removeListener(_onTextChanged);
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Column Selector
        Expanded(
          flex: 4,
          child: AppSelect<String>(
            value: widget.filter.column,
            onChanged: (v) {
              if (v != null) widget.onUpdate(widget.filter.id, column: v);
            },
            items: widget.columns
                .map((col) => AppSelectItem(col.value, Text(col.label)))
                .toList(),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),

        // Operator Selector
        Expanded(
          flex: 3,
          child: AppSelect<String>(
            value: widget.filter.operator,
            onChanged: (v) {
              if (v != null) widget.onUpdate(widget.filter.id, operator: v);
            },
            items: const [
              AppSelectItem('contains', Text('contains')),
              AppSelectItem('equals', Text('equals')),
              AppSelectItem('starts_with', Text('starts with')),
              AppSelectItem('ends_with', Text('ends with')),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),

        // Value Input Field
        Expanded(
          flex: 4,
          child: AppTextField(controller: _valueController, hint: 'Value...'),
        ),
        const SizedBox(width: AppSpacing.xxs),

        // Delete Row Button
        AppButton(
          icon: AppIcons.x,
          tooltip: 'Remove filter',
          style: AppButtonStyle.accent,
          size: AppButtonSize.small,
          onTap: widget.onDelete,
        ),
      ],
    );
  }
}
