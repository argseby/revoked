import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/invite_trust_summary.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// Shows what an invite grants and lets the recipient accept it.
///
/// The probe is deliberately readable before any decision: the workspace, who
/// invited you, and every permission in plain language. Accepting needs a
/// signed-in account, so the workspace knows who joined.
class InviteAcceptScreen extends StatefulWidget {
  final String token;

  /// host[:port] the invite says it lives on; null = the signed-in server.
  final String? origin;

  const InviteAcceptScreen({super.key, required this.token, this.origin});

  @override
  State<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

class _InviteAcceptScreenState extends State<InviteAcceptScreen> {
  @override
  void initState() {
    super.initState();
    if (Stores.api.isOwnOrigin(widget.origin)) _probe();
  }

  Future<void> _probe() => Stores.invites.previewInvite(widget.token);

  Future<void> _accept() async {
    if (!Stores.auth.isAuthenticated) {
      context.go(AppRoutes.login);
      return;
    }

    Stores.invites.startAccepting();
    try {
      await Stores.invites.accept(widget.token);
      // Joining changes what this account can reach, so the workspace-scoped
      // stores have to be refetched rather than left showing the old context.
      await Stores.auth.initialize();
      await Stores.workspaceContext.reload();
      if (!mounted) return;
      AppToast.success(
        context,
        'You joined ${Stores.invites.acceptPreview?.workspaceName ?? 'the workspace'}.',
      );
      context.go(AppRoutes.vault);
    } catch (e) {
      if (!mounted) return;
      final err = AppErrorMessage.fromException(e);
      Stores.invites.failAccepting(err);
      // A terminal error replaces the page; anything else is transient and
      // only worth a toast.
      if (!err.isTerminal) AppToast.error(context, err.description);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workspace invite')),
      body: SafeArea(child: Observer(builder: (_) => _body(context))),
    );
  }

  Widget _body(BuildContext context) {
    // Membership is an account on one server. An invite minted elsewhere
    // cannot be accepted by this session - the account does not exist there.
    if (!Stores.api.isOwnOrigin(widget.origin)) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.screenH(context)),
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  AppIcons.server,
                  size: 40,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                AppSpacing.gapLg,
                const Text('This invite belongs to another server').header,
                AppSpacing.gapSm,
                Text(
                  'It was created on ${widget.origin}, but you are signed '
                  'into ${Stores.api.originAuthority}. Switch servers on '
                  'the login screen and open the invite again.',
                  textAlign: TextAlign.center,
                ).muted.small,
              ],
            ),
          ),
        ),
      );
    }
    if (Stores.invites.isPreviewing) return const Center(child: AppSpinner());

    final error = Stores.invites.acceptError;
    if (error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.screenH(context)),
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  AppIcons.shieldLock,
                  size: 40,
                  color: Theme.of(context).colorScheme.error,
                ),
                AppSpacing.gapMd,
                Text(error.title).header,
                AppSpacing.gapSm,
                Text(
                  error.description,
                  textAlign: TextAlign.center,
                ).muted.small,
                AppSpacing.gapLg,
                AppButton(
                  label: 'Back',
                  onTap: () => context.go(AppRoutes.vault),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final preview = Stores.invites.acceptPreview!;
    final signedIn = Stores.auth.isAuthenticated;

    return ListView(
      padding: EdgeInsets.all(AppSpacing.screenH(context)),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    AppIcons.personWorkspace,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(preview.workspaceName).header),
                ],
              ),

              if (preview.label.isNotEmpty) ...[
                AppSpacing.gapSm,
                Text(preview.label).muted.small,
              ],
            ],
          ),
        ),

        AppSpacing.gapLg,
        InviteTrustSummary(preview: preview),

        AppSpacing.gapLg,
        Text('You will be able to'),
        AppSpacing.gapSm,

        ...preview.permissions.map(
          (p) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    p.destructive ? AppIcons.shieldLock : AppIcons.shieldCheck,
                    size: 20,
                    color: p.destructive
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(p.label)),
                            if (p.destructive) ...[
                              const SizedBox(width: AppSpacing.sm),
                              AppBadge(
                                label: 'Sensitive',
                                variant: AppBadgeVariant.destructive,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(p.description).muted.small,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        if (preview.grantsDestructive) ...[
          AppSpacing.gapMd,
          AppAlert(
            destructive: true,
            title: const Text('This invite includes control over access'),
            content: Text(
              'You would be able to change who else can reach this workspace.',
            ).small,
          ),
        ],

        AppSpacing.gapLg,
        if (!signedIn)
          AppAlert(
            title: const Text('Sign in to accept'),
            content: Text(
              'An invite is tied to an account, so the workspace knows who joined.',
            ).small,
          ),
        AppSpacing.gapMd,
        AppButton(
          label: Stores.invites.isAccepting
              ? 'Joining…'
              : signedIn
              ? 'Join ${preview.workspaceName}'
              : 'Sign in to accept',
          onTap: Stores.invites.isAccepting ? null : _accept,
        ),
        AppSpacing.gapSm,
        AppButton(
          label: 'Not now',
          onTap: () => context.go(AppRoutes.vault),
          style: AppButtonStyle.accent,
        ),
      ],
    );
  }
}
