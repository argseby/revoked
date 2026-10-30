import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/identity.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/models/workspace.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/device_key_alert.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/app_trust_badge.dart';
import 'package:revoked_app/core/widgets/trust_panel.dart';
import 'package:revoked_app/features/api_keys/view/api_key_create_sheet.dart';
import 'package:revoked_app/features/connections/view/connections_section.dart';
import 'package:revoked_app/features/invites/view/invite_create_sheet.dart';
import 'package:revoked_app/features/invites/view/invite_join_sheet.dart';
import 'package:revoked_app/features/invites/view/member_permissions_sheet.dart';
import 'package:revoked_app/features/passkeys/view/passkeys_section.dart';
import 'package:revoked_app/features/templates/view/templates_screen.dart';
import 'package:revoked_app/features/settings/view/appearance_page.dart';

/// The settings topics, each a page of its own under Settings — opened from
/// the settings list the way a record is opened from the vault.
enum SettingsPage {
  appearance('appearance', 'Appearance and accessibility'),
  passkeys('passkeys', 'Passkeys'),
  workspaces('workspaces', 'Workspaces'),
  members('members', 'Members'),
  invites('invites', 'Invites'),
  identities('identities', 'Identities'),
  connectedTools('connected-tools', 'Connected tools'),
  apiKeys('api-keys', 'API keys'),
  templates('templates', 'Templates'),
  domain('domain', 'Domain verification');

  const SettingsPage(this.slug, this.title);

  final String slug;
  final String title;

  /// Templates live in the vault now; every other topic under Settings.
  String get route =>
      this == templates ? AppRoutes.templates : AppRoutes.settingsPage(slug);

  static SettingsPage? fromSlug(String? slug) {
    for (final p in values) {
      if (p.slug == slug) return p;
    }
    return null;
  }
}

/// One settings topic: its name and the way back in the top bar, its groups
/// below.
class SettingsPageScreen extends StatefulWidget {
  final SettingsPage page;

  const SettingsPageScreen({super.key, required this.page});

  @override
  State<SettingsPageScreen> createState() => _SettingsPageScreenState();
}

class _SettingsPageScreenState extends State<SettingsPageScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellSlots.title.claim(_title);
      _load();
    });
  }

  @override
  void dispose() {
    ShellSlots.title.release(_title);
    super.dispose();
  }

  Widget _title(BuildContext context) => AppBarTitle(
    title: widget.page.title,
    onBack: () => context.go(
      widget.page == SettingsPage.templates
          ? AppRoutes.vault
          : AppRoutes.settings,
    ),
  );

  void _load() {
    final auth = Stores.auth;
    if (!auth.isAuthenticated) return;
    final ws = auth.activeWorkspace ?? '';
    switch (widget.page) {
      case SettingsPage.appearance:
      case SettingsPage.passkeys:
      case SettingsPage.domain:
        // Load themselves.
        break;
      case SettingsPage.workspaces:
        Stores.settings.loadWorkspaces(auth.userId);
        Stores.invites.loadCatalogue();
      case SettingsPage.members:
        if (ws.isNotEmpty) Stores.invites.loadMembers(ws);
        // The total is what "3 of 16" is measured against.
        Stores.invites.loadCatalogue();
      case SettingsPage.invites:
        if (ws.isNotEmpty) Stores.invites.load(ws);
        Stores.invites.loadCatalogue();
      case SettingsPage.identities:
        Stores.identities.loadIdentities();
        Stores.settings.ensureDomainChecked();
      case SettingsPage.connectedTools:
        Stores.connections.load();
      case SettingsPage.apiKeys:
        Stores.apiKeys.loadApiKeys();
        Stores.invites.loadCatalogue();
      case SettingsPage.templates:
        Stores.templates.loadTemplates(ws);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageBody(
      children: [
        switch (widget.page) {
          SettingsPage.appearance => const AppearancePage(),
          SettingsPage.passkeys => const PasskeysSection(),
          SettingsPage.workspaces => const _WorkspacesPage(),
          SettingsPage.members => const _MembersPage(),
          SettingsPage.invites => const _InvitesPage(),
          SettingsPage.identities => const _IdentitiesPage(),
          SettingsPage.connectedTools => const ConnectionsList(),
          SettingsPage.apiKeys => const _ApiKeysPage(),
          SettingsPage.templates => const _TemplatesPage(),
          SettingsPage.domain => const _DomainPage(),
        },
      ],
    );
  }
}

