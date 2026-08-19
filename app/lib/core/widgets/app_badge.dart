import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';

enum AppBadgeVariant { outline, secondary, primary, destructive }

/// The app's only pill. Every scrap of secondary information — a status, a
/// view count, a type, a scope, a security flag — renders as one of these, so
/// they line up identically wherever they appear.
///
/// It takes the text rather than a child widget on purpose: a badge is always
/// the small size, and a caller that could pass its own styled text could
/// (and did) hand it body-sized text, which reads as a button rather than a
/// label.
///
/// Pass an [accent] to tint it with a semantic color (a status); it wins over
/// [variant], which otherwise picks a Material color role.
class AppBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final AppBadgeVariant variant;
  final Color? accent;

  /// Renders the label in the mono face — scopes, record keys, types.
  final bool mono;

  const AppBadge({
    super.key,
    required this.label,
    this.icon,
    this.variant = AppBadgeVariant.secondary,
    this.accent,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late final Color bg;
    late final Color fg;
    Color? border;

    if (accent != null) {
      bg = accent!.withValues(alpha: 0.12);
      fg = accent!;
    } else {
      switch (variant) {
        case AppBadgeVariant.secondary:
          bg = scheme.secondaryContainer;
          fg = scheme.onSecondaryContainer;
        case AppBadgeVariant.primary:
          bg = scheme.primary;
          fg = scheme.onPrimary;
        case AppBadgeVariant.destructive:
          bg = scheme.errorContainer;
          fg = scheme.onErrorContainer;
        case AppBadgeVariant.outline:
          bg = Colors.transparent;
          fg = scheme.onSurfaceVariant;
          border = scheme.outlineVariant;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.allPill,
        border: border == null ? null : Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            AppSpacing.gapXxs,
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}
