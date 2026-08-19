import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';

/// Shown in place of a list that failed to load. Sits at the top of the empty
/// space, where the content would have started — a failure centred in the
/// viewport reads as a state of the whole app rather than of this list.
class AppLoadError extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const AppLoadError({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAlert(
            destructive: true,
            leading: const Icon(AppIcons.exclamation),
            title: Text(title),
            content: Text(message),
          ),
          if (onRetry != null) ...[
            AppSpacing.gapMd,
            AppButton(
              label: 'Retry',
              style: AppButtonStyle.accent,
              onTap: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