/// A group's spinner while its rows load for the first time.
class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Center(child: AppSpinner()),
    );
  }
}

/// A small header button that adds to a group — "New", "Join".
class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppButton(
      icon: icon,
      label: label,
      style: AppButtonStyle.accent,
      size: AppButtonSize.small,
      onTap: onTap,
    );
  }
}

// Workspaces

class _WorkspacesPage extends StatelessWidget {
  const _WorkspacesPage();

  Future<void> _confirmDelete(BuildContext context, Workspace workspace) async {
    final settings = Stores.settings;
    final auth = Stores.auth;
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete ${workspace.name}?',
      message:
          'This deletes its records, files, templates, members and API keys. '
          'Every share and request link from it stops working right away, '
          'and its identities are revoked. You can’t undo this.',
      confirmLabel: 'Delete workspace',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final wasActive = auth.activeWorkspace == workspace.id;
    if (!await settings.deleteWorkspace(auth.userId, workspace.id)) {
      if (context.mounted) {
        AppToast.error(
          context,
          'Couldn’t delete the workspace',
          subtitle: settings.errorMessage,
        );
      }
      return;
    }

    // The server clears the active context of everyone pointing at it, so the
    // session still names a workspace that is gone. Same order as a switch:
    // refresh first, then reload, or the stores refetch the dead workspace.
    if (wasActive) {
      await Stores.auth.initialize();
      await Stores.workspaceContext.reload();
    }
  }

