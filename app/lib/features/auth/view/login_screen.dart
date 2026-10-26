import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/router/resume_location.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_logo.dart';
import 'package:revoked_app/core/widgets/app_qr_code.dart';
import 'package:revoked_app/features/auth/signup_policy.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/auth/view/round_trip.dart';
import 'package:revoked_app/features/auth/view/server_settings_sheet.dart';

/// The way in. The passkey belongs to the server's address, so making an
/// account or signing in runs on the server's own page in the browser, which
/// sends the person back signed in. Before it opens for a new account this
/// screen says so, and on a computer first offers the phone.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  @override
  void initState() {
    super.initState();
    SignupPolicy.load();
  }

  Future<void> _changeServer() async {
    await openServerSettingsSheet(context);
    // Another server may take no new accounts.
    await SignupPolicy.load();
  }

  @override
  Widget build(BuildContext context) {
    final authStore = Stores.auth;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Observer(
                      builder: (_) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ..._notices(authStore.errorMessage),
                          switch ((
                            authStore.isAwaitingBrowser,
                            authStore.signupIntro,
                          )) {
                            (true, _) => _waiting(
                              authStore.isLoading,
                              authStore.startedSignup,
                            ),
                            (_, SignupIntro.usePhone) => _usePhone(),
                            (_, SignupIntro.aboutBrowser) => _aboutBrowser(
                              authStore.isLoading,
                            ),
                            _ => _welcome(authStore.isLoading),
                          },
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Observer(
                    builder: (_) => AppButton(
                      icon: AppIcons.server,
                      label: Stores.serverSettings.savedLabel,
                      tooltip: 'Change server',
                      style: AppButtonStyle.ghost,
                      size: AppButtonSize.small,
                      onTap: _changeServer,
                    ),
                  ),
                  const AppText(
                    'Experimental app. Use with care.',
                    textAlign: TextAlign.center,
                  ).small.muted,
                ],
              ),
            ),
          ],
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
        AppSpacing.gapXl,
      ],
      if (error != null) ...[
        AppAlert(
          destructive: true,
          leading: const Icon(AppIcons.exclamation),
          title: const Text('That did not work'),
          content: Text(error),
        ),
        AppSpacing.gapXl,
      ],
    ];
  }

  /// Every state is laid out the same: a picture, a centered title and line,
  /// then full-width buttons, the main one first.
  Widget _screen({
    required Widget top,
    required String title,
    String? body,
    List<Widget> extra = const [],
    required List<Widget> actions,
    bool live = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: top),
        AppSpacing.gapXl,
        Semantics(
          header: true,
          liveRegion: live,
          child: AppText(title, textAlign: TextAlign.center).title,
        ),
        if (body != null) ...[
          AppSpacing.gapSm,
          AppText(body, textAlign: TextAlign.center).muted,
        ],
        for (final widget in extra) ...[AppSpacing.gapLg, widget],
        AppSpacing.gapXxl,
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) AppSpacing.gapSm,
          actions[i],
        ],
      ],
    );
  }

  Widget _welcome(bool busy) {
    if (!SignupPolicy.open) {
      return _screen(
        top: const AppLogo(),
        title: 'Revoked',
        extra: const [
          AppAlert(
            leading: Icon(AppIcons.info),
            title: Text('This server takes no new accounts'),
            content: Text(
              'Ask the person who runs it for an invite. Or sign in if you '
              'have an account.',
            ),
          ),
        ],
        actions: [
          AppButton(
            icon: AppIcons.key,
            label: 'Sign in',
            busy: busy,
            onTap: () => Stores.auth.beginSignIn(),
          ),
        ],
      );
    }
    return _screen(
      top: const AppLogo(),
      title: 'Revoked',
      actions: [
        AppButton(
          icon: AppIcons.personPlus,
          label: 'Create account',
          onTap: busy ? null : Stores.auth.startSignup,
        ),
        AppButton(
          icon: AppIcons.key,
          label: 'I have an account',
          style: AppButtonStyle.accent,
          busy: busy,
          onTap: () => Stores.auth.beginSignIn(),
        ),
      ],
    );
  }

  /// Only on a computer: a passkey stays with the device it is made on, and
  /// the phone is the device people have with them.
  Widget _usePhone() {
    return _screen(
      top: AppQrCode(data: '${Stores.api.baseUrl}/app'),
      title: 'Better on your phone',
      body:
          'Scan the code with your phone camera. Your passkey then lives on '
          'your phone, which is always with you.',
      actions: [
        AppButton(
          icon: AppIcons.computer,
          label: 'Continue on this computer',
          style: AppButtonStyle.accent,
          onTap: Stores.auth.continueSignupHere,
        ),
        _back(),
      ],
    );
  }

  /// Said before anything opens, because a browser appearing unannounced is
  /// where people gave up.
  Widget _aboutBrowser(bool busy) {
    return _screen(
      top: const RoundTrip(at: 0),
      title: 'Next: your browser',
      body:
          'Your browser opens. You set up your account there. Then you come '
          'back here.',
      extra: const [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            AppBadge(label: 'About 1 minute', icon: AppIcons.clock),
            AppBadge(label: 'No password', icon: AppIcons.lock),
          ],
        ),
      ],
      actions: [
        AppButton(
          icon: AppIcons.boxArrowUpRight,
          label: 'Open browser',
          busy: busy,
          onTap: () => Stores.auth.beginSignIn(signup: true),
        ),
        _back(),
      ],
    );
  }

  /// The browser is open; this screen carries on by itself when it answers.
  Widget _waiting(bool busy, bool signup) {
    return _screen(
      top: const RoundTrip(at: 1),
      title: 'Go on in your browser',
      body: signup
          ? 'When you are done there, you come back here.'
          : 'Use your passkey there. Then you come back here.',
      live: true,
      actions: [
        AppButton(
          icon: AppIcons.boxArrowUpRight,
          label: 'Open browser again',
          style: AppButtonStyle.accent,
          busy: busy,
          onTap: () => Stores.auth.beginSignIn(signup: signup),
        ),
        Center(
          child: AppButton(
            icon: AppIcons.x,
            label: 'Cancel',
            style: AppButtonStyle.ghost,
            size: AppButtonSize.small,
            onTap: busy ? null : () => Stores.auth.cancelSignIn(),
          ),
        ),
      ],
    );
  }

  Widget _back() => Center(
    child: AppButton(
      icon: AppIcons.arrowLeft,
      label: 'Back',
      style: AppButtonStyle.ghost,
      size: AppButtonSize.small,
      onTap: Stores.auth.leaveSignupIntro,
    ),
  );
}
