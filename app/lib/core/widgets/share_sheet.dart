import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/widgets/api_access_sheet.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:share_plus/share_plus.dart';

bool get _hasShareSheet => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Everything one link can be handed over as. A share is one act with one
/// button; which carrier the recipient needs — a URL, a scan, an API call — is
/// a detail inside it, not three separate menu entries.
Future<void> showShareSheet({
  required BuildContext context,
  required String slug,
  required String title,
  required bool isRequest,
  ApiAccessTarget? apiTarget,
}) {
  final origin = Stores.api.originAuthority;
  // A request collects data, so it has no browser page and gets no web link:
  // the one surface that accepts input is the app, which verifies the server
  // it is talking to before anything is typed.
  final webUrl = isRequest ? null : '${Stores.api.baseUrl}/s/$slug';
  final appUrl = isRequest
      ? DeepLinks.request(slug, origin: origin)
      : DeepLinks.share(slug, origin: origin);

  return showAppSheet(
    context: context,
    builder: (sheetContext) => _ShareSheet(
      title: title,
      webUrl: webUrl,
      appUrl: appUrl,
      apiTarget: apiTarget,
    ),
  );
}

class _ShareSheet extends StatelessWidget {
  final String title;
  final String? webUrl;
  final String appUrl;
  final ApiAccessTarget? apiTarget;

  const _ShareSheet({
    required this.title,
    required this.webUrl,
    required this.appUrl,
    required this.apiTarget,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primaryUrl = webUrl ?? appUrl;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xxs,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title).header,
                const SizedBox(height: AppSpacing.xxs),
                const Text(
                  'Anyone with the link can read what it grants, until you '
                  'pause or revoke it.',
                ).muted.small,
              ],
            ),
          ),
          const AppDivider(),

          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AppRadius.allMd,
                    ),
                    // The QR carries the web link: a phone camera opens it
                    // without the app installed, which is the whole point of
                    // pointing someone at a page.
                    child: QrImageView(
                      data: primaryUrl,
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                if (webUrl != null) ...[
                  _LinkRow(
                    icon: AppIcons.globe,
                    label: 'Web link',
                    hint: 'Opens in any browser — no app needed.',
                    url: webUrl!,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                _LinkRow(
                  icon: AppIcons.shieldCheck,
                  label: 'App link',
                  hint: webUrl == null
                      ? 'A request is only answered in the app, where the '
                            'server is verified before anything is typed.'
                      : 'Opens in revoked, which verifies the server first.',
                  url: appUrl,
                ),

                if (apiTarget != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const AppDivider(),
                  const SizedBox(height: AppSpacing.md),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          AppIcons.server,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        const Expanded(
                          child: Text(
                            'Pull this into a script or a spreadsheet.',
                          ),
                        ),
                        AppButton(
                          label: 'Web & API',
                          style: AppButtonStyle.accent,
                          size: AppButtonSize.small,
                          onTap: () {
                            Navigator.of(context).pop();
                            showApiAccessSheet(context, target: apiTarget!);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const AppDivider(),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Close',
                    style: AppButtonStyle.accent,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    icon: _hasShareSheet ? AppIcons.share : AppIcons.copy,
                    label: _hasShareSheet ? 'Share' : 'Copy link',
                    onTap: () async {
                      if (_hasShareSheet) {
                        await SharePlus.instance.share(
                          ShareParams(text: primaryUrl),
                        );
                        return;
                      }
                      await Clipboard.setData(ClipboardData(text: primaryUrl));
                      if (context.mounted) {
                        AppToast.success(context, 'Copied link');
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final String url;

  const _LinkRow({
    required this.icon,
    required this.label,
    required this.hint,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(label).small),
              AppButton(
                icon: AppIcons.copy,
                tooltip: 'Copy $label',
                style: AppButtonStyle.accent,
                size: AppButtonSize.small,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) {
                    AppToast.success(context, 'Copied $label');
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: AppRadius.allSm,
            ),
            child: Text(url, maxLines: 2).mono.small.selectable,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(hint).muted.small,
        ],
      ),
    );
  }
}