  void _options(BuildContext context, Workspace ws, bool active) {
    final auth = Stores.auth;
    showAppOptionsSheet(
      context: context,
      title: ws.name,
      subtitle: ws.id,
      actions: [
        if (!active)
          AppSheetAction(
            icon: AppIcons.arrowRight,
            label: 'Switch to it',
            onTap: () => Stores.workspaceContext.switchTo(
              userId: auth.userId,
              workspaceId: ws.id,
            ),
          ),
        AppSheetAction(
          icon: AppIcons.copy,
          label: 'Copy ID',
          onTap: () {
            Clipboard.setData(ClipboardData(text: ws.id));
            AppToast.success(context, 'Workspace ID copied');
          },
        ),
        if (Stores.settings.canManageWorkspace(ws.id, Stores.invites.catalogue))
          AppSheetAction(
            icon: AppIcons.trash,
            label: 'Delete workspace',
            destructive: true,
            onTap: () => _confirmDelete(context, ws),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Stores.settings;
    return Observer(
      builder: (_) {
        final activeId = Stores.auth.activeWorkspace ?? '';
        return AppListGroup(
          title: 'Workspaces',
          footer: const Text('Keep work, home and clients apart.'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeaderButton(
                // Not the plus the New button carries: joining an existing
                // workspace is not a second way to create one.
                icon: AppIcons.key,
                label: 'Join',
                onTap: () => showInviteJoinSheet(context: context),
              ),
              AppSpacing.gapSm,
              _HeaderButton(
                icon: AppIcons.plus,
                label: 'New',
                onTap: () => showAppSheet(
                  context: context,
                  builder: (_) => const _CreateWorkspaceSheet(),
                ),
              ),
            ],
          ),
          children: [
            if (settings.isLoading && settings.workspaces.isEmpty)
              const _LoadingRow()
            else if (settings.workspaces.isEmpty)
              const AppDetailRow(
                icon: AppIcons.info,
                label: 'No workspaces yet. Create one to keep your data apart.',
              )
            else
              for (final ws in settings.workspaces)
                AppListRow(
                  icon: AppIcons.personWorkspace,
                  title: ws.name,
                  subtitle: ws.slug,
                  trailing: ws.id == activeId
                      ? const AppBadge(
                          label: 'Active',
                          variant: AppBadgeVariant.primary,
                        )
                      : null,
                  onTap: () => _options(context, ws, ws.id == activeId),
                ),
          ],
        );
      },
    );
  }
}

// Members

class _MembersPage extends StatelessWidget {
  const _MembersPage();

  void _reload() {
    final ws = Stores.auth.activeWorkspace ?? '';
    if (ws.isEmpty) return;
    Stores.invites.loadMembers(ws);
    Stores.invites.loadCatalogue();
  }

  Future<void> _remove(
    BuildContext context,
    WorkspaceMemberDetail member,
  ) async {
    final ws = Stores.auth.activeWorkspace ?? '';
    final confirmed = await showAppDialog(
      context: context,
      title: member.isSelf ? 'Leave workspace?' : 'Remove member?',
      message: member.isSelf
          ? 'You lose access to this workspace.'
          : '${member.email} loses access to this workspace.',
      confirmLabel: member.isSelf ? 'Leave' : 'Remove',
      confirmIcon: member.isSelf ? AppIcons.boxArrowLeft : AppIcons.trash,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final store = Stores.invites;
    final ok = await store.removeMember(ws, member.id);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(
        context,
        member.isSelf ? 'You left the workspace.' : 'Member removed.',
      );
      if (member.isSelf) await Stores.auth.initialize();
    } else {
      AppToast.error(
        context,
        store.error?.description ?? 'Couldn’t remove the member. Try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.invites;
    return Observer(
      builder: (_) {
        final error = store.membersError;
        if (error != null && store.members.isEmpty) {
          return AppLoadError(
            title: error.title,
            message: error.description,
            onRetry: _reload,
          );
        }
        final total = store.catalogue.length;
        return AppListGroup(
          title: 'Members',
          footer: const Text('Who has access, and what they can do.'),
          children: [
            if (store.isLoadingMembers && store.members.isEmpty)
              const _LoadingRow()
            else if (store.members.isEmpty)
              const AppDetailRow(
                icon: AppIcons.info,
                label: 'No members yet. Invite someone to work with you here.',
              )
            else
              for (final member in store.members)
                _memberRow(context, member, total),
          ],
        );
      },
    );
  }

  Widget _memberRow(
    BuildContext context,
    WorkspaceMemberDetail member,
    int total,
  ) {
    final store = Stores.invites;
    final title = member.isSelf ? '${member.email} (you)' : member.email;
    final actions = [
      if (store.canManageMembers)
        AppSheetAction(
          icon: AppIcons.shieldCheck,
          label: 'Edit permissions',
          onTap: () => showMemberPermissionsSheet(
            context: context,
            workspaceId: Stores.auth.activeWorkspace ?? '',
            member: member,
          ),
        ),
      if (store.canManageMembers || member.isSelf)
        AppSheetAction(
          icon: AppIcons.xCircle,
          label: member.isSelf ? 'Leave workspace' : 'Remove member',
          destructive: true,
          // The workspace must keep someone able to invite, so the last one
          // cannot be removed at all.
          enabled: !member.isLastAdmin,
          onTap: () => _remove(context, member),
        ),
    ];
    return AppListRow(
      icon: AppIcons.person,
      title: title,
      subtitle: permissionCountLabel(member.permissions.length, total),
      trailing: member.isLastAdmin
          ? const AppBadge(icon: AppIcons.shieldLock, label: 'Only admin')
          : null,
      onTap: actions.isEmpty
          ? null
          : () => showAppOptionsSheet(
              context: context,
              title: title,
              actions: actions,
            ),
    );
  }
}

// Invites

class _InvitesPage extends StatelessWidget {
  const _InvitesPage();

  Future<void> _create(BuildContext context) async {
    final ws = Stores.auth.activeWorkspace ?? '';
    if (ws.isEmpty) {
      AppToast.error(context, 'Select a workspace first.');
      return;
    }
    await showInviteCreateSheet(context: context, workspaceId: ws);
    if (context.mounted) await Stores.invites.load(ws);
  }

  /// Withdrawing cannot be undone — the key stops working for whoever holds
  /// it — so it asks first.
  Future<void> _withdraw(BuildContext context, Invite invite) async {
    final label = invite.label.isEmpty ? 'this invite' : invite.label;
    final confirmed = await showAppDialog(
      context: context,
      title: 'Withdraw invite?',
      message: 'The key for $label stops working. Nobody can join with it.',
      confirmLabel: 'Withdraw',
      confirmIcon: AppIcons.xCircle,
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final store = Stores.invites;
    final ok = await store.revoke(invite.id);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'Invite withdrawn.');
    } else {
      AppToast.error(
        context,
        store.error?.description ?? 'Couldn’t withdraw the invite. Try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.invites;
    return Observer(
      builder: (_) {
        final open = store.invites.where((i) => i.isActive).toList();
        final total = store.catalogue.length;
        if (open.isEmpty && !store.isLoading) {
          return AppEmptyState(
            icon: AppIcons.personPlus,
            title: 'Work together in this workspace',
            subtitle:
                'Send someone an invite key. They join with the permissions '
                'you choose, and nothing more.',
            example: const AppEmptyExample(
              title: 'Accountant',
              detail: '3 of 16 permissions · valid 7 days',
              badge: 'open',
            ),
            steps: const [
              AppEmptyStep(
                'Choose what they can do',
                'Read records, answer requests, and so on',
              ),
              AppEmptyStep('Hand them the key', 'As a link or a QR code'),
              AppEmptyStep(
                'Withdraw it if unused',
                'You can take it back until someone uses it',
              ),
            ],
            action: AppButton(
              icon: AppIcons.plus,
              label: 'New invite',
              onTap: () => _create(context),
            ),
          );
        }
        return AppListGroup(
          title: 'Pending invites',
          footer: const Text('Keys you sent that nobody has used yet.'),
          trailing: _HeaderButton(
            icon: AppIcons.plus,
            label: 'New',
            onTap: () => _create(context),
          ),
          children: [
            if (store.isLoading && open.isEmpty)
              const _LoadingRow()
            else
              for (final invite in open)
                AppListRow(
                  icon: AppIcons.personPlus,
                  title: invite.label.isEmpty ? 'Invite' : invite.label,
                  subtitle: [
                    permissionCountLabel(
                      permissionsFromScopes(
                        store.catalogue,
                        invite.permissions,
                      ).length,
                      total,
                    ),
                    if (invite.isSingleUse) 'single use',
                    // Only shown when the invite is pinned to an address.
                    ?invite.email,
                  ].join(' · '),
                  onTap: () => showAppOptionsSheet(
                    context: context,
                    title: invite.label.isEmpty ? 'Invite' : invite.label,
                    actions: [
                      AppSheetAction(
                        icon: AppIcons.xCircle,
                        label: 'Withdraw invite',
                        destructive: true,
                        onTap: () => _withdraw(context, invite),
                      ),
                    ],
                  ),
                ),
          ],
        );
      },
    );
  }
}

// Identities

class _IdentitiesPage extends StatelessWidget {
  const _IdentitiesPage();

  Future<void> _confirmRevoke(BuildContext context, Identity identity) async {
    final store = Stores.identities;
    final confirmed = await showAppDialog(
      context: context,
      title: 'Revoke ${identity.name}?',
      message:
          'Nobody can trust it any more. Anyone who checks it, here or on '
          'another server, learns this within the hour. Links and requests '
          'it signed keep working, but no longer show as verified. Its key is '
          'erased from this device.\n\n'
          'You can’t undo this. Create a new identity to sign again.',
      confirmLabel: 'Revoke',
      confirmIcon: AppIcons.xCircle,
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final ok = await store.revokeIdentity(identity.id);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'Identity revoked');
    } else {
      AppToast.error(
        context,
        'Couldn’t revoke the identity',
        subtitle: store.errorMessage,
      );
    }
  }

  Future<void> _setPrimary(BuildContext context, Identity id) async {
    final store = Stores.identities;
    final ok = await store.setPrimary(id.id);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'Primary identity updated');
    } else {
      AppToast.error(
        context,
        'Couldn’t set primary identity',
        subtitle: store.errorMessage,
      );
    }
  }

  /// Whether this server's own domain check vouches for the domain the
  /// identity was issued under.
  TrustCheckState _claimState(String domain) =>
      Stores.settings.claimStateFor(domain);

  void _options(BuildContext context, Identity id) {
    final store = Stores.identities;
    showAppOptionsSheet(
      context: context,
      title: id.name,
      subtitle: id.shortFingerprint,
      actions: [
        AppSheetAction(
          icon: AppIcons.copy,
          label: 'Copy public key',
          onTap: () {
            Clipboard.setData(ClipboardData(text: id.publicKey));
            AppToast.success(context, 'Public key copied');
          },
        ),
        if (!id.isPrimary && !id.isRevoked)
          AppSheetAction(
            icon: AppIcons.stars,
            label: 'Set as primary',
            onTap: () => _setPrimary(context, id),
          ),
        // Revoking, not deleting, is the answer to a leaked key: the holder
        // of a copy keeps passing every check until this server says
        // otherwise, and it can only say so about an identity it still has a
        // record of.
        if (!id.isRevoked)
          AppSheetAction(
            icon: AppIcons.shieldSlash,
            label: 'Revoke',
            destructive: true,
            onTap: () => _confirmRevoke(context, id),
          ),
        AppSheetAction(
          icon: AppIcons.trash,
          label: 'Delete',
          destructive: true,
          // The primary signs by default; demote it first.
          enabled: !id.isPrimary,
          onTap: () => store.deleteIdentity(id.id),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.identities;
    return Observer(
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DeviceKeyAlert(),
          if (store.identities.isEmpty && !store.isLoading)
            AppEmptyState(
              icon: AppIcons.personBoundingBox,
              title: 'Prove it’s really you',
              subtitle:
                  'Your identity lets people check that a link or answer '
                  'came from you. Its key stays on this device.',
              example: const AppEmptyExample(
                title: 'Laptop',
                detail: 'Primary · 3fa2c1…',
                badge: 'verified',
              ),
              steps: const [
                AppEmptyStep('Create one on this device', 'It takes a second'),
                AppEmptyStep(
                  'Sign what you share and answer',
                  'People see it really came from you',
                ),
                AppEmptyStep(
                  'Revoke it if a device is lost',
                  'Anyone who checks it learns this',
                ),
              ],
              action: AppButton(
                icon: AppIcons.plus,
                label: 'New identity',
                onTap: () => showAppSheet(
                  context: context,
                  builder: (_) => const _CreateIdentitySheet(),
                ),
              ),
            )
          else
            AppListGroup(
              title: 'Identities',
              footer: const Text('Prove that what you send comes from you.'),
              trailing: _HeaderButton(
                icon: AppIcons.plus,
                label: 'New',
                onTap: () => showAppSheet(
                  context: context,
                  builder: (_) => const _CreateIdentitySheet(),
                ),
              ),
              children: [
                if (store.isLoading && store.identities.isEmpty)
                  const _LoadingRow()
                else
                  for (final id in store.identities)
                    AppListRow(
                      icon: AppIcons.personBoundingBox,
                      title: id.name,
                      subtitle: id.isPrimary
                          ? 'Primary · ${id.shortFingerprint}'
                          : id.shortFingerprint,
                      // A revoked identity proves nothing, so its domain claim is
                      // moot; otherwise the claim is stated the one way it may be.
                      trailing: id.isRevoked
                          ? const AppBadge(
                              icon: AppIcons.shieldSlash,
                              label: 'Revoked',
                            )
                          : store.keysChecked && !store.hasLocalKey(id.id)
                          ? const AppBadge(
                              icon: AppIcons.keyOff,
                              label: keyElsewhereLabel,
                              variant: AppBadgeVariant.outline,
                            )
                          : id.domainAtIssue.isNotEmpty
                          ? TrustClaimBadge(
                              domain: id.domainAtIssue,
                              state: _claimState(id.domainAtIssue),
                            )
                          : null,
                      onTap: () => _options(context, id),
                    ),
              ],
            ),
        ],
      ),
    );
  }
}

// API keys

class _ApiKeysPage extends StatelessWidget {
  const _ApiKeysPage();

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
                'Give your scripts and integrations a key to this '
                'workspace. It does only what you allow, and never opens the '
                'vault.',
            example: const AppEmptyExample(
              title: 'Import script',
              detail: 'links:read, requests:create · expires in 90 days',
              badge: 'active',
            ),
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
            'Keys for your scripts. A key never opens the vault.',
          ),
          trailing: _HeaderButton(
            icon: AppIcons.plus,
            label: 'New',
            onTap: () => openApiKeyCreateSheet(context),
          ),
          children: [
            if (store.isLoading && store.apiKeys.isEmpty)
              const _LoadingRow()
            else
              for (final key in store.apiKeys) ApiKeyRow(apiKey: key),
          ],
        );
      },
    );
  }
}

