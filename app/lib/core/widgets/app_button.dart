import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';

/// How much weight a button carries. There is no fourth style on purpose: a
/// control that is neither the screen's main action nor destructive is
/// [accent], and the moment a "just one more" style exists the screens drift.
enum AppButtonStyle { primary, accent, destructive }

enum AppButtonSize { normal, small }

/// The app's only button. Views never use Filled/Outlined/Text/IconButton
/// directly — a second button implementation is how screens drift apart.
///
/// Three styles × icon-only or icon+label × normal or small. Omit [label] for
/// an icon-only button; it then needs a [tooltip], which is also its
/// accessible name.
class AppButton extends StatelessWidget {
  final String? label;
  final IconData? icon;

  /// Trailing affordance for dropdown and menu triggers, so a trigger is the
  /// same button as everything else rather than a hand-built container.
  final IconData? trailingIcon;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final AppButtonStyle style;
  final AppButtonSize size;

  /// Replaces the content with a spinner and disables the button, so every
  /// in-flight action looks the same.
  final bool busy;

  final String? tooltip;

  const AppButton({
    super.key,
    this.label,
    this.icon,
    this.trailingIcon,
    required this.onTap,
    this.onLongPress,
    this.style = AppButtonStyle.primary,
    this.size = AppButtonSize.normal,
    this.busy = false,
    this.tooltip,
  }) : assert(label != null || icon != null, 'a button needs a label or icon'),
       assert(
         label != null || tooltip != null,
         'an icon-only button needs a tooltip — it is its accessible name',
       );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = size == AppButtonSize.small;
    final iconOnly = label == null;
    final iconSize = small ? 16.0 : 18.0;
    final extent = small ? 32.0 : 40.0;

    final (Color background, Color foreground) = switch (style) {
      AppButtonStyle.primary => (scheme.primary, scheme.onPrimary),
      AppButtonStyle.accent => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      AppButtonStyle.destructive => (scheme.error, scheme.onError),
    };

    final AppText? text = iconOnly
        ? null
        : AppText(
            label!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            bold: true,
          );

    final Widget content = busy
        ? AppSpinner(color: foreground)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon, size: iconSize),
              if (icon != null && text != null) AppSpacing.gapXs,
              if (text != null) Flexible(child: small ? text.small : text),
              if (trailingIcon != null) ...[
                AppSpacing.gapXxs,
                Icon(trailingIcon, size: iconSize),
              ],
            ],
          );

    final button = FilledButton(
      onPressed: busy ? null : onTap,
      onLongPress: busy ? null : onLongPress,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
        elevation: 0,
        minimumSize: Size(iconOnly ? extent : 0, extent),
        padding: iconOnly
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(
                horizontal: small ? AppSpacing.md : AppSpacing.lg,
              ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.allMd),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      ),
      child: content,
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
