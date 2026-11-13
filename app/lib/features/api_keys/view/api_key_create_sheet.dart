import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/utils/dates.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/api_key.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_alert.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_create_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/permission_check_row.dart';
import 'package:revoked_app/features/api_keys/store/api_keys_store.dart';
import 'package:revoked_app/features/connections/view/access_summary.dart';
import 'package:revoked_app/features/vault/view/vault_create_sheet.dart';

/// Clears the last draft and loads what the form offers, before it opens.
void prepareApiKeyDraft() {
  Stores.apiKeys.resetDraft();
  Stores.invites.loadCatalogue();
  Stores.vault.loadIfDue();
}

/// Starting points for a new key: the permissions and reach most scripts need.
List<AppCreateStart> apiKeyStarts() {
  final store = Stores.apiKeys;
  return [
    AppCreateStart(
      icon: AppIcons.arrowRepeat,
      label: 'Keep records current',
      subtitle: 'Writes records into selected sections',
      apply: () => store.toggleDraftScope('vault:write', true),
    ),
    AppCreateStart(
      icon: AppIcons.inboxFill,
      label: 'Read collected data',
      subtitle: 'Exports responses to requests',
      apply: () => store.toggleDraftScope('responses:read', true),
    ),
    AppCreateStart(
      icon: AppIcons.sliders,
      label: 'Custom',
      subtitle: 'No permissions preselected',
      apply: () {},
    ),
  ];
}

/// Opens the new-key form, starting from one of [apiKeyStarts].
Future<void> openApiKeyCreateSheet(BuildContext context) => showAppCreateSheet(
  context,
  label: 'New API key',
  starts: apiKeyStarts(),
  onOpen: prepareApiKeyDraft,
  form: (close) => ApiKeyCreateForm(onClose: close),
);

/// The new-key form.
class ApiKeyCreateForm extends StatelessWidget {
  final VoidCallback onClose;

  const ApiKeyCreateForm({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final store = Stores.apiKeys;
    return Observer(
      builder: (ctx) => Column(
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
                  'A key is limited to the permissions and vault sections '
                  'selected here. Keys are for personal use; other services '
                  'connect as tools or send requests.',
                ).muted.small,
              ],
            ),
          ),
          const AppDivider(),

          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppFormSectionHeader('Name'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: AppTextField(
                  controller: store.draftLabel,
                  label: 'Key name',
                  required: true,
                  hint: 'e.g. Production server',
                ),
              ),

              const AppFormSectionHeader('Expires'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: AppSegmented<int?>(
                  value: store.draftExpiresInDays,
                  items: [
                    for (final option in _expiryOptions)
                      AppSegmentedItem(value: option.days, label: option.label),
                  ],
                  onChanged: store.setDraftExpiry,
                ),
              ),

              AppFormSectionHeader(
                'Permissions',
                missing: store.draftScopes.isEmpty,
              ),
              Observer(
                builder: (_) {
                  final catalogue = _keyPermissions(Stores.invites.catalogue);
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
                                  onChanged: (on) => store.toggleDraftScope(
                                    permission.key,
                                    on,
                                  ),
                                )
                              : PermissionCheckRow(
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
              if (store.draftReachesVault) ...[
                AppFormSectionHeader(
                  'Sections',
                  missing: store.draftSections.isEmpty,
                ),
                const _SectionPicker(),
              ],
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
          const AppDivider(),

          // A greyed-out button alone does not say what it is waiting for.
          if (_missing(store) case final missing?)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                0,
              ),
              child: Text(missing).muted.small,
            ),
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
                    onTap: onClose,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    icon: AppIcons.plus,
                    label: 'Create key',
                    onTap: store.canCreateDraft
                        ? () => _create(context, onClose)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the form still needs before the key can be created, in the order
/// the form asks for it; null once [ApiKeysStore.canCreateDraft] holds.
String? _missing(ApiKeysStore store) {
  if (store.draftLabel.text.trim().isEmpty) return 'A key name is required.';
  if (store.draftScopes.isEmpty) return 'At least one permission is required.';
  if (store.draftReachesVault && store.draftSections.isEmpty) {
    return _ownSections().isEmpty
        ? 'Vault access requires a vault section, and there are none yet.'
        : 'Vault access requires at least one selected section.';
  }
  return null;
}

Future<void> _create(BuildContext context, VoidCallback close) async {
  final store = Stores.apiKeys;
  final ok = await store.createApiKey(
    label: store.draftLabel.text.trim(),
    user: Stores.auth.userId,
    workspace: Stores.auth.activeWorkspace ?? '',
    scopes: store.draftScopes.toList(),
    sections: store.draftReachesVault ? store.draftSections.toList() : const [],
    expiresAt: _expiryTimestamp(store.draftExpiresInDays),
  );
  if (!context.mounted) return;
  if (!ok) {
    AppToast.error(
      context,
      store.errorMessage ?? 'The key could not be created.',
    );
    return;
  }
  final token = store.lastCreatedPlainToken;
  if (token != null) await _showTokenDialog(context, token);
  close();
  // Unconditionally: the plaintext key must not survive in memory because the
  // dialog was dismissed by tapping the barrier, or never opened at all.
  store.clearLastToken();
}

Future<void> _showTokenDialog(BuildContext context, String token) async {
  final copy = await showAppDialog(
    context: context,
    title: 'API key created',
    message: 'Keys are shown once and cannot be retrieved later.',
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
    message: 'Revoked keys stop working immediately. This cannot be undone.',
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
    final expires = dayOf(apiKey.expiresAt);
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
              label: 'Full vault access — replacement recommended',
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
///
/// Easy to miss until the button stays grey: without a section there is
/// nothing to reach, so the row says so.
String _vaultSubtitle(InvitePermission p) => [
  p.key == 'vault:write'
      ? 'Adds records to the selected sections and edits its own records.'
      : 'Reads the records in the selected sections.',
  if (_ownSections().isEmpty) 'Requires a vault section; there are none yet.',
].join(' ');

/// The person's own sections, the only ones a key may reach. A section
/// holding a request's answers or a sign-in's entries isn't theirs to hand on.
List<Section> _ownSections() => [
  for (final s in Stores.vault.sections)
    if (!s.isRequested && s.user == Stores.auth.userId) s,
];

/// Picks the sections a new key reaches, or says how to make one.
class _SectionPicker extends StatelessWidget {
  const _SectionPicker();

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final store = Stores.apiKeys;
        final sections = _ownSections();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: sections.isEmpty
              ? AppAlert(
                  tone: AppAlertTone.warning,
                  leading: const Icon(AppIcons.folder),
                  title: const Text('No vault sections yet'),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'A key reaches the vault only through sections. '
                        'Records outside a section stay out of every key\'s '
                        'reach.',
                      ).small,
                      AppSpacing.gapSm,
                      AppButton(
                        icon: AppIcons.plus,
                        label: 'Create section',
                        size: AppButtonSize.small,
                        onTap: () => openVaultCreateSheet(
                          context,
                          initialTab: VaultCreateTab.section,
                        ),
                      ),
                    ],
                  ),
                )
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
