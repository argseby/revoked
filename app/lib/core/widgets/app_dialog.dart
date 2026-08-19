import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_button.dart';

/// The app's only dialog. Resolves to `true` when confirmed, `false` when
/// dismissed — a hand-rolled [AlertDialog] is how nine screens ended up with
/// nine different button orders and three different words for "cancel".
///
/// Pass [cancelLabel] as null for a dialog that only reports something.
Future<bool> showAppDialog({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  IconData? icon,
  Color? iconColor,
  String confirmLabel = 'Confirm',
  String? cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    // Same reason as the sheet: the dialog carries the page's own color, so
    // the scrim is the only thing that would make the page look grey.
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.2),
    builder: (ctx) => AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.allLg),
      title: icon == null
          ? Text(title).header
          : Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                AppSpacing.gapSm,
                Expanded(child: Text(title).header),
              ],
            ),
      content: (message == null && content == null)
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message != null) Text(message),
                if (message != null && content != null) AppSpacing.gapMd,
                ?content,
              ],
            ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      actions: [
        if (cancelLabel != null)
          AppButton(
            label: cancelLabel,
            style: AppButtonStyle.accent,
            onTap: () => Navigator.of(ctx).pop(false),
          ),
        AppButton(
          label: confirmLabel,
          style: destructive
              ? AppButtonStyle.destructive
              : AppButtonStyle.primary,
          onTap: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}
