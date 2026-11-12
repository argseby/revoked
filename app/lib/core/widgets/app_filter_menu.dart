import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_select.dart';
import 'package:revoked_app/core/widgets/app_filter_chips.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';

/// One box in an [AppChecklistSection].
class AppChecklistItem {
  /// What the caller keeps in its selection.
  final String id;
  final String label;

  /// How many entries the box lets through, shown after the label.
  final int? count;

  const AppChecklistItem({required this.id, required this.label, this.count});
}

/// A named group of boxes in the Filter and sort panel — "Status", "Person".
/// Within a section the ticked boxes add up: Active and Paused shows both.
/// Nothing ticked means the section does not narrow anything.
class AppChecklistSection {
  final String title;
  final List<AppChecklistItem> items;
  final Set<String> selected;
  final void Function(String id, bool on) onToggle;

  /// With more items than this a search field narrows the boxes.
  final int searchAbove;

  const AppChecklistSection({
    required this.title,
    required this.items,
    required this.selected,
    required this.onToggle,
    this.searchAbove = 8,
  });
}

/// One order in the Filter and sort panel.
class AppSortOption<T> {
  final T value;
  final String label;

  const AppSortOption(this.value, this.label);
}

/// Search beside a separate filter control. Collection pages keep both
/// above their rows; shell-hosted lists can use [button] to open search too.
/// Filters open in a bounded popover on desktop and a bottom sheet on phones.
/// Sort and filter changes apply immediately, with removable [chips] above
/// the list. The panel observes [sections] and [sort] while it is open.
class AppListToolbar extends StatelessWidget {
  final String query;
  final ValueChanged<String> onQueryChanged;
  final String searchHint;

  /// Search matches before filters. Enables the shared quick-filter row.
  final int? totalCount;

  /// A collection can name its reset choice and reflect its navigation scope.
  final String allLabel;
  final bool Function()? isAllSelected;

  /// Sections promoted to quick filters; otherwise the first section.
  final List<String>? quickSections;

  /// The filters; empty where a list has nothing to filter by.
  final List<AppChecklistSection> Function() sections;

  /// Unticks every filter.
  final VoidCallback onClearFilters;

  final List<AppSortOption<String>> sortOptions;

  /// The current order.
  final String Function() sort;
  final ValueChanged<String> onSort;

  /// The order the list starts in; any other shows as a chip.
  final String defaultSort;

  const AppListToolbar({
    super.key,
    required this.query,
    required this.onQueryChanged,
    this.searchHint = 'Search',
    this.totalCount,
    this.allLabel = 'All',
    this.isAllSelected,
    this.quickSections,
    required this.sections,
    required this.onClearFilters,
    required this.sortOptions,
    required this.sort,
    required this.onSort,
    required this.defaultSort,
  });

  String? get _sortLabel {
    final current = sort();
    if (current == defaultSort) return null;
    for (final o in sortOptions) {
      if (o.value == current) return o.label;
    }
    return null;
  }

  /// What narrows or reorders the list; with [withQuery], a typed search
  /// counts too.
  int _activeCount({bool withQuery = false}) =>
      sections().fold<int>(0, (n, s) => n + s.selected.length) +
      (_sortLabel == null ? 0 : 1) +
      (withQuery && query.trim().isNotEmpty ? 1 : 0);

  void _reset({bool withQuery = false}) {
    onClearFilters();
    onSort(defaultSort);
    if (withQuery) onQueryChanged('');
  }

  /// Search, Filter and sort behind one button, for the shell's top bar.
  Widget button() => _FilterSortButton(toolbar: this, withSearch: true);

