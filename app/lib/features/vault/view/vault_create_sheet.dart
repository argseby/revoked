import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_expandable_fab.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_tile.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/vault/view/record_create_sheet.dart';
import 'package:revoked_app/features/vault/view/section_create_sheet.dart';

/// The vault tab's create actions, fanned out by the shell's expandable
/// floating button: section, record, or instantiate a template.
List<AppFabAction> vaultCreateFabActions(BuildContext context) => [
  AppFabAction(
    icon: AppIcons.folderPlus,
    label: 'New Section',
    onTap: () => openSectionCreateSheet(
      context: context,
      store: Stores.vault,
      authStore: Stores.auth,
    ),
  ),
  AppFabAction(
    icon: AppIcons.filePlus,
    label: 'New Record',
    onTap: () => openRecordCreateSheet(
      context: context,
      store: Stores.vault,
      authStore: Stores.auth,
    ),
  ),
  AppFabAction(
    icon: AppIcons.cardList,
    label: 'From Template',
    onTap: () => openVaultTemplateSheet(context),
  ),
];

void openVaultTemplateSheet(BuildContext context) {
  final store = Stores.vault;
  final authStore = Stores.auth;
  final templatesStore = Stores.templates;
  templatesStore.loadTemplates(authStore.activeWorkspace ?? '');

  showAppSheet(
    context: context,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Create from Template').header,
            const SizedBox(height: AppSpacing.xxs),
            const Text(
              'Select a structural blueprint to instantiate sections and records in your vault.',
            ).muted.small,
            const SizedBox(height: AppSpacing.xl),

            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: Observer(
                builder: (_) {
                  if (templatesStore.isLoading &&
                      templatesStore.templates.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.xxl),
                        child: AppSpinner(large: true),
                      ),
                    );
                  }

                  if (templatesStore.templates.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.huge,
                        ),
                        child: Column(
                          children: [
                            Icon(
                              AppIcons.cardList,
                              size: 32,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            const Text('No templates available'),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              'Admins can configure templates in Settings.',
                              textAlign: TextAlign.center,
                            ).muted.small,
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: templatesStore.templates.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, index) {
                      final template = templatesStore.templates[index];
                      final sections =
                          template.schema['sections'] as List<dynamic>? ?? [];
                      final records =
                          template.schema['records'] as List<dynamic>? ?? [];

                      return AppTile(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        leading: Icon(
                          AppIcons.cardList,
                          color: theme.colorScheme.primary,
                          size: 18,
                        ),
                        title: Text(template.name),
                        subtitle: Text(
                          '${sections.length} sections • ${records.length} root records',
                        ).muted.small,
                        trailing: Icon(
                          AppIcons.chevronRight,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onTap: () async {
                          AppToast.success(
                            context,
                            'Instantiating template blueprints...',
                          );

                          final ok = await store.createFromTemplate(
                            template: template,
                            user: authStore.userId,
                            workspace: authStore.activeWorkspace ?? '',
                          );

                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }

                          if (ok && context.mounted) {
                            AppToast.success(
                              context,
                              'Vault items generated successfully!',
                            );
                          } else if (context.mounted) {
                            AppToast.error(
                              context,
                              'Generation failed',
                              subtitle: store.errorMessage ?? 'Unknown error',
                            );
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
