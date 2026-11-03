import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/features/api_keys/view/api_key_create_sheet.dart';

/// The workspace's API keys, listed beside its connected tools: both are ways
/// in from outside the app, and each says what it may do and where.
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
