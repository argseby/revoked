import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/widgets/api_access_sheet.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_composer.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_qr_code.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/vault/view/record_composer.dart';
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

  /// For a share carrying end-to-end encrypted records: what follows `#k=`
  /// in its address (design/e2ee-sharing.md §3). It never reaches the
  /// server, so it is only ever part of what this sheet hands out.
  String? linkKey,

  /// The share has such a key, and this device can't open it.
  bool keyUnreadable = false,
}) {
  final origin = Stores.api.originAuthority;
  final key = isRequest || linkKey == null ? '' : '#k=$linkKey';
  // A request collects data, so it has no browser page and gets no web link:
  // the one surface that accepts input is the app, which verifies the server
  // it is talking to before anything is typed.
  final webUrl = isRequest ? null : '${Stores.api.baseUrl}/s/$slug$key';
  final appUrl = isRequest
      ? DeepLinks.request(slug, origin: origin)
      : '${DeepLinks.share(slug, origin: origin)}$key';

  return showAppSheet(
    context: context,
    dismissible: true,
    panelWidth: vaultComposerWidth,
    builder: (sheetContext) => _ShareSheet(
      title: title,
      webUrl: webUrl,
      appUrl: appUrl,
      apiTarget: apiTarget,
      invitation: isRequest ? requestInvitation(title, appUrl) : null,
      keyNote: keyUnreadable
          ? 'The key of this link is not readable on this device. The link '
                'below opens everything except the encrypted records.'
          : key.isNotEmpty
          ? 'Encrypted records open only with the whole link, including '
                'the part after #.'
          : null,
    ),
  );
}

/// The message a requester sends along with a request link. Someone who has
/// never heard of revoked gets a `revoked://` link that does nothing without
/// the app, so the message says what it is and what to do first.
String requestInvitation(String title, String appUrl) =>
    '$title\n\n'
    'This request is answered in the Revoked app (https://revoked.link). '
    'Answers remain under the responder\'s control and can be updated or '
    'withdrawn at any time.\n\n'
    '1. Install the Revoked app and sign in.\n'
    '2. Open this link on the same device:\n'
    '$appUrl';

class _ShareSheet extends StatelessWidget {
  final String title;
  final String? webUrl;
  final String appUrl;
  final ApiAccessTarget? apiTarget;

  /// For a request: the message to send with the link.
  final String? invitation;

  /// For a share carrying encrypted records: what its address has to do
  /// with them.
  final String? keyNote;

  const _ShareSheet({
    required this.title,
    required this.webUrl,
    required this.appUrl,
    required this.apiTarget,
    this.invitation,
    this.keyNote,
  });

  @override
  Widget build(BuildContext context) {
    final primaryUrl = webUrl ?? appUrl;
    final isRequest = invitation != null;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: composerMaxHeight(context)),
      child: Column(
        // Fills the side panel, so the footer sits on its bottom edge.
        mainAxisSize: AppSpacing.isNarrow(context)
            ? MainAxisSize.min
            : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VaultComposerHeader(
            title: title,
            area: isRequest ? 'Requests' : 'Shares',
            areaIcon: isRequest ? AppIcons.askFor : AppIcons.share,
            crumb: 'Link',
            subtitle: isRequest
                ? 'Anyone who opens this in the Revoked app can answer until the request is closed.'
                : 'Anyone with the link can view the shared data until the link is paused or revoked.',
            onClose: () => Navigator.of(context).pop(),
          ),
          const AppDivider(),
          Flexible(
            fit: AppSpacing.isNarrow(context) ? FlexFit.loose : FlexFit.tight,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (keyNote != null)
                    AppComposerCard(child: Text(keyNote!).muted.small),
                  // The QR carries the web link: a phone camera opens it
                  // without the app installed, which is the whole point of
                  // pointing someone at a page.
                  AppComposerCard(
                    child: Center(
                      child: AppQrCode(data: primaryUrl, size: 180),
                    ),
                  ),
                  if (webUrl != null)
                    _LinkRow(
                      label: 'Web link',
                      hint: 'Opens in any browser without the app.',
                      url: webUrl!,
                    ),
                  _LinkRow(
                    label: 'App link',
                    hint: webUrl == null
                        ? 'Requests are answered in the app, which verifies the server before any input.'
                        : 'Opens in Revoked, which verifies the server first.',
                    url: appUrl,
                  ),
                  if (invitation != null) _InvitationBox(text: invitation!),
                  if (apiTarget != null)
                    AppComposerCard(
                      description: 'Access from scripts and spreadsheets.',
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: AppButton(
                          icon: AppIcons.globe,
                          label: 'Web & API',
                          style: AppButtonStyle.accent,
                          size: AppButtonSize.small,
                          onTap: () {
                            Navigator.of(context).pop();
                            showApiAccessSheet(context, target: apiTarget!);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const AppDivider(),
          AppComposerFooter(
            label: _hasShareSheet
                ? 'Share'
                : (invitation != null ? 'Copy message' : 'Copy link'),
            icon: _hasShareSheet ? AppIcons.share : AppIcons.copy,
            cancelLabel: 'Close',
            onCancel: () => Navigator.of(context).pop(),
            onSubmit: () async {
              // A request goes out with its explanation; a bare
              // revoked:// link means nothing to someone new.
              final text = invitation ?? primaryUrl;
              if (_hasShareSheet) {
                await SharePlus.instance.share(ShareParams(text: text));
                return;
              }
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                AppToast.success(
                  context,
                  invitation != null ? 'Copied message' : 'Copied link',
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final String label;
  final String hint;
  final String url;

  const _LinkRow({required this.label, required this.hint, required this.url});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppComposerField(
      label: label,
      explanation: hint,
      trailing: AppButton(
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
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: AppRadius.allSm,
        ),
        child: Text(url, maxLines: 1).mono.small.selectable,
      ),
    );
  }
}

/// The invitation a request is sent with, shown as it will arrive.
class _InvitationBox extends StatelessWidget {
  final String text;

  const _InvitationBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppComposerField(
      label: 'Accompanying message',
      explanation: 'Explains to recipients new to Revoked how to get the app.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: AppRadius.allMd,
        ),
        child: Text(text).small.selectable,
      ),
    );
  }
}
