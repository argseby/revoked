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
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/auth/view/server_settings_sheet.dart';

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
                const Text('Sign in to your account').header,
                const SizedBox(height: AppSpacing.xxs),
                const Text('Enter your credentials below').muted,
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
                  controller: Stores.auth.loginEmail,
                  hint: 'name@example.com',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: AppSpacing.md),

                const Text('Password'),
                const SizedBox(height: AppSpacing.xs),
                AppTextField(
                  controller: Stores.auth.loginPassword,
                  hint: 'Password',
                  obscureText: true,
                  passwordToggle: true,
                ),
                const SizedBox(height: AppSpacing.xl),

                Observer(
                  builder: (_) => AppButton(
                    label: 'Sign In',
                    busy: authStore.isLoading,
                    onTap: () => _handleLogin(context, authStore),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                const AppDivider(label: 'OR'),
                const SizedBox(height: AppSpacing.xl),

                AppButton(
                  label: 'Create an account',
                  onTap: () => context.go(AppRoutes.register),
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

  Future<void> _handleLogin(BuildContext context, AuthStore store) async {
    if (Stores.auth.loginEmail.text.isEmpty ||
        Stores.auth.loginPassword.text.isEmpty) {
      return;
    }
    final success = await store.login(
      Stores.auth.loginEmail.text.trim(),
      Stores.auth.loginPassword.text,
    );
    if (success && context.mounted) {
      Stores.auth.loginEmail.clear();
      Stores.auth.loginPassword.clear();

      context.go(AppRoutes.vault);
    }
  }
}

/// A horizontal divider with a centered "OR" label.
