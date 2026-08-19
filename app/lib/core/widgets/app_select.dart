import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';

/// One option in an [AppSelect].
class AppSelectItem<T> {
  final T value;
  final Widget child;
  const AppSelectItem(this.value, this.child);
}

/// Material 3 dropdown. Replaces shadcn's `Select<T>` (which used a
/// `SelectPopup`/`SelectItemButton` builder API). Renders as a bordered,
/// dense form field for visual parity with [AppTextField].
class AppSelect<T> extends StatelessWidget {
  final T? value;
  final String? placeholder;
  final ValueChanged<T?>? onChanged;
  final List<AppSelectItem<T>> items;
  final bool isDense;

  const AppSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.placeholder,
    this.isDense = true,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        isDense: isDense,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          borderRadius: AppRadius.allMd,
          isExpanded: true,
          isDense: isDense,
          hint: placeholder == null ? null : Text(placeholder!),
          items: items
              .map((i) => DropdownMenuItem<T>(value: i.value, child: i.child))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
