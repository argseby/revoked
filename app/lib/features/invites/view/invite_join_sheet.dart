import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/invite_trust_summary.dart';

/// Joins a workspace from an invite key.
///
/// The key is checked before it is spent, and never silently: what the invite
/// grants and who the server says sent it are on screen before Join is
/// reachable at all. That is the same order the onboarding wizard uses, and
/// both render one [InviteTrustSummary] — anyone can host this service, so the
/// domain behind an invite is the only part of it that is worth anything.
Future<void> showInviteJoinSheet({required BuildContext context}) {
  return showAppSheet(
    context: context,
    builder: (_) => const _InviteJoinSheet(),
  );
}

class _InviteJoinSheet extends StatefulWidget {
  const _InviteJoinSheet();

  @override
  State<_InviteJoinSheet> createState() => _InviteJoinSheetState();
}

class _InviteJoinSheetState extends State<_InviteJoinSheet> {
  @override
  void initState() {
    super.initState();
    Stores.invites.resetJoinDraft();
  }

  Future<void> _check() async {
    await Stores.invites.previewInvite(Stores.invites.joinToken);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    Stores.invites.joinKeyController.text = text;
    await _check();
  }

  Future<void> _join() async {
    final store = Stores.invites;
    store.startAccepting();
    try {
      await store.accept(store.joinToken);
      // Joining changes what this account can reach, so the workspace-scoped
      // stores have to be refetched rather than left showing the old context.
      await Stores.auth.initialize();
      await Stores.workspaceContext.reload();
      if (!mounted) return;
      final name = store.acceptPreview?.workspaceName ?? 'the workspace';
      Navigator.of(context).pop();
      AppToast.success(context, 'You joined $name.');
    } catch (e) {
      if (!mounted) return;
      final err = AppErrorMessage.fromException(e);
      store.failAccepting(err);
      AppToast.error(context, err.description);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final store = Stores.invites;
    final preview = store.acceptPreview;

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
                const Text('Join a workspace').header,
                const SizedBox(height: AppSpacing.xxs),
                const Text(
                  'Paste the key you were given. Nothing is spent until you '
                  'have seen what it grants.',
                ).muted.small,
              ],
            ),
          ),
          const AppDivider(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    controller: store.joinKeyController,
                    label: 'Invite key',
                    hint: 'revoked://i/… or the key itself',
                    mono: true,
                    autofocus: true,
                    onSubmitted: (_) => _check(),
                    trailing: AppButton(
                      icon: AppIcons.copy,
                      tooltip: 'Paste from clipboard',
                      style: AppButtonStyle.accent,
                      size: AppButtonSize.small,
                      onTap: _pasteFromClipboard,
                    ),
                  ),
                  AppSpacing.gapSm,
                  AppButton(
                    icon: AppIcons.key,
                    label: store.isPreviewing ? 'Checking…' : 'Check this key',
                    style: AppButtonStyle.accent,
                    busy: store.isPreviewing,
                    onTap: store.joinToken.isEmpty || store.isPreviewing
                        ? null
                        : _check,
                  ),
                  if (store.acceptError != null) ...[
                    AppSpacing.gapSm,
                    AppErrorText(store.acceptError!.description),
                  ],
                  if (preview != null) ...[
                    AppSpacing.gapLg,
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(preview.workspaceName).header,
                          if (preview.label.isNotEmpty) ...[
                            AppSpacing.gapXxs,
                            Text(preview.label).muted.small,
                          ],
                          AppSpacing.gapSm,
                          const Text('You will be able to').muted.small,
                          AppSpacing.gapXxs,
                          for (final permission in preview.permissions)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.xxs,
                              ),
                              child: Text('• ${permission.label}').muted.small,
                            ),
                        ],
                      ),
                    ),
                    AppSpacing.gapSm,
                    InviteTrustSummary(preview: preview),
                  ],
                ],
              ),
            ),
          ),
          const AppDivider(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Cancel',
                    style: AppButtonStyle.accent,
                    onTap: store.isAccepting
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ),
                AppSpacing.gapMd,
                Expanded(
                  child: AppButton(
                    label: store.isAccepting ? 'Joining…' : 'Join workspace',
                    busy: store.isAccepting,
                    // Unreachable until the key has been checked: joining is
                    // the decision, and it should not be possible to make it
                    // without having seen what is being joined.
                    onTap: preview == null || store.isAccepting ? null : _join,
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