// Templates

class _TemplatesPage extends StatelessWidget {
  const _TemplatesPage();

  String _summary(Template template) {
    final sections = template.schema['sections'] as List<dynamic>? ?? [];
    final records = template.schema['records'] as List<dynamic>? ?? [];
    return '${sections.length} '
        '${sections.length == 1 ? 'section' : 'sections'} · '
        '${records.length} root '
        '${records.length == 1 ? 'record' : 'records'}';
  }

  Widget _row(BuildContext context, Template template) {
    return AppListRow(
      icon: AppIcons.cardList,
      title: template.name,
      subtitle: _summary(template),
      // A built-in template is the same for everyone and cannot be changed.
      onTap: template.isBuiltin
          ? null
          : () => showAppOptionsSheet(
              context: context,
              title: template.name,
              actions: [
                AppSheetAction(
                  icon: AppIcons.pencil,
                  label: 'Edit',
                  onTap: () => openTemplateEditorSheet(
                    context,
                    initialTemplate: template,
                  ),
                ),
                AppSheetAction(
                  icon: AppIcons.trash,
                  label: 'Delete',
                  destructive: true,
                  onTap: () => confirmDeleteTemplate(context, template.id),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.templates;
    return Observer(
      builder: (_) {
        final builtins = store.templates.where((t) => t.isBuiltin).toList();
        final own = store.templates.where((t) => !t.isBuiltin).toList();
        final loading = store.isLoading && store.templates.isEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppListGroup(
              title: 'Your templates',
              footer: const Text(
                'Set up what a request asks for once, then reuse it.',
              ),
              trailing: _HeaderButton(
                icon: AppIcons.plus,
                label: 'New',
                onTap: () => openTemplateEditorSheet(context),
              ),
              children: [
                if (loading)
                  const _LoadingRow()
                else if (own.isEmpty)
                  const AppDetailRow(
                    icon: AppIcons.info,
                    label: 'No templates of your own yet.',
                  )
                else
                  for (final t in own) _row(context, t),
              ],
            ),
            if (builtins.isNotEmpty)
              AppListGroup(
                title: 'Built-in',
                noun: 'templates',
                collapsed: true,
                children: [for (final t in builtins) _row(context, t)],
              ),
          ],
        );
      },
    );
  }
}

// Domain verification

/// Runs the server-side DNS trust check (`/api/verify-peer` against this
/// server's own advertised domain) so the operator can confirm their
/// `_revoked` TXT record is published and pins the right root key — the proof
/// that lets recipients trust what they share. Surfaces the result as the same
/// [AppTrustBadge] used on the request-fill screen.
class _DomainPage extends StatelessWidget {
  const _DomainPage();

  @override
  Widget build(BuildContext context) {
    final store = Stores.settings;
    return Observer(
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppListGroup(
            title: 'DNS check',
            trailing: const SizedBox.shrink(),
            footer: const Text(
              'Run this after you add the _revoked DNS record. It confirms '
              'people can check that what you send comes from your domain.',
            ),
            children: [
              if (store.domainVerdict != null)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: AppTrustBadge(verdict: store.domainVerdict!),
                )
              else
                const AppDetailRow(
                  icon: AppIcons.server,
                  label: 'Status',
                  value: 'Not checked yet',
                ),
            ],
          ),
          if (store.domainError != null) ...[
            AppErrorText(store.domainError!),
            AppSpacing.gapMd,
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              icon: AppIcons.shieldCheck,
              label: 'Check DNS',
              style: AppButtonStyle.accent,
              busy: store.isCheckingDomain,
              onTap: store.checkDomain,
            ),
          ),
        ],
      ),
    );
  }
}

