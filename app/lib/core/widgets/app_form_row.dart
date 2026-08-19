import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_switch.dart';

/// A tappable settings-style summary row used by the create drawers.
///
/// Shows an icon, a label, and the field's current value underneath. Tapping
/// opens a focused editor (sub-sheet, picker, date picker, …). Optional fields
/// can pass [onClear] to expose a clear (×) affordance once a value is set.
class AppFormRow extends StatelessWidget {
  final IconData icon;
  final String label;

  /// The summary text shown under the label (current value, or a placeholder
  /// like "Not set" / "Required").
  final String valueText;

  /// When true [valueText] is a placeholder (renders muted; clear is hidden).
  final bool isPlaceholder;

  /// When true [valueText] renders in the error color.
  final bool isError;

  /// If provided (and a value is set), shows a clear button before the chevron.
  final VoidCallback? onClear;

  final VoidCallback onTap;

  const AppFormRow({
    super.key,
    required this.icon,
    required this.label,
    required this.valueText,
    required this.onTap,
    this.isPlaceholder = false,
    this.isError = false,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showClear = onClear != null && !isPlaceholder;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      leading: Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(label),
      subtitle: Text(
        valueText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isError
              ? scheme.error
              : (isPlaceholder ? scheme.onSurfaceVariant : scheme.onSurface),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showClear)
            AppButton(
              icon: AppIcons.x,
              style: AppButtonStyle.accent,
              tooltip: 'Clear',
              onTap: onClear,
            ),
          Icon(AppIcons.chevronRight, size: 20, color: scheme.onSurfaceVariant),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// A boolean setting rendered as a row with a trailing switch — no sub-sheet.
/// Companion to [AppFormRow]; the app's only labelled toggle.
class AppFormToggleRow extends StatelessWidget {
  /// Omitted for a toggle inside already-labelled content, where a second
  /// glyph would just be noise.
  final IconData? icon;

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Aligns the row with a create drawer's other rows. Off when the toggle
  /// sits inside a container that already provides the padding.
  final bool inset;

  const AppFormToggleRow({
    super.key,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
    this.inset = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: inset
          ? const EdgeInsets.symmetric(horizontal: AppSpacing.xl)
          : EdgeInsets.zero,
      leading: icon == null ? null : Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(label),
      subtitle: Text(subtitle).muted.small,
      trailing: AppSwitch(value: value, onChanged: onChanged),
      onTap: onChanged == null ? null : () => onChanged!(!value),
    );
  }
}

/// A small uppercase section label grouping rows within a create drawer.
class AppFormSectionHeader extends StatelessWidget {
  final String text;
  const AppFormSectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxs,
      ),
      child: Text(text.toUpperCase()).muted.small,
    );
  }
}
