import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/two_factor/view/two_factor_setup_sheet.dart';

/// Shown before anything else when this server requires an authenticator app
/// and the account has none yet. Setting one up opens the app; signing out is
/// the only other way on.
class TwoFactorGateScreen extends StatelessWidget {
  const TwoFactorGateScreen({super.key});

  Future<void> _setUp(BuildContext context) async {
    final on = await showTwoFactorSetupSheet(context);
    if (!on || !context.mounted) return;
    AppToast.success(context, 'Two-factor authentication is on');
    // The router moves on by itself once the gate is open.
    Stores.auth.markTwoFactorSetUp();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: Icon(AppIcons.shieldLock, size: 48)),
                  AppSpacing.gapXl,
                  Semantics(
                    header: true,
                    child: const AppText(
                      'Two-factor authentication required',
                      textAlign: TextAlign.center,
                    ).title,
                  ),
                  AppSpacing.gapSm,
                  const AppText(
                    'This server asks every account for a code from an '
                    'authenticator app after the passkey. The app is set up '
                    'once, here; after that each sign-in asks for its current '
                    'code.',
                    textAlign: TextAlign.center,
                  ).muted,
                  // Which account this is, read from the session.
                  Observer(
                    builder: (_) => Stores.auth.userEmail.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.sm),
                            child: AppText(
                              'Signed in as ${Stores.auth.userEmail}',
                              textAlign: TextAlign.center,
                            ).small.muted,
                          ),
                  ),
                  AppSpacing.gapXxl,
                  AppButton(
                    key: const ValueKey('two-factor-gate-set-up'),
                    icon: AppIcons.shieldLock,
                    label: 'Set up authenticator app',
                    onTap: () => _setUp(context),
                  ),
                  AppSpacing.gapSm,
                  Center(
                    child: AppButton(
                      icon: AppIcons.boxArrowLeft,
                      label: 'Sign out',
                      style: AppButtonStyle.ghost,
                      size: AppButtonSize.small,
                      onTap: () => Stores.auth.logout(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
