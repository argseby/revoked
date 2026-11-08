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

/// A list's search, Filter and sort:
///
///   top bar:   Shares        [🔍 Search links …… ⚟ Filter and sort ②] [+ New]
///   the list:  (Status: Active ×) (Oldest first ×)
///
/// One [pill] holds the search and, at its end, the button to the Filter and
/// sort panel — a popover on a wider window, a sheet on a phone, where the
/// button keeps only its icon. In the shell the pill sits in the top bar
/// beside New (on a phone behind a search icon there); `AppListPage` hands it
/// up. What narrows or reorders the list shows above the list as [chips],
/// each removed with its ×, so a list that looks short always says why.
///
/// This narrows the list it sits above. The shell's "Open link or go to" is
/// the other search: across everything, and it opens what it finds.
///
/// [sections] and [sort] are read inside an `Observer`, so an open panel and
/// the chips follow the caller's selection as it changes.
class AppListToolbar extends StatelessWidget {
  final String query;
  final ValueChanged<String> onQueryChanged;
  final String searchHint;

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

  int _activeCount() =>
      sections().fold<int>(0, (n, s) => n + s.selected.length) +
      (_sortLabel == null ? 0 : 1);

  void _reset() {
    onClearFilters();
    onSort(defaultSort);
  }

  /// The search pill with its Filter and sort button — in the shell's top
  /// bar, or above the list outside the shell. [autofocus] for the phone's
  /// search bar, which opens to type.
  ///
  /// Under [_labelledFrom] the button keeps only its icon and count, as on a
  /// phone, so the field keeps room to type in.
  Widget pill({bool autofocus = false}) => LayoutBuilder(
    builder: (context, box) => AppListSearchField(
      key: key == null ? null : ValueKey((key, 'pill')),
      value: query,
      hint: searchHint,
      autofocus: autofocus,
      onChanged: onQueryChanged,
      action: _FilterSortButton(
        toolbar: this,
        labelled:
            !AppSpacing.isNarrow(context) && box.maxWidth >= _labelledFrom,
      ),
    ),
  );

  /// What narrows or reorders the list, one chip each; null while nothing
  /// does. Always above the list, so the list says why it is short.
  Widget? chips(BuildContext context) {
    final narrow = AppSpacing.isNarrow(context);
    final chips = <Widget>[
      for (final s in sections())
        for (final item in s.items)
          if (s.selected.contains(item.id))
            _ActiveChip(
              label: narrow ? item.label : '${s.title}: ${item.label}',
              onRemove: () => s.onToggle(item.id, false),
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

  @override
  Widget build(BuildContext context) {
    final chips = this.chips(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pill(),
        if (chips != null) ...[AppSpacing.gapSm, chips],
      ],
    );
  }
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
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clear},
      child: Observer(
        builder: (context) => AppTextField(
          controller: _controller,
          hint: widget.hint,
          autofocus: widget.autofocus,
          leading: const Icon(AppIcons.search, size: 18),
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
    );
  }
}

/// The button at the end of the pill. Labelled where there is room; on a
/// phone its icon and the count say it.
/// The narrowest pill whose button still carries its label.
const double _labelledFrom = 360;

class _FilterSortButton extends StatefulWidget {
  final AppListToolbar toolbar;
  final bool labelled;

  const _FilterSortButton({required this.toolbar, required this.labelled});

  @override
  State<_FilterSortButton> createState() => _FilterSortButtonState();
}

class _FilterSortButtonState extends State<_FilterSortButton> {
  /// Each section's box search, by title; kept while the panel is closed.
  final Map<String, Local<String>> _queries = {};

  Local<String> _query(String section) =>
      _queries.putIfAbsent(section, () => Local(''));

  AppListToolbar get _t => widget.toolbar;

  @override
  Widget build(BuildContext context) {
    final narrow = AppSpacing.isNarrow(context);
    final active = _t._activeCount();
    const label = 'Filter and sort';
    Widget trigger(VoidCallback onTap) {
      final scheme = Theme.of(context).colorScheme;
      return Tooltip(
        message: active > 0 ? '$label · $active active' : label,
        child: Material(
          color: scheme.surfaceContainerHighest,
          borderRadius: AppRadius.allSm,
          child: InkWell(
            borderRadius: AppRadius.allSm,
            onTap: onTap,
            child: SizedBox(
              height: AppButton.smallExtent - AppSpacing.xs,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(AppIcons.sliders, size: 16),
                    if (widget.labelled) ...[
                      AppSpacing.gapXs,
                      const AppText(label).small,
                    ],
                    if (active > 0) ...[AppSpacing.gapXs, _CountBadge(active)],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (narrow) return trigger(() => _openSheet(context));

    return MenuAnchor(
      alignmentOffset: const Offset(0, AppSpacing.xs),
      style: const MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.allMd),
        ),
      ),
      menuChildren: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 260, maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Observer(builder: (context) => _panel(context)),
          ),
        ),
      ],
      builder: (context, controller, _) => trigger(
        () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) => showAppSheet<void>(
    context: context,
    dismissible: true,
    builder: (_) => SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Observer(builder: (context) => _panel(context)),
    ),
  );

  /// The same panel in the popover and the sheet: Sort first, one order
  /// picked; then each filter section's boxes with their counts.
  Widget _panel(BuildContext context) {
    final sections = _t.sections();
    final current = _t.sort();
    final active = _t._activeCount();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              const Expanded(child: Text('Filter and sort')),
              AppButton(
                icon: AppIcons.arrowClockwise,
                label: 'Reset',
                style: AppButtonStyle.ghost,
                size: AppButtonSize.small,
                onTap: active > 0 ? _t._reset : null,
              ),
            ],
          ),
        ),
        const AppDivider(),
        const _PanelHeading('Sort'),
        for (final o in _t.sortOptions)
          _PanelRow(
            label: o.label,
            radio: true,
            selected: o.value == current,
            onTap: () => _t.onSort(o.value),
          ),
        for (final section in sections) ...[
          _PanelHeading(section.title),
          if (section.items.length > section.searchAbove)
            _BoxSearch(query: _query(section.title)),
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
        color: scheme.primary,
        borderRadius: AppRadius.allMd,
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(color: scheme.onPrimary, fontSize: 11, height: 1.3),
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

  const _PanelHeading(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.xxs,
    ),
    child: AppText(title).small.muted,
  );
}

/// One choice in the panel: a radio for the order, a box for a filter.
class _PanelRow extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final bool radio;
  final VoidCallback onTap;

  const _PanelRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.radio = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = radio
        ? (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked)
        : (selected ? Icons.check_box : Icons.check_box_outline_blank);
    return Semantics(
      button: true,
      selected: selected,
      checked: radio ? null : selected,
      inMutuallyExclusiveGroup: radio,
      child: InkWell(
        onTap: onTap,
        // Full-width rows of the panel: square, edge to edge.
        borderRadius: BorderRadius.zero,
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

  const _BoxSearch({required this.query});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xxs,
    ),
    child: AppTextField(
      hint: 'Search',
      initialValue: query.value,
      leading: const Icon(AppIcons.search, size: 18),
      onChanged: (v) => query.value = v,
    ),
  );
}
