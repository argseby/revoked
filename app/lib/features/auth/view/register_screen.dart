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

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
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
                const SizedBox(height: AppSpacing.md),

                const Text('Confirm Password'),
                const SizedBox(height: AppSpacing.xs),
                AppTextField(
                  controller: _confirmController,
                  hint: 'Confirm Password',
                  obscureText: true,
                  passwordToggle: true,
                ),
                const SizedBox(height: AppSpacing.xl),

                Observer(
                  builder: (_) => AppButton(
                    label: 'Sign Up',
                    busy: authStore.isLoading,
                    onTap: () => _handleRegister(authStore),
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

  Future<void> _handleRegister(AuthStore store) async {
    if (_emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _confirmController.text.isEmpty) {
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      AppToast.error(context, 'Passwords do not match');
      return;
    }
    final success = await store.register(
      _emailController.text.trim(),
      _passwordController.text,
      _confirmController.text,
    );
    if (success && mounted) {
      context.go(AppRoutes.vault);
    }
  }
}

/// A horizontal divider with a centered "OR" label.
