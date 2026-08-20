import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:share_plus/share_plus.dart';

/// Whether the platform share sheet is worth offering — on desktop the copy
/// button already is the share story.
bool get _hasShareSheet => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Shows [link] as a QR code for another device to scan off the screen,
/// with copy — and, on mobile, the platform share action.
Future<void> showQrSheet({
  required BuildContext context,
  required String title,
  required String link,
}) {
  return showAppSheet(
    context: context,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxs,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title).header,
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            'Scan it with the Revoked app on another device.',
          ).muted.small,
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: const BoxDecoration(
                // A QR module must be dark-on-light for cameras, whatever the
                // app theme says — the one place a fixed color is the point.
                color: Color(0xFFFFFFFF),
                borderRadius: AppRadius.allMd,
              ),
              child: QrImageView(
                data: link,
                version: QrVersions.auto,
                size: 220,
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF000000),
                ),
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF000000),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(child: Text(link).mono.small.muted),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  icon: AppIcons.copy,
                  label: 'Copy link',
                  style: AppButtonStyle.accent,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: link));
                    AppToast.success(sheetContext, 'Link copied');
                  },
                ),
              ),
              if (_hasShareSheet) ...[
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    icon: AppIcons.share,
                    label: 'Share',
                    onTap: () =>
                        SharePlus.instance.share(ShareParams(text: link)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}
