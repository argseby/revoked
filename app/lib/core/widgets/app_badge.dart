import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';

/// [experimental] marks a feature still settling: a smaller, spaced-out pill
/// in the brand tint, so it reads as a tag on the label, not a status.
enum AppBadgeVariant {
  outline,
  secondary,
  primary,
  destructive,
  sunken,
  experimental,
}

/// The app's only tag. Every scrap of secondary information — a status, a
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

  /// Uppercase and spaced out, a tag can sit under the small size and still
  /// read; at the small size it would look like a second word of the label.
  static const double _tagFontSize = 10;

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
        case AppBadgeVariant.sunken:
          bg = scheme.surfaceContainerHighest;
          fg = scheme.onSurfaceVariant;
        case AppBadgeVariant.experimental:
          bg = scheme.primaryContainer;
          fg = scheme.onPrimaryContainer;
      }
    }
    final tag = variant == AppBadgeVariant.experimental && accent == null;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.allMd,
        border: border == null ? null : Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            AppSpacing.gapXxs,
          ],
          Flexible(
            child: Text(
              tag ? label.toUpperCase() : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: tag ? _tagFontSize : AppTextSize.small,
                letterSpacing: tag ? 1 : null,
                fontWeight: FontWeight.w500,
                fontFamily: mono ? AppFont.mono : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Beside the label of a field a form cannot be sent without, while that
/// field is still empty. Every form marks its required fields with this.
class AppRequiredBadge extends StatelessWidget {
  const AppRequiredBadge({super.key});

  @override
  Widget build(BuildContext context) =>
      const AppBadge(label: 'Required', variant: AppBadgeVariant.primary);
}
