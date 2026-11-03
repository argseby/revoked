import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_inline_create.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppInlineCreate(
          label: 'New API key',
          starts: apiKeyStarts(),
          onOpen: prepareApiKeyDraft,
          form: (close) => ApiKeyCreateForm(onClose: close),
        ),
        AppSpacing.gapLg,
        const _Keys(),
      ],
    );
  }
}

class _Keys extends StatelessWidget {
  const _Keys();

  @override
  Widget build(BuildContext context) {
    final store = Stores.apiKeys;
    return Observer(
      builder: (_) {
        if (store.errorMessage != null && store.apiKeys.isEmpty) {
          return AppLoadError(
            title: 'API keys could not be loaded',
            message: store.errorMessage!,
            onRetry: store.loadApiKeys,
          );
        }
        if (store.apiKeys.isEmpty && !store.isLoading) {
          return AppEmptyState(
            icon: AppIcons.key,
            title: 'No API keys',
            subtitle:
                'API keys provide programmatic access to this workspace, '
                'limited to the granted permissions and sections.',
            steps: const [
              AppEmptyStep('Permissions', 'Scoped to the required access'),
              AppEmptyStep('Key', 'Shown once at creation'),
              AppEmptyStep('Revocation', 'Takes effect immediately'),
            ],
          );
        }
        return AppListGroup(
          title: 'API keys',
          footer: const Text(
            'Programmatic access, limited to the selected sections.',
          ),
          children: [
            if (store.isLoading && store.apiKeys.isEmpty)
              const AppListSkeleton(embedded: true)
            else if (store.apiKeys.isEmpty)
              const AppDetailRow(icon: AppIcons.key, label: 'No API keys')
            else
              for (final key in store.apiKeys) ApiKeyRow(apiKey: key),
          ],
        );
      },
    );
  }
}
