import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_focus_ring.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// The height of the bar's other controls, so search and New line up.
const double _searchHeight = AppButton.smallExtent;

/// The shell's "Open link or go to" pill: it opens the panel that finds
/// anything by name or opens a pasted link, rather than filtering anything in
/// place. A list's own search is the field in its `AppListToolbar`.
class AppSearchTrigger extends StatelessWidget {
  final String hint;
  final VoidCallback onTap;
  final Widget? trailing;

  /// Makes a navigation search stand apart from destination rows.
  final bool outlined;
  final bool compact;
  final BorderRadius borderRadius;
  final double height;

  /// Optional leading icon describing what this search opens.
  final IconData? icon;

  const AppSearchTrigger({
    super.key,
    required this.hint,
    required this.onTap,
    this.trailing,
    this.icon,
    this.outlined = false,
    this.compact = false,
    this.borderRadius = AppRadius.allMd,
    this.height = _searchHeight,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: hint,
      excludeSemantics: true,
      child: AppFocusRing(
        borderRadius: borderRadius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: borderRadius,
            child: Ink(
              height: height,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: borderRadius,
                border: outlined ? Border.all(color: scheme.outline) : null,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    AppSpacing.gapMd,
                    Icon(icon, size: 16, color: scheme.onSurfaceVariant),
                    AppSpacing.gapSm,
                  ] else
                    AppSpacing.gapMd,

                  Expanded(
                    child: AppText(
                      hint,
                      small: compact,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).muted,
                  ),
                  if (trailing != null) ...[
                    trailing!,
                    AppSpacing.gapSm,
                  ] else
                    AppSpacing.gapMd,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
