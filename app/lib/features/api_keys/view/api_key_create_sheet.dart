import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/api_key.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_entity_card.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/permission_check_row.dart';
import 'package:revoked_app/features/connections/view/access_summary.dart';

/// The create-key drawer, opened straight from wherever keys are listed.
/// Header and footer are pinned; only the form scrolls, so Cancel and Create
/// stay reachable however long the permission catalogue grows.
Future<void> openApiKeyCreateSheet(BuildContext context) {
  final store = Stores.apiKeys;
  store.resetDraft();
  Stores.invites.loadCatalogue();
  Stores.vault.loadIfDue();

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
                    'A key does only what you allow here. It reaches only the '
                    'sections of your vault you choose. Keep it to yourself: '
                    'other services connect as tools or send requests '
                    'instead.',
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

                    const AppFormSectionHeader('What this key can do'),
                    Observer(
                      builder: (_) {
                        final catalogue = _keyPermissions(
                          Stores.invites.catalogue,
                        );
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
                                child: _isVault(permission)
                                    ? AppCheckRow(
                                        label: permission.label,
                                        subtitle: _vaultSubtitle(permission),
                                        value: store.draftScopes.contains(
                                          permission.key,
                                        ),
                                        onChanged: (on) =>
                                            store.toggleDraftScope(
                                              permission.key,
                                              on,
                                            ),
                                      )
                                    : PermissionCheckRow(
                                        permission: permission,
                                        selected: store.draftScopes.contains(
                                          permission.key,
                                        ),
                                        onChanged: (on) =>
                                            store.toggleDraftScope(
                                              permission.key,
                                              on,
                                            ),
                                      ),
                              ),
                          ],
                        );
                      },
                    ),
                    if (store.draftReachesVault) ...[
                      const AppFormSectionHeader('Sections it can reach'),
                      const _SectionPicker(),
                    ],
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
                      icon: AppIcons.plus,
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
    sections: store.draftReachesVault ? store.draftSections.toList() : const [],
    expiresAt: _expiryTimestamp(store.draftExpiresInDays),
  );
  if (!sheetCtx.mounted) return;
  if (!ok) {
    AppToast.error(
      sheetCtx,
      store.errorMessage ?? 'Couldn’t create the key. Try again.',
    );
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
    message: 'You see it only once. You can’t get it back later.',
    content: SelectableText(token),
    confirmLabel: 'Copy',
    confirmIcon: AppIcons.copy,
    cancelLabel: 'Done',
  );
  if (copy) await Clipboard.setData(ClipboardData(text: token));
}

/// Revoke with the standard confirmation; shared by the settings list and the
/// full-screen list.
Future<void> confirmRevokeApiKey(BuildContext context, String id) async {
  final confirmed = await showAppDialog(
    context: context,
    title: 'Revoke this API key?',
    message: 'It stops working right away. You can’t undo this.',
    confirmLabel: 'Revoke',
    confirmIcon: AppIcons.xCircle,
    destructive: true,
  );
  if (confirmed) await Stores.apiKeys.deleteApiKey(id);
}

/// One key as a row: what it may do and when it expires; tapping it offers
/// the revoke.
class ApiKeyRow extends StatelessWidget {
  final ApiKey apiKey;

  const ApiKeyRow({super.key, required this.apiKey});

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final scopes = apiKey.scopes;
    final catalogue = _keyPermissions(Stores.invites.catalogue);
    // A key from before keys were kept out of the vault still holds what it
    // was granted, until it expires or is revoked.
    final opensVault = Stores.invites.catalogue.any(
      (p) => p.membersOnly && p.scopes.any(scopes.contains),
    );
    final expires = AppEntityCard.formatDate(apiKey.expiresAt);
    final label = apiKey.label;

    final vaultAccess = apiKey.vaultAccess;
    final sections = apiKey.sections;

    return AppListRow(
      icon: AppIcons.key,
      title: label,
      subtitle: [
        // Stored scopes are the expanded form, so they are counted as the
        // permissions they satisfy — the same count members and invites show.
        // The vault's two are held as its access instead.
        if (catalogue.isNotEmpty)
          accessSummary(
            permissions:
                permissionsFromScopes(
                  catalogue.where((p) => !_isVault(p)).toList(),
                  scopes,
                ).length +
                (vaultAccess.isEmpty ? 0 : 1) +
                (vaultAccess == 'write' ? 1 : 0),
            sections: vaultAccess.isEmpty ? 0 : sections.length,
          ),
        expires == null ? 'Never expires' : 'Expires $expires',
      ].join(' · '),
      trailing: opensVault
          ? const AppBadge(
              icon: AppIcons.exclamationTriangle,
              label: 'Can open the vault — replace it',
              variant: AppBadgeVariant.destructive,
            )
          : null,
      onTap: () => showAppOptionsSheet(
        context: context,
        title: label,
        actions: [
          AppSheetAction(
            icon: AppIcons.xCircle,
            label: 'Revoke key',
            destructive: true,
            onTap: () => confirmRevokeApiKey(context, apiKey.id),
          ),
        ],
      ),
    );
  }
}

/// What a key may be granted: everything a member may hand on, and the vault
/// through the sections picked for it.
List<InvitePermission> _keyPermissions(List<InvitePermission> catalogue) =>
    catalogue.where((p) => !p.membersOnly || _isVault(p)).toList();

bool _isVault(InvitePermission p) =>
    p.key == 'vault:read' || p.key == 'vault:write';

/// The catalogue's words are about a member, who reaches the whole vault; a
/// key reaches only its sections.
String _vaultSubtitle(InvitePermission p) => p.key == 'vault:write'
    ? 'Add records to the sections you choose, and change the ones it added.'
    : 'See the records in the sections you choose.';

/// The person's own sections, to pick the ones a new key reaches. A section
/// holding a request's answers or a sign-in's entries isn't theirs to hand on.
class _SectionPicker extends StatelessWidget {
  const _SectionPicker();

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final store = Stores.apiKeys;
        final sections = [
          for (final s in Stores.vault.sections)
            if (!s.isRequested && s.user == Stores.auth.userId) s,
        ];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: sections.isEmpty
              ? const Text(
                  'You have no sections yet. Make one in your vault first.',
                ).muted.small
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in sections)
                      AppCheckRow(
                        label: s.name.isEmpty ? s.key : s.name,
                        subtitle:
                            '${s.records.length} '
                            '${s.records.length == 1 ? 'record' : 'records'}',
                        value: store.draftSections.contains(s.id),
                        onChanged: (on) => store.toggleDraftSection(s.id, on),
                      ),
                  ],
                ),
        );
      },
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
