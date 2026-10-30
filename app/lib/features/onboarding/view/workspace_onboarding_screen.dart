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
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/features/auth/view/round_trip.dart';

/// First run: an account has no workspace until it either creates one or joins
/// one. Creating comes first and asks one thing, the name others see; the
/// workspace is called "Personal" unless renamed here, so someone arriving
/// from a tool is one tap away from where they were going. Joining with an
/// invite key is a link below it.
///
/// Right after creating an account this is the last of its steps, and says
/// so with the same counter the passkey page showed.
class WorkspaceOnboardingScreen extends StatefulWidget {
  const WorkspaceOnboardingScreen({super.key});

  @override
  State<WorkspaceOnboardingScreen> createState() =>
      _WorkspaceOnboardingScreenState();
}

class _WorkspaceOnboardingScreenState extends State<WorkspaceOnboardingScreen> {
  OnboardingStore get _store => Stores.onboarding;

  /// Whether the workspace name is open for editing; it starts as a line.
  final Local<bool> _renaming = Local(false);

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
        Stores.settings.errorMessage ??
            'Couldn\'t create your workspace. Try again.',
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
      if (next == null) AppToast.success(context, 'You\'re in.');
      context.go(next ?? AppRoutes.overview);
    }
    _store.finish();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final next = ResumeLocation.describe();
    final creating = _store.choice == OnboardingChoice.create;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(AppSpacing.screenH(context)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (Stores.auth.createdAccount && creating) ...[
                    const RoundTrip(at: 2),
                    AppSpacing.gapXl,
                  ],
                  Semantics(
                    header: true,
                    child: AppText(
                      creating ? 'Your name' : 'Join a workspace',
                      textAlign: TextAlign.center,
                    ).title,
                  ),
                  AppSpacing.gapSm,
                  AppText(
                    creating
                        ? 'People see this name when you share with them or '
                              'ask them for something.'
                        : 'Paste your invite key. You\'ll see who sent it and '
                              'what it lets you do before you join.',
                    textAlign: TextAlign.center,
                  ).muted,
                  AppSpacing.gapXl,
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
                      title: const Text('That didn\'t work'),
                      content: Text(_store.error!).small,
                    ),
                    AppSpacing.gapMd,
                  ],
                  if (creating) ..._createForm(),
                  if (_store.choice == OnboardingChoice.join) ..._joinForm(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _createForm() => [
    AppTextField(
      controller: _store.identityNameController,
      label: 'Name',
      hint: 'e.g. Ada Lovelace',
      autofocus: true,
    ),
    AppSpacing.gapXxs,
    const Text('Taken from your email. You can change it later.').muted.small,
    AppSpacing.gapLg,
    if (_renaming.value)
      AppTextField(
        controller: _store.nameController,
        label: 'Workspace name',
        hint: 'e.g. Personal, Family or Acme',
      )
    else
      Row(
        children: [
          const Text('Workspace').muted,
          AppSpacing.gapSm,
          Expanded(
            child: AppText(
              _store.nameController.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ).bold,
          ),
          AppButton(
            icon: AppIcons.pencil,
            label: 'Rename',
            style: AppButtonStyle.ghost,
            size: AppButtonSize.small,
            onTap: _store.isBusy ? null : () => _renaming.value = true,
          ),
        ],
      ),
    AppSpacing.gapXxs,
    const Text('Your vault, links and requests live here.').muted.small,
    AppSpacing.gapXl,
    AppButton(
      icon: AppIcons.check,
      label: _store.isBusy ? 'Setting up…' : 'Finish',
      onTap:
          _store.isBusy ||
              _store.nameController.text.trim().isEmpty ||
              _store.identityNameController.text.trim().isEmpty
          ? null
          : _createWorkspace,
    ),
    AppSpacing.gapLg,
    Center(
      child: AppButton(
        icon: AppIcons.key,
        label: 'Use an invite key',
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
      label: _store.isPreviewing ? 'Checking…' : 'Check invite',
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
