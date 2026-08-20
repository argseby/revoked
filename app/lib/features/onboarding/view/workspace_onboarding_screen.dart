import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/onboarding/store/onboarding_store.dart';

/// First run: an account has no workspace until it either creates one or joins
/// one, so this asks which — rather than silently provisioning a workspace the
/// person may not want and then having them join a second one anyway.
class WorkspaceOnboardingScreen extends StatelessWidget {
  const WorkspaceOnboardingScreen({super.key});

  OnboardingStore get _store => Stores.onboarding;

  /// Accepts either a bare token or a full `revoked://i/<token>` link.
  String get _token {
    final raw = _store.keyController.text.trim();
    final location = DeepLinks.locationFor(Uri.tryParse(raw) ?? Uri());
    if (location != null && location.startsWith('/i/')) {
      return location.substring(3);
    }
    return raw;
  }

  Future<void> _createWorkspace(BuildContext context) async {
    final name = _store.nameController.text.trim();
    if (name.isEmpty) {
      _store.fail('Give your workspace a name.');
      return;
    }

    _store.startBusy();

    final auth = Stores.auth;
    final ok = await Stores.settings.createWorkspace(
      name: name,
      slug: _slugify(name),

      userId: auth.userId,
    );
    if (!ok) {
      _store.stopBusy(
        Stores.settings.errorMessage ?? 'Could not create the workspace.',
      );
      return;
    }

    _store.nameController.clear();
    _store.isBusy = false;

    if (!context.mounted) return;
    await _adoptFirstWorkspace(context);
  }

  Future<void> _peekInvite() async {
    if (_token.isEmpty) return;
    _store.startPreview();
    try {
      final preview = await Stores.invites.preview(_token);
      _store.finishPreview(result: preview);
    } catch (e) {
      _store.finishPreview(
        message: AppErrorMessage.fromException(e).description,
      );
    }
  }

  Future<void> _joinWorkspace(BuildContext context) async {
    if (_token.isEmpty) {
      _store.fail('Paste the invite key you were given.');
      return;
    }

    _store.startBusy();
    try {
      await Stores.invites.accept(_token);
      if (!context.mounted) return;
      await _adoptFirstWorkspace(context);
    } catch (e) {
      _store.stopBusy(AppErrorMessage.fromException(e).description);
    }
  }

  /// Re-reads the session so the new membership becomes the active context,
  /// then gives the account a signing identity now that one can be scoped to a
  /// workspace, and finally loads the workspace's data.
  Future<void> _adoptFirstWorkspace(BuildContext context) async {
    final auth = Stores.auth;
    await auth.initialize();
    await auth.ensureIdentity(name: _store.identityNameController.text);
    await Stores.workspaceContext.reload();
    if (!context.mounted) return;
    AppToast.success(context, 'You are all set.');
    context.go(AppRoutes.vault);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppText('Set up your workspace', header: true),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(AppSpacing.screenH(context)),
          children: [
            Text(
              'A workspace holds your vault, shares and requests. '
              'Start your own, or join one you have been invited to.',
            ).muted.small,
            AppSpacing.gapLg,
            if (_store.error != null) ...[
              AppAlert(
                destructive: true,
                title: const Text('That did not work'),
                content: Text(_store.error!).small,
              ),
              AppSpacing.gapMd,
            ],
            if (_store.choice == OnboardingChoice.undecided)
              ..._chooser(context),
            if (_store.choice == OnboardingChoice.create)
              ..._createForm(context),
            if (_store.choice == OnboardingChoice.join) ..._joinForm(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _chooser(BuildContext context) => [
    _ChoiceCard(
      icon: AppIcons.personWorkspace,
      title: 'Create a workspace',
      subtitle: 'Start fresh with your own vault.',
      onTap: () => _store.choose(OnboardingChoice.create),
    ),
    AppSpacing.gapMd,
    _ChoiceCard(
      icon: AppIcons.key,
      title: 'Join with an invite',
      subtitle: 'Paste the key someone shared with you.',
      onTap: () => _store.choose(OnboardingChoice.join),
    ),
  ];

  List<Widget> _createForm(BuildContext context) => [
    AppTextField(
      controller: _store.nameController,
      label: 'Workspace name',
      hint: 'e.g. Acme, or your own name',
    ),
    AppSpacing.gapMd,
    AppTextField(
      controller: _store.identityNameController,
      label: 'Your name',
      hint: 'e.g. Ada Lovelace',
    ),
    AppSpacing.gapXxs,
    const Text(
      'This is the name on your signing identity — everyone you share with or '
      'request from sees it.',
    ).muted.small,
    AppSpacing.gapLg,

    Row(
      children: [
        Expanded(child: _backButton()),
        AppSpacing.gapSm,

        Expanded(
          child: AppButton(
            label: _store.isBusy ? 'Creating…' : 'Create workspace',
            onTap:
                _store.isBusy ||
                    (_store.nameController.text.isEmpty ||
                        _store.identityNameController.text.isEmpty)
                ? null
                : () => _createWorkspace(context),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _joinForm(BuildContext context) => [
    AppTextField(
      controller: _store.keyController,
      label: 'Invite key',
      hint: 'revoked://i/… or the key itself',
    ),
    AppSpacing.gapSm,
    AppButton(
      label: _store.isPreviewing ? 'Checking…' : 'Check this invite',
      onTap: _store.isPreviewing || _store.keyController.text.isEmpty
          ? null
          : _peekInvite,
      icon: AppIcons.shieldCheck,
      style: AppButtonStyle.accent,
    ),
    AppSpacing.gapMd,
    if (_store.isPreviewing) ...[
      AppSpacing.gapMd,
      const Center(child: AppSpinner()),
    ],
    if (_store.preview != null) ...[
      AppSpacing.gapMd,
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_store.preview!.workspaceName),
            if (_store.preview!.invitedBy != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text('Invited by ${_store.preview!.invitedBy}').muted.small,
            ],
            AppSpacing.gapSm,
            for (final permission in _store.preview!.permissions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Text('• ${permission.label}').muted.small,
              ),
          ],
        ),
      ),
    ],
    Row(
      children: [
        Expanded(child: _backButton()),
        AppSpacing.gapLg,

        Expanded(
          child: AppButton(
            label: _store.isBusy ? 'Joining…' : 'Join workspace',
            onTap: _store.isBusy || _store.keyController.text.isEmpty
                ? null
                : () => _joinWorkspace(context),
          ),
        ),
      ],
    ),
  ];

  Widget _backButton() => AppButton(
    label: 'Back',
    onTap: _store.isBusy ? null : _store.restart,
    style: AppButtonStyle.accent,
  );
}

/// The server requires a unique slug, so a suffix is added rather than risking
/// a collision on a common workspace name.
String _slugify(String value) {
  final base = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  return base.isEmpty ? 'workspace-$suffix' : '$base-$suffix';
}

class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.allLg,
      child: AppCard(
        child: Row(
          children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitle).muted.small,
                ],
              ),
            ),
            Icon(
              AppIcons.chevronRight,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
