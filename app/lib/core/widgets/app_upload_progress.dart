import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/files/file_saver.dart';
import 'package:revoked_app/core/widgets/app_button.dart';

/// The app's only determinate progress indicator: a file transfer in flight,
/// with the byte count and a way out. [AppSpinner] covers the case where there
/// is nothing to count.
///
/// A large upload with no byte counter is indistinguishable from a hung one,
/// which is most of why a slow transfer gets reported as a broken server.
class AppUploadProgress extends StatelessWidget {
  final int sent;
  final int total;
  final VoidCallback onCancel;

  const AppUploadProgress({
    super.key,
    required this.sent,
    required this.total,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = total <= 0 ? 0.0 : (sent / total).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: AppRadius.allPill,
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${formatBytes(sent)} of ${formatBytes(total)} · '
                '${(fraction * 100).round()}%',
              ).small.muted,
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppButton(
          icon: AppIcons.x,
          tooltip: 'Cancel upload',
          size: AppButtonSize.small,
          style: AppButtonStyle.destructive,
          onTap: onCancel,
        ),
      ],
    );
  }
}
