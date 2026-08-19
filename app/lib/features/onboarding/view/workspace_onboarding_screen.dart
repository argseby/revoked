import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// First run: an account has no workspace until it either creates one or joins
/// one, so this asks which — rather than silently provisioning a workspace the
/// person may not want and then having them join a second one anyway.
class WorkspaceOnboardingScreen extends StatefulWidget {
  const WorkspaceOnboardingScreen({super.key});

  @override
  State<WorkspaceOnboardingScreen> createState() =>
      _WorkspaceOnboardingScreenState();
}

enum _Choice { undecided, create, join }

class _WorkspaceOnboardingScreenState extends State<WorkspaceOnboardingScreen> {
  _Choice _choice = _Choice.undecided;

  final _nameCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

  /// What the pasted key grants, shown before it is accepted.
  InvitePreview? _preview;
  bool _previewing = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  /// Accepts either a bare token or a full `revoked://i/<token>` link.
  String get _token {
    final raw = _keyCtrl.text.trim();
    final location = DeepLinks.locationFor(Uri.tryParse(raw) ?? Uri());
    if (location != null && location.startsWith('/i/')) {
      return location.substring(3);
    }
    return raw;
  }

  Future<void> _createWorkspace() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give your workspace a name.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final auth = Stores.auth;
    final ok = await Stores.settings.createWorkspace(
      name: name,
      slug: _slugify(name),
      userId: auth.userId,
    );
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _busy = false;
        _error =
            Stores.settings.errorMessage ?? 'Could not create the workspace.';
      });
      return;
    }

    await _adoptFirstWorkspace();
  }

  Future<void> _peekInvite() async {
    if (_token.isEmpty) return;
    setState(() {
      _previewing = true;
      _error = null;
      _preview = null;
    });
    try {
      final preview = await Stores.invites.preview(_token);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _previewing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _previewing = false;
        _error = AppErrorMessage.fromException(e).description;
      });
    }
  }

  Future<void> _joinWorkspace() async {
    if (_token.isEmpty) {
      setState(() => _error = 'Paste the invite key you were given.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Stores.invites.accept(_token);
      if (!mounted) return;
      await _adoptFirstWorkspace();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppErrorMessage.fromException(e).description;
      });
    }
  }

  /// Re-reads the session so the new membership becomes the active context,
  /// then gives the account a signing identity now that one can be scoped to a
  /// workspace, and finally loads the workspace's data.
  Future<void> _adoptFirstWorkspace() async {
    final auth = Stores.auth;
    await auth.initialize();
    await auth.ensureIdentity();
    await Stores.workspaceContext.reload();
    if (!mounted) return;
    AppToast.success(context, 'You are all set.');
    context.go(AppRoutes.vault);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your workspace'),
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
            if (_error != null) ...[
              AppAlert(
                destructive: true,
                title: const Text('That did not work'),
                content: Text(_error!).small,
              ),
              AppSpacing.gapMd,
            ],
            if (_choice == _Choice.undecided) ..._chooser(context),
            if (_choice == _Choice.create) ..._createForm(context),
            if (_choice == _Choice.join) ..._joinForm(context),
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
      onTap: () => setState(() => _choice = _Choice.create),
    ),
    AppSpacing.gapMd,
    _ChoiceCard(
      icon: AppIcons.key,
      title: 'Join with an invite',
      subtitle: 'Paste the key someone shared with you.',
      onTap: () => setState(() => _choice = _Choice.join),
    ),
  ];

  List<Widget> _createForm(BuildContext context) => [
    AppTextField(
      controller: _nameCtrl,
      label: 'Workspace name',
      hint: 'e.g. Acme, or your own name',
    ),
    AppSpacing.gapLg,
    AppButton(
      label: _busy ? 'Creating…' : 'Create workspace',
      onTap: _busy ? null : _createWorkspace,
    ),
    _backButton(),
  ];

  List<Widget> _joinForm(BuildContext context) => [
    AppTextField(
      controller: _keyCtrl,
      label: 'Invite key',
      hint: 'revoked://i/… or the key itself',
    ),
    AppSpacing.gapSm,
    AppButton(
      label: _previewing ? 'Checking…' : 'Check this invite',
      onTap: _previewing ? null : _peekInvite,
      style: AppButtonStyle.accent,
    ),
    if (_previewing) ...[AppSpacing.gapMd, const Center(child: AppSpinner())],
    if (_preview != null) ...[
      AppSpacing.gapMd,
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_preview!.workspaceName),
            if (_preview!.invitedBy != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text('Invited by ${_preview!.invitedBy}').muted.small,
            ],
            AppSpacing.gapSm,
            for (final permission in _preview!.permissions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Text('• ${permission.label}').muted.small,
              ),
          ],
        ),
      ),
    ],
    AppSpacing.gapLg,
    AppButton(
      label: _busy ? 'Joining…' : 'Join workspace',
      onTap: _busy ? null : _joinWorkspace,
    ),
    _backButton(),
  ];

  Widget _backButton() => AppButton(
    label: 'Back',
    onTap: _busy
        ? null
        : () => setState(() {
            _choice = _Choice.undecided;
            _preview = null;
            _error = null;
          }),
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
