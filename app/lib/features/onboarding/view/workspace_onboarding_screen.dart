import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/router/resume_location.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/invite_trust_summary.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/onboarding/store/onboarding_store.dart';

/// First run: an account has no workspace until it either creates one or joins
/// one. Creating comes first, with both names already suggested, so someone
/// arriving from a tool is one tap away from where they were going; joining
/// with an invite key is a link below it.
class WorkspaceOnboardingScreen extends StatefulWidget {
  const WorkspaceOnboardingScreen({super.key});

  @override
  State<WorkspaceOnboardingScreen> createState() =>
      _WorkspaceOnboardingScreenState();
}

class _WorkspaceOnboardingScreenState extends State<WorkspaceOnboardingScreen> {
  OnboardingStore get _store => Stores.onboarding;

  String get _token => DeepLinks.inviteTokenFrom(_store.keyController.text);

  @override
  void initState() {
    super.initState();
    _store.prefill(Stores.auth.userEmail);
  }

  Future<void> _createWorkspace() async {
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

    try {
      await _adoptFirstWorkspace();
    } catch (e) {
      _store.stopBusy(AppErrorMessage.fromException(e).description);
    }
  }

  Future<void> _peekInvite() async {
    if (_token.isEmpty) return;
    _store.startPreview();
    try {
      final preview = await Stores.invites.preview(_token);
      _store.finishPreview(result: preview);
      // The same check the accept screen runs. Joining is the moment the
      // decision is actually made, so the domain behind the invite has to be
      // on screen here too, not only on the other route into it.
      await Stores.invites.verifyInviteTrust(preview);
    } catch (e) {
      _store.finishPreview(
        message: AppErrorMessage.fromException(e).description,
      );
    }
  }

  Future<void> _joinWorkspace() async {
    if (_token.isEmpty) {
      _store.fail('Paste the invite key you were given.');
      return;
    }

    _store.startBusy();
    try {
      await Stores.invites.accept(_token);
      await _adoptFirstWorkspace();
    } catch (e) {
      _store.stopBusy(AppErrorMessage.fromException(e).description);
    }
  }

  /// Re-reads the session so the new membership becomes the active context,
  /// then gives the account a signing identity now that one can be scoped to a
  /// workspace, and finally loads the workspace's data.
  ///
  /// Busy throughout: the router leaves this screen alone until then, so a
  /// proposal waiting behind it opens with the identity it signs with.
  Future<void> _adoptFirstWorkspace() async {
    final auth = Stores.auth;
    await auth.initialize();
    await auth.ensureIdentity(name: _store.identityNameController.text);
    await Stores.workspaceContext.reload();
    if (mounted) {
      final next = ResumeLocation.take();
      if (next == null) AppToast.success(context, 'You are all set.');
      context.go(next ?? AppRoutes.vault);
    }
    _store.finish();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final next = ResumeLocation.describe();
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
              'We suggested names below - keep them or change them.',
            ).muted.small,
            AppSpacing.gapLg,
            if (next != null) ...[
              AppAlert(
                leading: const Icon(AppIcons.info),
                title: const Text('One step left'),
                content: Text(next).small,
              ),
              AppSpacing.gapMd,
            ],
            if (_store.error != null) ...[
              AppAlert(
                destructive: true,
                title: const Text('That did not work'),
                content: Text(_store.error!).small,
              ),
              AppSpacing.gapMd,
            ],
            if (_store.choice == OnboardingChoice.create) ..._createForm(),
            if (_store.choice == OnboardingChoice.join) ..._joinForm(),
          ],
        ),
      ),
    );
  }

  List<Widget> _createForm() => [
    AppTextField(
      controller: _store.nameController,
      label: 'Workspace name',
      hint: 'e.g. Personal, Family or Acme',
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
    AppButton(
      icon: AppIcons.plus,
      label: _store.isBusy ? 'Creating…' : 'Create workspace',
      onTap:
          _store.isBusy ||
              _store.nameController.text.trim().isEmpty ||
              _store.identityNameController.text.trim().isEmpty
          ? null
          : _createWorkspace,
    ),
    AppSpacing.gapXl,
    Center(
      child: AppButton(
        icon: AppIcons.key,
        label: 'Join with an invite key instead',
        style: AppButtonStyle.ghost,
        size: AppButtonSize.small,
        onTap: _store.isBusy
            ? null
            : () => _store.choose(OnboardingChoice.join),
      ),
    ),
  ];

  List<Widget> _joinForm() => [
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
            AppSpacing.gapSm,
            for (final permission in _store.preview!.permissions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Text('• ${permission.label}').muted.small,
              ),
          ],
        ),
      ),
      AppSpacing.gapSm,
      InviteTrustSummary(preview: _store.preview!),
      AppSpacing.gapSm,
    ],
    Row(
      children: [
        Expanded(child: _backButton()),
        AppSpacing.gapLg,

        Expanded(
          child: AppButton(
            icon: AppIcons.personWorkspace,
            label: _store.isBusy ? 'Joining…' : 'Join workspace',
            onTap: _store.isBusy || _store.keyController.text.isEmpty
                ? null
                : _joinWorkspace,
          ),
        ),
      ],
    ),
  ];

  Widget _backButton() => AppButton(
    icon: AppIcons.arrowLeft,
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
