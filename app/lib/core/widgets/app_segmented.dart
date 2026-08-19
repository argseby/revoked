import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// One choice in an [AppSegmented].
class AppSegmentedItem<T> {
  final T value;
  final String? label;
  final IconData? icon;

  const AppSegmentedItem({required this.value, this.label, this.icon})
    : assert(label != null || icon != null, 'a segment needs a label or icon');
}

/// A one-of-N picker: theme mode, list/table view, edit mode. The only
/// segmented control — every filter and view toggle renders identically.
class AppSegmented<T> extends StatelessWidget {
  final T value;
  final List<AppSegmentedItem<T>> items;
  final ValueChanged<T> onChanged;

  const AppSegmented({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      segments: [
        for (final item in items)
          ButtonSegment<T>(
            value: item.value,
            icon: item.icon == null ? null : Icon(item.icon, size: 16),
            label: item.label == null ? null : Text(item.label!).small,
            tooltip: item.label ?? '',
          ),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onChanged(s.first),
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.allMd),
      ),
    );
  }
}
