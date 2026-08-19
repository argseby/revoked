import 'package:flutter/material.dart';

import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
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

  const InviteAcceptScreen({super.key, required this.token});

  @override
  State<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

class _InviteAcceptScreenState extends State<InviteAcceptScreen> {
  bool _loading = true;
  bool _accepting = false;
  InvitePreview? _preview;
  AppErrorMessage? _error;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await Stores.invites.preview(widget.token);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppErrorMessage.fromException(e);
        _loading = false;
      });
    }
  }

  Future<void> _accept() async {
    if (!Stores.auth.isAuthenticated) {
      context.go(AppRoutes.login);
      return;
    }

    setState(() => _accepting = true);
    try {
      await Stores.invites.accept(widget.token);
      // Joining changes what this account can reach, so the workspace-scoped
      // stores have to be refetched rather than left showing the old context.
      await Stores.auth.initialize();
      await Stores.workspaceContext.reload();
      if (!mounted) return;
      AppToast.success(
        context,
        'You joined ${_preview?.workspaceName ?? 'the workspace'}.',
      );
      context.go(AppRoutes.vault);
    } catch (e) {
      if (!mounted) return;
      final err = AppErrorMessage.fromException(e);
      setState(() {
        _accepting = false;
        if (err.isTerminal) _error = err;
      });
      if (!err.isTerminal) AppToast.error(context, err.description);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workspace invite')),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: AppSpinner());

    final error = _error;
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

    final preview = _preview!;
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
              if (preview.invitedBy != null) ...[
                AppSpacing.gapSm,
                Text('Invited by ${preview.invitedBy}').muted.small,
              ],
              if (preview.label.isNotEmpty) ...[
                AppSpacing.gapSm,
                Text(preview.label).muted.small,
              ],
            ],
          ),
        ),

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
          label: _accepting
              ? 'Joining…'
              : signedIn
              ? 'Join ${preview.workspaceName}'
              : 'Sign in to accept',
          onTap: _accepting ? null : _accept,
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
