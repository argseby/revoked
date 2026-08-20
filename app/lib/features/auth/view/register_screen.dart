import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/auth/view/server_settings_sheet.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

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
                const Text('Create an account').header,
                const SizedBox(height: AppSpacing.xxs),
                const Text('Enter your details below to sign up').muted,
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

                const Text('Email'),
                const SizedBox(height: AppSpacing.xs),
                AppTextField(
                  controller: Stores.auth.registerEmail,
                  hint: 'name@example.com',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: AppSpacing.md),

                const Text('Password'),
                const SizedBox(height: AppSpacing.xs),
                AppTextField(
                  controller: Stores.auth.registerPassword,
                  hint: 'Password',
                  obscureText: true,
                  passwordToggle: true,
                ),
                const SizedBox(height: AppSpacing.md),

                const Text('Confirm Password'),
                const SizedBox(height: AppSpacing.xs),
                AppTextField(
                  controller: Stores.auth.registerConfirm,
                  hint: 'Confirm Password',
                  obscureText: true,
                  passwordToggle: true,
                ),
                const SizedBox(height: AppSpacing.xl),

                Observer(
                  builder: (_) => AppButton(
                    label: 'Sign Up',
                    busy: authStore.isLoading,
                    onTap: () => _handleRegister(context, authStore),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                const AppDivider(label: 'OR'),
                const SizedBox(height: AppSpacing.xl),

                AppButton(
                  label: 'Already have an account? Sign In',
                  onTap: () => context.go(AppRoutes.login),
                  style: AppButtonStyle.accent,
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

  Future<void> _handleRegister(BuildContext context, AuthStore store) async {
    if (Stores.auth.registerEmail.text.isEmpty ||
        Stores.auth.registerPassword.text.isEmpty ||
        Stores.auth.registerConfirm.text.isEmpty) {
      return;
    }
    if (Stores.auth.registerPassword.text != Stores.auth.registerConfirm.text) {
      AppToast.error(context, 'Passwords do not match');
      return;
    }
    final success = await store.register(
      Stores.auth.registerEmail.text.trim(),
      Stores.auth.registerPassword.text,
      Stores.auth.registerConfirm.text,
    );
    if (success && context.mounted) {
      Stores.auth.registerEmail.clear();
      Stores.auth.registerPassword.clear();
      Stores.auth.registerConfirm.clear();

      context.go(AppRoutes.vault);
    }
  }
}

/// A horizontal divider with a centered "OR" label.
