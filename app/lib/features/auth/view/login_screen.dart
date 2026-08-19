import 'package:flutter/material.dart';

import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_brand_mark.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/auth/view/server_settings_sheet.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

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
                const Center(child: AppBrandMark(size: 40)),
                const SizedBox(height: AppSpacing.xxl),

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
                  controller: _emailController,
                  hint: 'name@example.com',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: AppSpacing.md),

                const Text('Password'),
                const SizedBox(height: AppSpacing.xs),
                AppTextField(
                  controller: _passwordController,
                  hint: 'Password',
                  obscureText: true,
                  passwordToggle: true,
                ),
                const SizedBox(height: AppSpacing.xl),

                Observer(
                  builder: (_) => AppButton(
                    label: 'Sign In',
                    busy: authStore.isLoading,
                    onTap: () => _handleLogin(authStore),
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
                const Text(
                  'This is an experimental app. Use with caution.',
                ).muted.small,
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: AppButton(
                    icon: AppIcons.server,
                    label: 'Server: ${_serverLabel()}',
                    style: AppButtonStyle.accent,
                    size: AppButtonSize.small,
                    onTap: () async {
                      await openServerSettingsSheet(context);
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _serverLabel() {
    final url = Stores.api.baseUrl;
    return Uri.tryParse(url)?.authority ?? url;
  }

  Future<void> _handleLogin(AuthStore store) async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      return;
    }
    final success = await store.login(
      _emailController.text.trim(),
      _passwordController.text,
    );
    if (success && mounted) {
      context.go(AppRoutes.vault);
    }
  }
}

/// A horizontal divider with a centered "OR" label.
