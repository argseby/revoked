import 'package:material_ui/material_ui.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// One choice in an [AppFilterChips] row.
class AppFilterOption<T> {
  final T value;
  final String label;
  final int count;
  final bool alwaysVisible;

  const AppFilterOption({
    required this.value,
    required this.label,
    required this.count,
    this.alwaysVisible = false,
  });
}

/// The quick filter at the top of a list — "All 14 · Active 6 · Closed 8". The
/// counts are the overview: a reader sees how many of each there are before
/// scrolling. Small pills, so the row stays one line on a phone. An option
/// with nothing in it is left out, unless it is the one selected.
class AppFilterChips<T> extends StatelessWidget {
  final List<AppFilterOption<T>> options;
  final T selected;
  final Set<T>? selectedValues;
  final ValueChanged<T> onSelected;

  const AppFilterChips({
    super.key,
    required this.options,
    required this.selected,
    this.selectedValues,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final o in options)
          if (o.alwaysVisible ||
              o.count > 0 ||
              (selectedValues?.contains(o.value) ?? o.value == selected))
            _Pill(
              label: '${o.label} ${o.count}',
              selected:
                  selectedValues?.contains(o.value) ?? o.value == selected,
              onTap: () => onSelected(o.value),
            ),
      ],
    );
  }
}

/// [AppFilterChips] over a list's Status filter, which may hold several
/// values: "All 14 · Needs attention 2 · Active 6 · Closed 5". The chips show
/// and change the same selection as that section of Filter and sort. One
/// value ticked selects its chip, none selects All, and with several ticked
/// no chip is the selected one.
///
/// Shows nothing while the choice would change nothing: fewer than two
/// values hold anything and none is ticked.
class AppStatusChips<T> extends StatelessWidget {
  /// Each value with its label and how many items it holds.
  final List<AppFilterOption<T>> options;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;

  const AppStatusChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  /// Null while the chips would show nothing, so a page leaves out the
  /// space around them too.
  AppStatusChips<T>? get orNull =>
      options.where((o) => o.count > 0).length < 2 && selected.isEmpty
      ? null
      : this;

  @override
  Widget build(BuildContext context) {
    if (orNull == null) return const SizedBox.shrink();
    final total = options.fold(0, (n, o) => n + o.count);
    final single = selected.length == 1 ? selected.single : null;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        _Pill(
          label: 'All $total',
          selected: selected.isEmpty,
          onTap: () => onChanged(const {}),
        ),
        for (final o in options)
          if (o.count > 0 || selected.contains(o.value))
            _Pill(
              label: '${o.label} ${o.count}',
              selected: o.value == single,
              onTap: () => onChanged({o.value}),
            ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primary : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.allMd,
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.allMd,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xxs,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: AppTextSize.small,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