// Create sheets

String _slugify(String s) =>
    s.toLowerCase().replaceAll(' ', '-').replaceAll(RegExp(r'[^a-z0-9\-]'), '');

class _CreateWorkspaceSheet extends StatefulWidget {
  const _CreateWorkspaceSheet();

  @override
  State<_CreateWorkspaceSheet> createState() => _CreateWorkspaceSheetState();
}

class _CreateWorkspaceSheetState extends State<_CreateWorkspaceSheet> {
  @override
  void initState() {
    super.initState();
    Stores.settings.workspaceName.addListener(
      () => Stores.settings.workspaceSlug.text = _slugify(
        Stores.settings.workspaceName.text,
      ),
    );
  }

  Future<void> _submit() async {
    final settings = Stores.settings;
    final auth = Stores.auth;
    if (settings.workspaceName.text.trim().isEmpty ||
        settings.workspaceSlug.text.trim().isEmpty) {
      return;
    }
    settings.setSubmitting(true);
    final ok = await settings.createWorkspace(
      name: settings.workspaceName.text.trim(),
      slug: settings.workspaceSlug.text.trim(),
      userId: auth.userId,
    );
    if (!mounted) return;
    if (ok) {
      await auth.initialize();
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.success(context, 'Workspace created');
    } else {
      settings.setSubmitting(false);
      AppToast.error(context, 'Couldn’t create workspace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxs,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('New workspace').header,
          const SizedBox(height: AppSpacing.xs),
          const Text('Keep personal, team and client data apart.').muted.small,
          const SizedBox(height: AppSpacing.lg),
          const Text('Name').small,
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: Stores.settings.workspaceName,
            hint: 'My Team',
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('Slug').small,
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: Stores.settings.workspaceSlug,
            hint: 'my-team',
            inputFormatters: [
              TextInputFormatter.withFunction((oldValue, newValue) {
                final text = _slugify(newValue.text);
                return TextEditingValue(
                  text: text,
                  selection: TextSelection.collapsed(offset: text.length),
                );
              }),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  style: AppButtonStyle.accent,
                  onTap: Stores.settings.isSubmittingDrawer
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(
                  icon: AppIcons.plus,
                  label: 'Create workspace',
                  busy: Stores.settings.isSubmittingDrawer,
                  onTap: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreateIdentitySheet extends StatefulWidget {
  const _CreateIdentitySheet();

  @override
  State<_CreateIdentitySheet> createState() => _CreateIdentitySheetState();
}

class _CreateIdentitySheetState extends State<_CreateIdentitySheet> {
  Future<void> _submit() async {
    if (Stores.settings.identityName.text.trim().isEmpty) return;
    Stores.settings.setSubmitting(true);
    final ok = await Stores.identities.createIdentity(
      name: Stores.settings.identityName.text.trim(),
      isPrimary: Stores.settings.identityIsPrimary,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      AppToast.success(context, 'Identity created');
    } else {
      Stores.settings.setSubmitting(false);
      AppToast.error(context, 'Couldn’t create identity');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxs,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('New identity').header,
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Let people check that what you share came from you. Its key stays '
            'on this device.',
          ).muted.small,
          const SizedBox(height: AppSpacing.lg),
          const Text('Profile name').small,
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: Stores.settings.identityName,
            hint: 'e.g. Recruiter, Max Musterman, Personal',
          ),
          const SizedBox(height: AppSpacing.sm),
          AppFormToggleRow(
            label: 'Make it your primary identity',
            subtitle: 'Used by default when you sign shares or requests.',
            value: Stores.settings.identityIsPrimary,
            onChanged: Stores.settings.setIdentityPrimary,
            inset: false,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  style: AppButtonStyle.accent,
                  onTap: Stores.settings.isSubmittingDrawer
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(
                  icon: AppIcons.shieldCheck,
                  label: 'Create identity',
                  busy: Stores.settings.isSubmittingDrawer,
                  onTap: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
