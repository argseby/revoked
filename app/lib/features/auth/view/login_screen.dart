import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_logo.dart';
import 'package:revoked_app/features/auth/view/server_settings_sheet.dart';

/// Signing in is a passkey, and a passkey belongs to the server's address:
/// the buttons here open the server's own page in the browser, which talks
/// to the device's authenticator and sends the person back signed in. There
/// is nothing to type here, and no password anywhere.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authStore = Stores.auth;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(alignment: Alignment.centerLeft, child: AppLogo()),
                const SizedBox(height: AppSpacing.xl),
                const Text('Sign in to your account').header,
                const SizedBox(height: AppSpacing.xxs),
                const Text(
                  'With a passkey: your fingerprint, face or device PIN. '
                  'There is no password.',
                ).muted,
                const SizedBox(height: AppSpacing.xxl),

                Observer(
                  builder: (_) {
                    if (authStore.errorMessage != null) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        child: AppAlert(
                          destructive: true,
                          leading: const Icon(AppIcons.exclamation),
                          title: const Text('Error'),
                          content: Text(authStore.errorMessage!),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                Observer(
                  builder: (_) => authStore.isAwaitingBrowser
                      ? _waiting(authStore.isLoading)
                      : _start(authStore.isLoading),
                ),

                const SizedBox(height: AppSpacing.xxl),
                Center(
                  child: const Text(
                    'This is an experimental app. Use with caution.',
                  ).muted.small,
                ),
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: Observer(
                    builder: (_) => AppButton(
                      icon: AppIcons.server,
                      label: 'Server: ${Stores.serverSettings.savedLabel}',
                      style: AppButtonStyle.accent,
                      size: AppButtonSize.small,
                      onTap: () => openServerSettingsSheet(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _start(bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          icon: AppIcons.key,
          label: 'Sign in with a passkey',
          busy: busy,
          onTap: () => Stores.auth.beginSignIn(),
        ),
        const SizedBox(height: AppSpacing.xl),
        const AppDivider(label: 'OR'),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          icon: AppIcons.personPlus,
          label: 'Create an account',
          onTap: () => Stores.auth.beginSignIn(signup: true),
          style: AppButtonStyle.accent,
        ),
      ],
    );
  }

  /// The browser has the next step; this screen carries on by itself when
  /// it is done.
  Widget _waiting(bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppAlert(
          leading: const Icon(AppIcons.boxArrowUpRight),
          title: const Text('Continue in your browser'),
          content: const Text(
            'Your server’s sign-in page is open there. This screen carries '
            'on by itself once you are done.',
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          icon: AppIcons.boxArrowUpRight,
          label: 'Open the page again',
          busy: busy,
          onTap: () => Stores.auth.beginSignIn(),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          icon: AppIcons.x,
          label: 'Cancel',
          style: AppButtonStyle.accent,
          onTap: busy ? null : () => Stores.auth.cancelSignIn(),
        ),
      ],
    );
  }
}
