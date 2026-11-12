import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/design/app_colors.dart';

/// How much weight a button carries. [outline] gives secondary controls a
/// subtle boundary so they are recognizable before hover.
/// A control that is neither the screen's
/// main action nor destructive is [accent]. [ghost] has no fill of its own and
/// is only for a control repeated on every row or group — a ⋮ menu — where an
/// [accent] fill on each one would outweigh the content it sits beside.
/// [destructive] is the solid red of a confirmation; [danger] is the same
/// warning outlined, for a destructive action resting on a page, so it is
/// never the loudest thing on it.
enum AppButtonStyle { primary, accent, outline, destructive, danger, ghost }

enum AppButtonSize { normal, small }

/// The app's only button. Views never use Filled/Outlined/Text/IconButton
/// directly — a second button implementation is how screens drift apart.
///
/// Styles support icon-only or icon+label, normal or small. Omit [label] for
/// an icon-only button; it then needs a [tooltip], which is also its
/// accessible name.
class AppButton extends StatelessWidget {
  final String? label;

  /// Secondary utilities can use a regular-weight label.
  final bool emphasizeLabel;
  final IconData? icon;

  /// Trailing affordance for dropdown and menu triggers, so a trigger is the
  /// same button as everything else rather than a hand-built container.
  final IconData? trailingIcon;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final AppButtonStyle style;
  final AppButtonSize size;

  /// A grouped control can match its enclosing surface without changing the app default.
  final BorderRadius borderRadius;

  /// Replaces the content with a spinner and disables the button, so every
  /// in-flight action looks the same.
  final bool busy;

  final String? tooltip;

  /// Off for a button inside a text field, where any semantics node of its
  /// own is reported off screen once the form scrolls, so screen readers
  /// can't reach it. The [tooltip] still names it, merged into one node.
  final bool showTooltip;

  /// Height of a button at each size. Exposed so surfaces that sit a button
  /// next to plain text can reserve the same height whether or not a button is
  /// actually there, instead of collapsing to the text's own height.
  ///
  /// 44 and 36 so a button is easy to hit; a small one sits inline in a row
  /// where the row itself carries the full 48.
  static const double normalExtent = 44;
  static const double smallExtent = 36;

  const AppButton({
    super.key,
    this.label,
    this.emphasizeLabel = true,
    this.icon,
    this.trailingIcon,
    required this.onTap,
    this.onLongPress,
    this.style = AppButtonStyle.primary,
    this.size = AppButtonSize.normal,
    this.borderRadius = AppRadius.allMd,
    this.busy = false,
    this.tooltip,
    this.showTooltip = true,
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
    final extent = small ? smallExtent : normalExtent;

    final (Color background, Color foreground) = switch (style) {
      AppButtonStyle.primary => (scheme.primary, scheme.onPrimary),
      // Outlined rather than tinted: a pale fill reads as disabled on white
      // and turns muddy on an alert's colour.
      AppButtonStyle.accent => (Colors.transparent, scheme.onSurface),
      AppButtonStyle.destructive => (scheme.dangerFill, scheme.onDangerFill),
      AppButtonStyle.danger => (Colors.transparent, scheme.danger),
      AppButtonStyle.ghost ||
      AppButtonStyle.outline => (Colors.transparent, scheme.onSurfaceVariant),
    };

    final AppText? text = iconOnly
        ? null
        : AppText(
            label!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            bold: emphasizeLabel,
          );

    final Widget content = busy
        ? AppSpinner(color: foreground)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon, size: iconSize),
              if (icon != null && text != null)
                small ? AppSpacing.gapXs : AppSpacing.gapSm,
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
      style:
          FilledButton.styleFrom(
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
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.standard,
          ).copyWith(
            // Keyboard focus: a 2 px accent ring just outside the fill, the same
            // ring `AppFocusRing` draws around rows.
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? BorderSide(
                      color: scheme.accent,
                      width: 2,
                      strokeAlign: BorderSide.strokeAlignOutside,
                    )
                  : style == AppButtonStyle.accent
                  ? BorderSide(color: scheme.outline)
                  : style == AppButtonStyle.outline
                  ? BorderSide(color: scheme.outlineVariant)
                  : style == AppButtonStyle.danger
                  ? BorderSide(color: scheme.danger.withValues(alpha: 0.5))
                  : null,
            ),
          ),
      child: content,
    );

    if (tooltip == null) return button;
    if (!showTooltip) {
      return MergeSemantics(
        child: Semantics(label: tooltip, child: button),
      );
    }
    return Tooltip(message: tooltip!, child: button);
  }
}