  /// Search and its neighbouring filter control. The label collapses to
  /// an icon on small screens so the query keeps room to type.
  Widget pill({bool autofocus = false}) => LayoutBuilder(
    key: key == null ? null : ValueKey((key, 'search-layout')),
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      return Row(
        children: [
          Expanded(
            child: AppListSearchField(
              key: key == null ? null : ValueKey((key, 'pill')),
              value: query,
              hint: searchHint,
              autofocus: autofocus,
              onChanged: onQueryChanged,
            ),
          ),
          AppSpacing.gapSm,
          _FilterSortButton(
            toolbar: this,
            labelled:
                !AppSpacing.isNarrow(context) &&
                box.maxWidth >= _labelledFrom * scale,
          ),
        ],
      );
    },
  );

  /// What narrows or reorders the list, one chip each; null while nothing
  /// does. Always above the list, so the list says why it is short.
  ///
  /// [withQuery] adds the typed search, for the shell, where the field is
  /// behind the top bar's [button].
  Widget? chips(BuildContext context, {bool withQuery = false}) {
    final narrow = AppSpacing.isNarrow(context);
    final typed = query.trim();
    final chips = <Widget>[
      if (withQuery && typed.isNotEmpty)
        _ActiveChip(label: '“$typed”', onRemove: () => onQueryChanged('')),
      for (final s in sections())
        for (final id in s.selected)
          _ActiveChip(
            label: narrow
                ? (s.items.where((item) => item.id == id).firstOrNull?.label ??
                      id)
                : '${s.title}: ${s.items.where((item) => item.id == id).firstOrNull?.label ?? id}',
            onRemove: () => s.onToggle(id, false),
          ),
      if (_sortLabel case final label?)
        _ActiveChip(label: label, onRemove: () => onSort(defaultSort)),
    ];
    if (chips.isEmpty) return null;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: chips,
    );
  }

  /// Quick choices and the drawer are two views of the same selections.
  /// Choosing a quick option replaces that section's choice; All clears all
  /// filters while preserving the query and ordering.
  Widget? quickFilters() {
    final total = totalCount;
    final available = sections();
    if (total == null || available.isEmpty) return null;
    final promoted = quickSections == null
        ? available.take(1).toList()
        : available.where((s) => quickSections!.contains(s.title)).toList();
    if (promoted.isEmpty) return null;
    final values = <String, (AppChecklistSection, AppChecklistItem)>{};
    final selected = <String>{};
    final all =
        available.every((s) => s.selected.isEmpty) &&
        (isAllSelected?.call() ?? true);
    if (all) selected.add('');
    for (final (index, section) in promoted.indexed) {
      for (final item in section.items) {
        final key = '$index:${item.id}';
        values[key] = (section, item);
        if (section.selected.contains(item.id)) selected.add(key);
      }
    }
    return AppFilterChips<String>(
      selected: '',
      selectedValues: selected,
      options: [
        AppFilterOption(
          value: '',
          label: allLabel,
          count: total,
          alwaysVisible: true,
        ),
        for (final entry in values.entries)
          AppFilterOption(
            value: entry.key,
            label: entry.value.$2.label,
            count: entry.value.$2.count ?? total,
          ),
      ],
      onSelected: (key) {
        if (key.isEmpty) {
          onClearFilters();
          return;
        }
        final (section, item) = values[key]!;
        final wasOnly =
            section.selected.length == 1 && section.selected.contains(item.id);
        for (final id in section.selected.toList()) {
          section.onToggle(id, false);
        }
        if (!wasOnly) section.onToggle(item.id, true);
      },
    );
  }

  @override
  Widget build(BuildContext context) => Observer(
    builder: (context) {
      final quick = quickFilters();
      final chips = this.chips(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (quick != null) ...[quick, AppSpacing.gapLg],
          pill(),
          if (chips != null) ...[AppSpacing.gapSm, chips],
        ],
      );
    },
  );
}

/// The search field of an [AppListToolbar]. Esc clears the query; the ×
/// after it does too. [action] sits at the end, inside the pill.
class AppListSearchField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String hint;
  final Widget? action;
  final bool autofocus;

  const AppListSearchField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint = 'Search',
    this.action,
    this.autofocus = false,
  });

  @override
  State<AppListSearchField> createState() => _AppListSearchFieldState();
}

class _AppListSearchFieldState extends State<AppListSearchField> {
  late final ObservableTextController _controller = ObservableTextController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(AppListSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cleared from outside — a reset, a new route.
    if (widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const text = TextStyle(
      fontSize: AppTextSize.small,
      fontWeight: FontWeight.w400,
      height: AppTextSize.smallHeight,
    );
    final border = OutlineInputBorder(
      borderRadius: AppRadius.allMd,
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          bodyLarge: theme.textTheme.bodyLarge?.merge(text),
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          hintStyle: text.copyWith(color: scheme.onSurfaceVariant),
          prefixIconColor: scheme.onSurfaceVariant,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.allMd,
            borderSide: BorderSide(color: scheme.primary),
          ),
        ),
      ),
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clear},
        child: Observer(
          builder: (context) => AppTextField(
            controller: _controller,
            hint: widget.hint,
            autofocus: widget.autofocus,
            leading: const Icon(AppIcons.search, size: 16),
            trailing: Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.xxs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_controller.text.isNotEmpty)
                    AppButton(
                      icon: AppIcons.x,
                      tooltip: 'Clear search',
                      showTooltip: false,
                      style: AppButtonStyle.ghost,
                      size: AppButtonSize.small,
                      onTap: _clear,
                    ),
                  ?widget.action,
                ],
              ),
            ),
            onChanged: widget.onChanged,
          ),
        ),
      ),
    );
  }
}

/// The narrowest toolbar whose filter control still carries its label.
const double _labelledFrom = 360;

