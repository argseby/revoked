import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/router/resume_location.dart';
import 'package:revoked_app/core/utils/form_factor.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_logo.dart';
import 'package:revoked_app/core/widgets/app_qr_code.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/version_summary.dart';
import 'package:revoked_app/features/auth/signup_policy.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/auth/view/round_trip.dart';
import 'package:revoked_app/features/auth/view/server_settings_sheet.dart';
import 'package:revoked_app/features/two_factor/view/two_factor_code_prompt.dart';

/// The way in. The passkey belongs to the server's address, so making an
/// account or signing in runs on the server's own page in the browser, which
/// sends the person back signed in. One button opens it: the page offers a
/// saved passkey and a new account side by side, so nothing is asked here
/// first. The button names the browser, a link can be copied for another
/// browser, and on a computer the phone is offered instead.
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
    Stores.serverSettings.loadServerVersion();
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
                          if (authStore.twoFactorChallenge != null)
                            _twoFactor(
                              authStore.isLoading,
                              authStore.twoFactorError,
                            )
                          else
                            switch ((
                              authStore.isAwaitingBrowser,
                              authStore.signupIntro,
                            )) {
                              (true, _) => _waiting(authStore.isLoading),
                              (_, SignupIntro.usePhone) => _usePhone(),
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Observer(
                    builder: (_) => ServerPill(
                      host: Stores.serverSettings.savedLabel,
                      serverVersion: Stores.serverSettings.serverVersion,
                      onTap: _changeServer,
                    ),
                  ),
                  AppSpacing.gapSm,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        AppIcons.flask,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      AppSpacing.gapXxs,
                      const Text('Experimental').small.muted,
                    ],
                  ),
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
          title: const Text('Sign-in required'),
          content: Text(next),
        ),
        AppSpacing.gapXl,
      ],
      if (error != null) ...[
        AppAlert(
          destructive: true,
          leading: const Icon(AppIcons.exclamation),
          title: const Text('Sign-in failed'),
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
    final open = SignupPolicy.open;
    return _screen(
      top: const AppLogo(),
      title: 'Revoked',
      body: open
          ? 'Sign in or create an account. Revoked uses passkeys, no '
                'passwords.'
          : 'Sign in with a passkey.',
      extra: [
        if (!open)
          const AppAlert(
            leading: Icon(AppIcons.info),
            title: Text('Registration is closed on this server'),
            content: Text(
              'New accounts require an invite from the operator. Existing '
              'accounts can sign in.',
            ),
          ),
      ],
      actions: [
        // The label says where it goes, so nothing has to explain it first:
        // a browser appearing unannounced is where people gave up.
        AppButton(
          label: 'Continue in browser',
          trailingIcon: AppIcons.boxArrowUpRight,
          busy: busy,
          onTap: () => Stores.auth.beginSignIn(),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          children: [
            AppButton(
              icon: AppIcons.copy,
              label: 'Copy link',
              tooltip: 'For another browser on this device',
              style: AppButtonStyle.ghost,
              size: AppButtonSize.small,
              onTap: busy ? null : _copyLink,
            ),
            // A passkey stays with the device it is made on, and the phone
            // is the one people carry: worth a mention on a computer.
            if (open && !isMobileDevice)
              AppButton(
                icon: AppIcons.phone,
                label: 'Use a phone',
                style: AppButtonStyle.ghost,
                size: AppButtonSize.small,
                onTap: busy ? null : Stores.auth.showPhoneSetup,
              ),
          ],
        ),
      ],
    );
  }

  /// The sign-in page as a link, for a browser other than the default one.
  Future<void> _copyLink() async {
    final link = await Stores.auth.signInLink();
    await Clipboard.setData(ClipboardData(text: link.toString()));
    if (!mounted) return;
    AppToast.success(context, 'Sign-in link copied');
  }

  /// Only on a computer, when asked for: a passkey stays with the device it
  /// is made on, and the phone is the device people have with them.
  Widget _usePhone() {
    return _screen(
      top: AppQrCode(data: '${Stores.api.baseUrl}/app'),
      title: 'Set up on a phone',
      body:
          'Scanning the code continues setup on a phone. The passkey is then '
          'stored on that phone.',
      actions: [
        AppButton(
          icon: AppIcons.computer,
          label: 'Continue on this computer',
          style: AppButtonStyle.accent,
          onTap: () {
            Stores.auth.leaveSignupIntro();
            Stores.auth.beginSignIn();
          },
        ),
        _back(),
      ],
    );
  }

  /// The passkey was right and the account has an authenticator app: its
  /// current code completes the sign-in.
  Widget _twoFactor(bool busy, String? error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: Icon(AppIcons.shieldLock, size: 48)),
        AppSpacing.gapXl,
        TwoFactorCodePrompt(
          title: 'Code from the authenticator app',
          body:
              'This account asks for the 6-digit code from its authenticator '
              'app after the passkey.',
          submitLabel: 'Sign in',
          busy: busy,
          error: error,
          onSubmit: (code) => Stores.auth.completeTwoFactor(code),
          onCancel: Stores.auth.cancelTwoFactor,
        ),
      ],
    );
  }

  /// The browser is open; this screen carries on by itself when it answers.
  Widget _waiting(bool busy) {
    return _screen(
      top: const RoundTrip(at: 1),
      title: 'Waiting for the browser',
      body: 'This screen continues once the browser is finished.',
      live: true,
      actions: [
        AppButton(
          icon: AppIcons.boxArrowUpRight,
          label: 'Open browser again',
          style: AppButtonStyle.accent,
          busy: busy,
          onTap: () => Stores.auth.beginSignIn(),
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
