import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';

/// One choice in an [AppFilterChips] row.
class AppFilterOption<T> {
  final T value;
  final String label;
  final int count;

  const AppFilterOption({
    required this.value,
    required this.label,
    required this.count,
  });
}

/// The quick filter at the top of a list — "All 14 · Active 6 · Closed 8". The
/// counts are the overview: a reader sees how many of each there are before
/// scrolling. Small pills, so the row stays one line on a phone.
class AppFilterChips<T> extends StatelessWidget {
  final List<AppFilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  const AppFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final o in options)
          _Pill(
            label: '${o.label} ${o.count}',
            selected: o.value == selected,
            onTap: () => onSelected(o.value),
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
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.allPill,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xxs,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
