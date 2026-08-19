import 'package:flutter/material.dart';

import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/permission_check_row.dart';
import 'package:revoked_app/features/api_keys/store/api_keys_store.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_entity_card.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

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
    final authStore = Stores.auth;

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
                      onTap: () => _showCreateSheet(context, store, authStore),
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
                      return _ApiKeyCard(
                        apiKey: key,
                        onRevoke: () => _confirmRevoke(context, store, key.id),
                      );
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

  void _showCreateSheet(
    BuildContext context,
    ApiKeysStore store,
    AuthStore authStore,
  ) {
    final labelCtrl = TextEditingController();
    final selected = <String>{};
    // Days until the key stops working; null means it never expires.
    int? expiresInDays = 90;

    Stores.invites.loadCatalogue();

    showAppSheet(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xxs,
                    AppSpacing.xl,
                    0,
                  ),
                  child: Text('New API key').header,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xxs,
                    AppSpacing.xl,
                    0,
                  ),
                  child: Text(
                    'A key can do only what you grant it here.',
                  ).muted.small,
                ),

                const AppFormSectionHeader('Name'),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: AppTextField(
                    controller: labelCtrl,
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
                    value: expiresInDays,
                    items: [
                      for (final option in _expiryOptions)
                        AppSegmentedItem(
                          value: option.days,
                          label: option.label,
                        ),
                    ],
                    onChanged: (v) => setSheetState(() => expiresInDays = v),
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
                              selected: selected.contains(permission.key),
                              onChanged: (on) => setSheetState(() {
                                if (on) {
                                  selected.add(permission.key);
                                } else {
                                  selected.remove(permission.key);
                                }
                              }),
                            ),
                          ),
                      ],
                    );
                  },
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xxl,
                  ),
                  child: AppButton(
                    label: 'Create key',
                    onTap: () async {
                      if (labelCtrl.text.trim().isEmpty || selected.isEmpty) {
                        AppToast.error(
                          ctx,
                          'Name the key and grant at least one permission.',
                        );
                        return;
                      }
                      final ok = await store.createApiKey(
                        label: labelCtrl.text.trim(),
                        user: authStore.userId,
                        workspace: authStore.activeWorkspace ?? '',
                        scopes: selected.toList(),
                        expiresAt: _expiryTimestamp(expiresInDays),
                      );
                      if (!ctx.mounted) return;
                      if (!ok) {
                        AppToast.error(
                          ctx,
                          store.errorMessage ?? 'Could not create the key.',
                        );
                        return;
                      }
                      Navigator.of(ctx).pop();
                      final token = store.lastCreatedPlainToken;
                      if (token != null && context.mounted) {
                        await _showTokenDialog(context, token);
                      }
                      // Unconditionally: the plaintext key must not survive
                      // in memory because the dialog was dismissed by tapping
                      // the barrier, or never opened at all.
                      store.clearLastToken();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(labelCtrl.dispose);
  }

  /// The key is shown once: only its hash is stored server-side.
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

  Future<void> _confirmRevoke(
    BuildContext context,
    ApiKeysStore store,
    String id,
  ) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Revoke API key',
      message:
          'This key will stop working immediately. '
          'This action cannot be undone.',
      confirmLabel: 'Revoke',
      destructive: true,
    );
    if (confirmed) await store.deleteApiKey(id);
  }
}

class _ApiKeyCard extends StatelessWidget {
  final dynamic apiKey;
  final VoidCallback onRevoke;

  const _ApiKeyCard({required this.apiKey, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    // Scopes are the expanded form of the granted permissions, and two
    // permissions can expand onto the same scope, so the stored list repeats.
    final scopes = (apiKey.scopes as List<String>).toSet().toList()..sort();

    return AppEntityCard(
      icon: AppIcons.key,
      title: apiKey.label,
      subtitle: apiKey.neverExpires
          ? 'Never expires'
          : 'Expires ${AppEntityCard.formatDate(apiKey.expiresAt) ?? apiKey.expiresAt}',
      tags: [for (final scope in scopes) AppBadge(label: scope, mono: true)],
      actions: [
        AppSheetAction(
          icon: AppIcons.xCircle,
          label: 'Revoke key',
          destructive: true,
          onTap: onRevoke,
        ),
      ],
    );
  }
}

/// How long a new key stays valid. "Never" is deliberately offered: some
/// integrations have nowhere to rotate a key from.
class _ExpiryOption {
  final String label;
  final int? days;
  const _ExpiryOption(this.label, this.days);
}

const _expiryOptions = [
  _ExpiryOption('7 days', 7),
  _ExpiryOption('30 days', 30),
  _ExpiryOption('90 days', 90),
  _ExpiryOption('Never', null),
];

/// Renders the chosen lifetime as the timestamp the API expects; null for a key
/// that never expires.
String? _expiryTimestamp(int? days) {
  if (days == null) return null;
  return DateTime.now().toUtc().add(Duration(days: days)).toIso8601String();
}
