import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/features/api_keys/view/api_key_create_sheet.dart';

/// The workspace's API keys: what each may do, and which sections it reaches.
class ApiKeysGroup extends StatelessWidget {
  const ApiKeysGroup({super.key});

  @override
  Widget build(BuildContext context) {
    final store = Stores.apiKeys;
    return Observer(
      builder: (_) {
        if (store.errorMessage != null && store.apiKeys.isEmpty) {
          return AppLoadError(
            title: 'Couldn’t load API keys',
            message: store.errorMessage!,
            onRetry: store.loadApiKeys,
          );
        }
        if (store.apiKeys.isEmpty && !store.isLoading) {
          return AppEmptyState(
            icon: AppIcons.key,
            title: 'Connect your own scripts',
            subtitle:
                'Give your scripts and integrations a key to this workspace. '
                'It does only what you allow, and reaches only the sections '
                'you choose.',
            steps: const [
              AppEmptyStep(
                'Name it and choose what it can do',
                'Only what it needs',
              ),
              AppEmptyStep('Copy the key', 'You see it only once'),
              AppEmptyStep('Revoke it any time', 'It stops working right away'),
            ],
            action: AppButton(
              icon: AppIcons.plus,
              label: 'New API key',
              onTap: () => openApiKeyCreateSheet(context),
            ),
          );
        }
        return AppListGroup(
          title: 'API keys',
          footer: const Text(
            'Keys for your scripts. A key reaches only the sections you '
            'choose.',
          ),
          trailing: AppButton(
            icon: AppIcons.plus,
            label: 'New',
            style: AppButtonStyle.accent,
            size: AppButtonSize.small,
            onTap: () => openApiKeyCreateSheet(context),
          ),
          children: [
            if (store.isLoading && store.apiKeys.isEmpty)
              const AppListSkeleton(embedded: true)
            else if (store.apiKeys.isEmpty)
              const AppDetailRow(icon: AppIcons.key, label: 'No API keys yet')
            else
              for (final key in store.apiKeys) ApiKeyRow(apiKey: key),
          ],
        );
      },
    );
  }
}
