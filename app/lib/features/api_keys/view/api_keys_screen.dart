import 'package:flutter/material.dart';

import 'package:revoked_app/features/api_keys/view/api_key_create_sheet.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';

class ApiKeysScreen extends StatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Stores.apiKeys.loadApiKeys();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.apiKeys;

    final outerPad = AppSpacing.screenH(context);
    final horizontalPad = EdgeInsets.symmetric(horizontal: outerPad);

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: horizontalPad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: [
                    AppButton(
                      icon: AppIcons.chevronLeft,
                      tooltip: 'Back',
                      style: AppButtonStyle.accent,
                      onTap: () => context.go(AppRoutes.settings),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('API Keys').header,
                          const Text(
                            'Manage programmatic access to your workspace.',
                          ).muted.small,
                        ],
                      ),
                    ),
                    AppButton(
                      icon: AppIcons.plus,
                      tooltip: 'New API key',
                      onTap: () => openApiKeyCreateSheet(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const AppDivider(spaced: true),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: horizontalPad,
              child: Observer(
                builder: (_) {
                  if (store.isLoading && store.apiKeys.isEmpty) {
                    return const Center(child: AppSpinner(large: true));
                  }

                  if (store.errorMessage != null) {
                    return AppLoadError(
                      title: 'Failed to load API keys',
                      message: store.errorMessage!,
                      onRetry: store.loadApiKeys,
                    );
                  }

                  if (store.apiKeys.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            AppIcons.key,
                            size: 40,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const Text('No API keys'),
                          const SizedBox(height: AppSpacing.xxs),
                          const Text(
                            'Create a key for programmatic access.',
                          ).muted.small,
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: AppSpacing.huge),
                    itemCount: store.apiKeys.length,
                    itemBuilder: (context, index) {
                      final key = store.apiKeys[index];
                      return ApiKeyCard(apiKey: key);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