/// The lightly outlined utility beside search. With [withSearch], the shell's button
/// opens search too. Labels yield to an icon when space is limited.
class _FilterSortButton extends StatefulWidget {
  final AppListToolbar toolbar;
  final bool labelled;

  /// The panel opens with the search field first, and the count, the chips
  /// and Reset take the search in.
  final bool withSearch;

  const _FilterSortButton({
    required this.toolbar,
    this.labelled = false,
    this.withSearch = false,
  });

  @override
  State<_FilterSortButton> createState() => _FilterSortButtonState();
}

class _FilterSortButtonState extends State<_FilterSortButton> {
  /// Each section's box search, by title; kept while the panel is closed.
  final Map<String, Local<String>> _queries = {};
  final MenuController _menuController = MenuController();

  Local<String> _query(String section) =>
      _queries.putIfAbsent(section, () => Local(''));

  AppListToolbar get _t => widget.toolbar;

  bool get _withSearch => widget.withSearch;

  String get _label => _withSearch ? 'Search and filter' : 'Filter and sort';

  /// The shell's button: a ghost button like its neighbours in the bar,
  /// labelled beside the sidebar, the count on its corner.
  Widget _barTrigger(BuildContext context, int active, VoidCallback onTap) {
    final labelled = MediaQuery.sizeOf(context).width >= AppSpacing.wideWidth;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppButton(
          icon: AppIcons.sliders,
          label: labelled ? _label : null,
          emphasizeLabel: false,
          style: AppButtonStyle.outline,
          size: labelled ? AppButtonSize.small : AppButtonSize.normal,
          tooltip: active > 0 ? '$_label · $active active' : _label,
          onTap: onTap,
        ),
        if (active > 0)
          PositionedDirectional(
            top: labelled ? -AppSpacing.xxs : AppSpacing.xxs,
            end: labelled ? -AppSpacing.xxs : AppSpacing.xxs,
            child: IgnorePointer(child: _CountBadge(active)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrow = AppSpacing.isNarrow(context);
    final active = _t._activeCount(withQuery: _withSearch);
    Widget trigger(VoidCallback onTap) {
      if (_withSearch) return _barTrigger(context, active, onTap);
      return AppButton(
        icon: AppIcons.sliders,
        label: widget.labelled
            ? '$_label${active > 0 ? ' · $active' : ''}'
            : null,
        tooltip: active > 0 ? '$_label · $active active' : _label,
        emphasizeLabel: false,
        size: widget.labelled ? AppButtonSize.small : AppButtonSize.normal,
        style: AppButtonStyle.outline,
        onTap: onTap,
      );
    }

    if (narrow) return trigger(() => _openSheet(context));

    return MenuAnchor(
      controller: _menuController,
      alignmentOffset: const Offset(0, AppSpacing.sm),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStatePropertyAll(
          Theme.of(context).colorScheme.surface,
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.allLg),
        ),
      ),
      builder: (context, controller, _) => trigger(
        () => controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        Builder(
          builder: (context) => SizedBox(
            width: math.min(
              400,
              MediaQuery.sizeOf(context).width - AppSpacing.xxl * 2,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(
                  120,
                  math.min(
                    680,
                    MediaQuery.sizeOf(context).height - AppSpacing.xxl * 2,
                  ),
                ),
              ),
              child: Observer(
                builder: (context) => _panel(context, _menuController.close),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openSheet(BuildContext context) => showAppSheet<void>(
    context: context,
    dismissible: true,
    builder: (context) => Observer(
      builder: (context) => _panel(context, () => Navigator.of(context).pop()),
    ),
  );

  /// Changes apply immediately. Only the choices scroll, keeping the way
  /// back to the list and Reset reachable even with a long list or keyboard.
  Widget _panel(BuildContext context, VoidCallback close) {
    final sections = _t.sections();
    final active = _t._activeCount(withQuery: _withSearch);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: AppText(_label).header),
              AppSpacing.gapXxs,
              const Text('Changes apply as you choose.').small.muted,
            ],
          ),
        ),
        const AppDivider(),
        Flexible(
          child: SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_withSearch) ...[
                  AppListSearchField(
                    value: _t.query,
                    hint: _t.searchHint,
                    autofocus: true,
                    onChanged: _t.onQueryChanged,
                  ),
                  AppSpacing.gapXxl,
                ],
                if (_t.sortOptions.isNotEmpty) ...[
                  const _PanelHeading('Sort'),
                  AppSelect<String>(
                    value: _t.sort(),
                    onChanged: (value) {
                      if (value != null) _t.onSort(value);
                    },
                    items: [
                      for (final option in _t.sortOptions)
                        AppSelectItem(
                          option.value,
                          Text(
                            option.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                  if (sections.isNotEmpty) AppSpacing.gapXxl,
                ],
                for (final (index, section) in sections.indexed) ...[
                  if (index > 0) AppSpacing.gapXxl,
                  _PanelHeading(
                    section.title,
                    selected: section.selected.length,
                    onClear: () {
                      for (final id in section.selected.toList()) {
                        section.onToggle(id, false);
                      }
                    },
                  ),
                  if (section.items.length > section.searchAbove) ...[
                    _BoxSearch(
                      title: section.title,
                      query: _query(section.title),
                    ),
                    AppSpacing.gapSm,
                  ],
                  if (_visible(section).isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Text('No matching options.'),
                    )
                  else if (section.items.length <= section.searchAbove)
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final item in section.items)
                          _FilterChoice(
                            label: item.label,
                            count: item.count,
                            selected: section.selected.contains(item.id),
                            onTap: () => section.onToggle(
                              item.id,
                              !section.selected.contains(item.id),
                            ),
                          ),
                      ],
                    )
                  else
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: AppRadius.allMd,
                      ),
                      child: Column(
                        children: [
                          for (final item in _visible(section))
                            _PanelRow(
                              label: item.label,
                              count: item.count,
                              selected: section.selected.contains(item.id),
                              onTap: () => section.onToggle(
                                item.id,
                                !section.selected.contains(item.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        const AppDivider(),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppButton(
                    label: 'Reset',
                    emphasizeLabel: false,
                    style: AppButtonStyle.ghost,
                    onTap:
                        active > 0 ||
                            _queries.values.any((q) => q.value.isNotEmpty)
                        ? () {
                            _t._reset(withQuery: _withSearch);
                            for (final query in _queries.values) {
                              query.value = '';
                            }
                          }
                        : null,
                  ),
                ),
              ),
              AppSpacing.gapSm,
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AppButton(label: 'Done', onTap: close),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<AppChecklistItem> _visible(AppChecklistSection section) {
    if (section.items.length <= section.searchAbove) return section.items;
    final q = _query(section.title).value.trim().toLowerCase();
    if (q.isEmpty) return section.items;
    return [
      for (final item in section.items)
        // A ticked box stays in view, so it can be unticked while searching.
        if (item.label.toLowerCase().contains(q) ||
            section.selected.contains(item.id))
          item,
    ];
  }
}

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge(this.count);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: AppRadius.allMd,
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 11,
          height: 1.3,
        ),
      ),
    );
  }
}

/// What narrows or reorders the list, under the pill; its × undoes it.
class _ActiveChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _ActiveChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Remove $label',
      excludeSemantics: true,
      child: Material(
        color: scheme.primary.withValues(alpha: 0.1),
        borderRadius: AppRadius.allSm,
        child: InkWell(
          borderRadius: AppRadius.allSm,
          onTap: onRemove,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.sm,
              AppSpacing.xxs,
              AppSpacing.xs,
              AppSpacing.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(color: scheme.primary, fontSize: 12),
                ),
                AppSpacing.gapXxs,
                Icon(AppIcons.x, size: 14, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelHeading extends StatelessWidget {
  final String title;
  final int selected;
  final VoidCallback? onClear;

  const _PanelHeading(this.title, {this.selected = 0, this.onClear});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: AppText(
              selected > 0 ? '$title · $selected' : title,
            ).small.bold,
          ),
        ),
        if (selected > 0) ...[
          AppButton(
            label: 'Clear',
            tooltip: 'Clear $title',
            style: AppButtonStyle.ghost,
            size: AppButtonSize.small,
            onTap: onClear,
          ),
        ],
      ],
    ),
  );
}

class _FilterChoice extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      checked: selected,
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
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 18,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                AppSpacing.gapSm,
                Flexible(child: AppText(label).small),
                if (count != null) ...[
                  AppSpacing.gapSm,
                  AppText('$count').small.muted,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One checkbox row in a searchable filter section.
class _PanelRow extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _PanelRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = selected ? Icons.check_box : Icons.check_box_outline_blank;
    return Semantics(
      button: true,
      checked: selected,
      child: InkWell(
        onTap: onTap,
        // Checklist rows use the same rectangular feedback as list rows.
        borderRadius: AppRadius.row,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              AppSpacing.gapSm,
              Expanded(child: Text(label)),
              if (count != null) AppText('$count').small.muted,
            ],
          ),
        ),
      ),
    );
  }
}

class _BoxSearch extends StatelessWidget {
  final Local<String> query;
  final String title;

  const _BoxSearch({required this.query, required this.title});

  @override
  Widget build(BuildContext context) => AppListSearchField(
    value: query.value,
    hint: 'Find ${title.toLowerCase()}',
    onChanged: (value) => query.value = value,
  );
}
