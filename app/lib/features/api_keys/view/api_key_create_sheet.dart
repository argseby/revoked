import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_entity_card.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/permission_check_row.dart';

/// The create-key drawer, opened straight from wherever keys are listed.
/// Header and footer are pinned; only the form scrolls, so Cancel and Create
/// stay reachable however long the permission catalogue grows.
Future<void> openApiKeyCreateSheet(BuildContext context) {
  final store = Stores.apiKeys;
  store.resetDraft();
  Stores.invites.loadCatalogue();

  return showAppSheet(
    context: context,
    builder: (sheetContext) => Observer(
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xxs,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('New API key').header,
                  const SizedBox(height: AppSpacing.xxs),
                  const Text(
                    'A key can do only what you grant it here.',
                  ).muted.small,
                ],
              ),
            ),
            const AppDivider(),

            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppFormSectionHeader('Name'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: AppTextField(
                        controller: store.draftLabel,
                        label: 'Name this key',
                        hint: 'e.g. Production server',
                      ),
                    ),

                    const AppFormSectionHeader('Expires'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: AppSegmented<int?>(
                        value: store.draftExpiresInDays,
                        items: [
                          for (final option in _expiryOptions)
                            AppSegmentedItem(
                              value: option.days,
                              label: option.label,
                            ),
                        ],
                        onChanged: store.setDraftExpiry,
                      ),
                    ),

                    const AppFormSectionHeader('What this key may do'),
                    Observer(
                      builder: (_) {
                        final catalogue = Stores.invites.catalogue;
                        if (catalogue.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(AppSpacing.xl),
                            child: Text('Loading permissions…'),
                          );
                        }
                        return Column(
                          children: [
                            for (final permission in catalogue)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xl,
                                ),
                                child: PermissionCheckRow(
                                  permission: permission,
                                  selected: store.draftScopes.contains(
                                    permission.key,
                                  ),
                                  onChanged: (on) => store.toggleDraftScope(
                                    permission.key,
                                    on,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
            const AppDivider(),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Cancel',
                      style: AppButtonStyle.accent,
                      onTap: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppButton(
                      label: 'Create key',
                      onTap: store.canCreateDraft
                          ? () => _create(ctx, context)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _create(BuildContext sheetCtx, BuildContext parent) async {
  final store = Stores.apiKeys;
  final ok = await store.createApiKey(
    label: store.draftLabel.text.trim(),
    user: Stores.auth.userId,
    workspace: Stores.auth.activeWorkspace ?? '',
    scopes: store.draftScopes.toList(),
    expiresAt: _expiryTimestamp(store.draftExpiresInDays),
  );
  if (!sheetCtx.mounted) return;
  if (!ok) {
    AppToast.error(sheetCtx, store.errorMessage ?? 'Could not create the key.');
    return;
  }
  Navigator.of(sheetCtx).pop();
  final token = store.lastCreatedPlainToken;
  if (token != null && parent.mounted) {
    await _showTokenDialog(parent, token);
  }
  // Unconditionally: the plaintext key must not survive in memory because the
  // dialog was dismissed by tapping the barrier, or never opened at all.
  store.clearLastToken();
}

Future<void> _showTokenDialog(BuildContext context, String token) async {
  final copy = await showAppDialog(
    context: context,
    title: 'Copy this key now',
    message: 'It is shown once and cannot be retrieved later.',
    content: SelectableText(token),
    confirmLabel: 'Copy',
    cancelLabel: 'Done',
  );
  if (copy) await Clipboard.setData(ClipboardData(text: token));
}

/// Revoke with the standard confirmation; shared by the settings list and the
/// full-screen list.
Future<void> confirmRevokeApiKey(BuildContext context, String id) async {
  final confirmed = await showAppDialog(
    context: context,
    title: 'Revoke API key',
    message:
        'This key will stop working immediately. '
        'This action cannot be undone.',
    confirmLabel: 'Revoke',
    destructive: true,
  );
  if (confirmed) await Stores.apiKeys.deleteApiKey(id);
}

/// One key as an expanding card: scopes as pills, revoke at the bottom.
class ApiKeyCard extends StatelessWidget {
  final dynamic apiKey;

  const ApiKeyCard({super.key, required this.apiKey});

  @override
  Widget build(BuildContext context) {
    final scopes = (apiKey.scopes as List<String>).toSet().toList()..sort();

    return AppEntityCard(
      icon: AppIcons.key,
      title: apiKey.label,
      subtitle: apiKey.neverExpires
          ? 'Never expires'
          : 'Expires ${AppEntityCard.formatDate(apiKey.expiresAt) ?? apiKey.expiresAt}',
      tags: [AppBadge(label: '${scopes.length} permissions', mono: true)],
      actions: [
        AppSheetAction(
          icon: AppIcons.xCircle,
          label: 'Revoke key',
          destructive: true,
          onTap: () => confirmRevokeApiKey(context, apiKey.id as String),
        ),
      ],
    );
  }
}

class _ExpiryOption {
  final String label;
  final int? days;
  const _ExpiryOption(this.label, this.days);
}

/// "Never" is deliberately offered: some integrations have nowhere to rotate
/// a key from.
const _expiryOptions = [
  _ExpiryOption('7 days', 7),
  _ExpiryOption('30 days', 30),
  _ExpiryOption('90 days', 90),
  _ExpiryOption('Never', null),
];

String? _expiryTimestamp(int? days) {
  if (days == null) return null;
  return DateTime.now().toUtc().add(Duration(days: days)).toIso8601String();
}
