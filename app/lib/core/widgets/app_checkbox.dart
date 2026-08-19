import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// The app's only checkbox — bare, for table headers and selection columns.
class AppCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?>? onChanged;

  /// Renders the "some but not all" bar. Only meaningful on a header box.
  final bool tristate;

  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.tristate = false,
  });

  @override
  Widget build(BuildContext context) {
    return Checkbox(
      value: value,
      tristate: tristate,
      onChanged: onChanged,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// A checkbox with a label and optional explanation, for the permission and
/// scope pickers. The whole row is the tap target.
class AppCheckRow extends StatelessWidget {
  final String label;
  final String? subtitle;

  /// Rendered after the label, for a marker the label itself cannot carry.
  final Widget? badge;

  final bool value;
  final ValueChanged<bool>? onChanged;

  const AppCheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return InkWell(
      onTap: enabled ? () => onChanged!(!value) : null,
      borderRadius: AppRadius.allMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCheckbox(
              value: value,
              onChanged: enabled ? (v) => onChanged!(v ?? false) : null,
            ),
            AppSpacing.gapSm,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(label)),
                        if (badge != null) ...[AppSpacing.gapSm, badge!],
                      ],
                    ),
                    if (subtitle != null) ...[
                      AppSpacing.gapXxs,
                      Text(subtitle!).muted.small,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
