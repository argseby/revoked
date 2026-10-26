import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/router/resume_location.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_logo.dart';
import 'package:revoked_app/features/auth/signup_steps.dart';
import 'package:revoked_app/features/auth/view/server_settings_sheet.dart';

/// The way in. New here, it says what Revoked is and lays out every step of
/// making an account, with the time it takes, before anything opens; signing
/// in again is the second choice, and one step.
///
/// The passkey belongs to the server's address, so the buttons open the
/// server's own page in the browser, which talks to the device's
/// authenticator and sends the person back signed in. While it is open this
/// screen says which steps happen there, and carries on by itself.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  @override
  void initState() {
    super.initState();
    SignupSteps.load();
  }

  Future<void> _changeServer() async {
    await openServerSettingsSheet(context);
    // Another server may count other steps, or take no new accounts.
    await SignupSteps.load();
  }

  @override
  Widget build(BuildContext context) {
    final authStore = Stores.auth;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxl,
            vertical: AppSpacing.huge,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Observer(
              builder: (_) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: AppLogo(),
                  ),
                  AppSpacing.gapXl,
                  ..._notices(authStore.errorMessage),
                  if (authStore.isAwaitingBrowser)
                    _waiting(authStore.isLoading, authStore.startedSignup)
                  else
                    _welcome(authStore.isLoading),
                  AppSpacing.gapXxl,
                  Center(
                    child: AppButton(
                      icon: AppIcons.server,
                      label: 'Server: ${Stores.serverSettings.savedLabel}',
                      style: AppButtonStyle.ghost,
                      size: AppButtonSize.small,
                      onTap: _changeServer,
                    ),
                  ),
                  AppSpacing.gapXs,
                  Center(
                    child: const Text(
                      'This is an experimental app. Use with caution.',
                    ).muted.small,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A link that brought someone here, and anything that went wrong.
  List<Widget> _notices(String? error) {
    final next = ResumeLocation.describe();
    return [
      if (next != null) ...[
        AppAlert(
          leading: const Icon(AppIcons.info),
          title: const Text('Sign in or create an account first'),
          content: Text(next),
        ),
        AppSpacing.gapLg,
      ],
      if (error != null) ...[
        AppAlert(
          destructive: true,
          leading: const Icon(AppIcons.exclamation),
          title: const Text('That did not work'),
          content: Text(error),
        ),
        AppSpacing.gapLg,
      ],
    ];
  }

  Widget _welcome(bool busy) {
    final policy = SignupSteps.policy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: const AppText('Share your data without handing it over').title,
        ),
        AppSpacing.gapSm,
        const Text(
          'People get a link, never a copy, and you can stop it at any time.',
        ).muted,
        AppSpacing.gapXl,
        if (policy.open) ...[
          _JourneyCard(
            title: 'Creating an account · ${SignupSteps.duration}',
            steps: SignupSteps.names,
            footer:
                'Steps 1 to ${SignupSteps.count - 1} run on your server’s '
                'own page in your browser, and you come straight back here. '
                'There is no password.',
          ),
          AppSpacing.gapXl,
          AppButton(
            icon: AppIcons.personPlus,
            label: 'Create account',
            busy: busy,
            onTap: () => Stores.auth.beginSignIn(signup: true),
          ),
          AppSpacing.gapSm,
          AppButton(
            icon: AppIcons.key,
            label: 'I already have an account',
            style: AppButtonStyle.accent,
            onTap: busy ? null : () => Stores.auth.beginSignIn(),
          ),
        ] else ...[
          const AppAlert(
            leading: Icon(AppIcons.info),
            title: Text('This server takes no new accounts'),
            content: Text(
              'Ask whoever runs it for an invite link, or sign in if you '
              'already have an account.',
            ),
          ),
          AppSpacing.gapXl,
          AppButton(
            icon: AppIcons.key,
            label: 'Sign in',
            busy: busy,
            onTap: () => Stores.auth.beginSignIn(),
          ),
        ],
      ],
    );
  }

  /// The browser has the next steps; this screen says which, and carries on
  /// by itself when they are done.
  Widget _waiting(bool busy, bool signup) {
    final last = SignupSteps.count;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          liveRegion: true,
          child: AppText(
            signup ? 'Continue in your browser' : 'Sign in in your browser',
          ).title,
        ),
        AppSpacing.gapSm,
        Text(
          signup
              ? 'Steps 1 to ${last - 1} are on the page that just opened. '
                    'When they are done you come back here for the last one.'
              : 'Confirm with your passkey on the page that just opened. It '
                    'takes about 10 seconds, and this screen moves on by '
                    'itself.',
        ).muted,
        if (signup) ...[
          AppSpacing.gapXl,
          _JourneyCard(
            title: 'Creating an account · ${SignupSteps.duration}',
            steps: SignupSteps.names,
            inBrowser: last - 1,
          ),
        ],
        AppSpacing.gapXl,
        AppButton(
          icon: AppIcons.boxArrowUpRight,
          label: 'Open the page again',
          busy: busy,
          onTap: () => Stores.auth.beginSignIn(signup: signup),
        ),
        AppSpacing.gapSm,
        AppButton(
          icon: AppIcons.arrowLeft,
          label: 'Start over',
          style: AppButtonStyle.accent,
          onTap: busy ? null : () => Stores.auth.cancelSignIn(),
        ),
      ],
    );
  }
}

/// The steps of making an account, numbered. [inBrowser] marks how many of
/// the first ones happen on the server's page.
class _JourneyCard extends StatelessWidget {
  final String title;
  final List<String> steps;
  final String? footer;
  final int inBrowser;

  const _JourneyCard({
    required this.title,
    required this.steps,
    this.footer,
    this.inBrowser = 0,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadius.allLg,
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppText(title).bold,
          AppSpacing.gapMd,
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.surfaceContainerHighest,
                    ),
                    child: AppText('${i + 1}').small.bold,
                  ),
                  AppSpacing.gapMd,
                  Expanded(child: Text(steps[i])),
                  if (inBrowser > 0)
                    AppText(i < inBrowser ? 'Browser' : 'Here').small.muted,
                ],
              ),
            ),
          if (footer != null) ...[
            Divider(color: scheme.outlineVariant, height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.lock, size: 16, color: scheme.onSurfaceVariant),
                AppSpacing.gapSm,
                Expanded(child: Text(footer!).small.muted),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
