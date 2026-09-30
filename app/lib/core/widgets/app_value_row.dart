import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/utils/value_kind.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// The icon and tint a kind of value is shown with.
(IconData, Color, Color) valueKindStyle(ColorScheme scheme, ValueKind kind) {
  (IconData, Color) pick() => switch (kind) {
    ValueKind.phone => (AppIcons.phone, scheme.success),
    ValueKind.email => (AppIcons.mail, scheme.primary),
    ValueKind.url => (AppIcons.globe, scheme.tertiary),
    ValueKind.date => (AppIcons.calendar, scheme.warning),
    ValueKind.number => (AppIcons.hash, scheme.onSurfaceVariant),
    ValueKind.boolean => (AppIcons.toggleOn, scheme.onSurfaceVariant),
    ValueKind.person => (AppIcons.person, scheme.onSurfaceVariant),
    ValueKind.place => (AppIcons.place, scheme.onSurfaceVariant),
    ValueKind.work => (AppIcons.building, scheme.onSurfaceVariant),
    ValueKind.text => (AppIcons.notes, scheme.onSurfaceVariant),
    ValueKind.pdf => (AppIcons.filePdf, scheme.error),
    ValueKind.image => (AppIcons.image, scheme.primary),
    ValueKind.file => (AppIcons.fileEarmark, scheme.onSurfaceVariant),
  };
  final (icon, color) = pick();
  final neutral = color == scheme.onSurfaceVariant;
  return (
    icon,
    color,
    neutral ? scheme.surfaceContainerHighest : color.withValues(alpha: 0.14),
  );
}

/// One shared value on an opened link: what it is, the value itself, and
/// what can be done with it.
///
///   [📞]  Phone
///         +49 170 1234567                         ( Call ) [⧉]
///
/// Every value can be copied; a phone number can be called, an email address
/// written to and a web address opened. A file passes its own buttons in
/// [actions] instead.
class AppValueRow extends StatelessWidget {
  final String label;

  /// The value as stored — what Copy copies.
  final String value;
  final ValueKind kind;

  /// Shown in place of the value, for a file: "payslip.pdf · 239 KB".
  final String? display;

  /// Null for a value that is never masked; otherwise whether it is masked
  /// now, with [onToggleMask] to change that.
  final bool? masked;
  final VoidCallback? onToggleMask;

  /// Replaces the value's own actions — a file's View and Download.
  final List<Widget>? actions;

  const AppValueRow({
    super.key,
    required this.label,
    required this.value,
    required this.kind,
    this.display,
    this.masked,
    this.onToggleMask,
    this.actions,
  });

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    final shown = value.length > 32 ? '${value.substring(0, 32)}…' : value;
    AppToast.success(
      context,
      masked == null ? 'Copied “$shown”' : 'Copied $label',
    );
  }

  Future<void> _launch(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      AppToast.error(context, 'No app on this device can open this');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, tile) = valueKindStyle(scheme, kind);
    final hidden = masked ?? false;
    final text = hidden
        ? '••••••••••••'
        : display ?? (value.trim().isEmpty ? '—' : displayValue(kind, value));
    final uri = hidden || value.trim().isEmpty ? null : actionUri(kind, value);

    final buttons = <Widget>[
      if (uri != null && kind == ValueKind.phone)
        AppButton(
          icon: AppIcons.phone,
          label: 'Call',
          style: AppButtonStyle.accent,
          size: AppButtonSize.small,
          onTap: () => _launch(context, uri),
        ),
      if (uri != null && kind == ValueKind.email)
        AppButton(
          icon: AppIcons.send,
          tooltip: 'Write an email',
          style: AppButtonStyle.accent,
          size: AppButtonSize.small,
          onTap: () => _launch(context, uri),
        ),
      if (uri != null && kind == ValueKind.url)
        AppButton(
          icon: AppIcons.boxArrowUpRight,
          tooltip: 'Open in the browser',
          style: AppButtonStyle.accent,
          size: AppButtonSize.small,
          onTap: () => _launch(context, uri),
        ),
      if (masked != null && onToggleMask != null)
        AppButton(
          icon: hidden ? AppIcons.eye : AppIcons.eyeSlash,
          tooltip: hidden ? 'Show value' : 'Hide value',
          style: AppButtonStyle.accent,
          size: AppButtonSize.small,
          onTap: onToggleMask,
        ),
      if (value.trim().isNotEmpty)
        AppButton(
          icon: AppIcons.copy,
          tooltip: 'Copy $label',
          style: AppButtonStyle.accent,
          size: AppButtonSize.small,
          onTap: () => _copy(context),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tile,
              borderRadius: AppRadius.allMd,
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          AppSpacing.gapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ).small.muted,
                const SizedBox(height: 2),
                SelectableText(
                  text,
                  style: const TextStyle(fontSize: 15, height: 1.35),
                ),
              ],
            ),
          ),
          AppSpacing.gapSm,
          for (final b in actions ?? buttons) ...[b, AppSpacing.gapXs],
        ],
      ),
    );
  }
}
