import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/router/return_to.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/identity.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/models/workspace.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/access_sheet.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_collection_header.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_create_sheet.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/device_key_alert.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/app_trust_badge.dart';
import 'package:revoked_app/core/widgets/trust_panel.dart';
import 'package:revoked_app/features/settings/view/groups_sheet.dart';
import 'package:revoked_app/features/api_keys/view/api_keys_group.dart';
import 'package:revoked_app/features/connections/view/connections_section.dart';
import 'package:revoked_app/features/identities/view/identity_replace_sheet.dart';
import 'package:revoked_app/features/invites/view/invite_create_sheet.dart';
import 'package:revoked_app/features/invites/view/invite_join_sheet.dart';
import 'package:revoked_app/features/invites/view/member_permissions_sheet.dart';
import 'package:revoked_app/features/passkeys/view/passkeys_section.dart';
import 'package:revoked_app/features/two_factor/view/two_factor_section.dart';
import 'package:revoked_app/features/templates/view/templates_screen.dart';
import 'package:revoked_app/features/sealing/view/sealing_section.dart';
import 'package:revoked_app/features/settings/view/appearance_page.dart';
import 'package:revoked_app/features/settings/view/features_page.dart';
import 'package:revoked_app/features/settings/view/mcp_page.dart';
import 'package:revoked_app/features/webhooks/view/webhooks_page.dart';

/// A topic still settling: alpha may change or go away, beta is close to
/// done.
enum SettingsStage {
  alpha('Alpha'),
  beta('Beta');

  const SettingsStage(this.label);

  final String label;
}

/// The settings topics, each a page of its own under Settings — opened from
/// the settings list the way a record is opened from the vault.
enum SettingsPage {
  appearance('appearance', 'Appearance and accessibility'),
  features('features', 'Features'),
  passkeys('passkeys', 'Passkeys and two-factor'),
  encryption('encryption', 'End-to-end encryption'),
  workspaces('workspaces', 'Workspaces'),
  members('members', 'Members'),
  invites('invites', 'Invites'),
  identities('identities', 'Identities'),
  connectedTools('connected-tools', 'Connected tools'),
  apiKeys('api-keys', 'API keys'),
  mcp('mcp', 'AI assistant (MCP)', isNew: true),
  webhooks('webhooks', 'Webhooks', isNew: true),
  templates('templates', 'Templates'),
  domain('domain', 'Domain verification');

  const SettingsPage(this.slug, this.title, {this.isNew = false})
    : stage = null;

  final String slug;
  final String title;

  /// Marks a topic added recently, with a "New" badge on its row.
  final bool isNew;

  /// How settled the topic is; null once it is stable.
  final SettingsStage? stage;

  /// Templates live in the vault now; every other topic under Settings.
  String get route =>
      this == templates ? AppRoutes.templates : AppRoutes.settingsPage(slug);

  /// The same content heading and supporting copy as the main collections.
  String get description => switch (this) {
    appearance => 'Make Revoked comfortable to read and use on this device.',
    features => 'Choose which parts of Revoked appear in your navigation.',
    passkeys => 'Manage how you sign in and add another layer of protection.',
    encryption => 'Control which devices can open your encrypted records.',
    workspaces => 'Separate your records, members and access into spaces.',
    members => 'See who has access to this workspace and what they can do.',
    invites => 'Invite people to your workspace with the access they need.',
    identities => 'Manage the identities that sign your shares and responses.',
    connectedTools =>
      'Review the services you connected and the access you gave them.',
    apiKeys => 'Give scripts and applications scoped access to this workspace.',
    mcp => 'Connect an AI assistant to Revoked with permissions you control.',
    webhooks => 'Send workspace events to your services and review deliveries.',
    templates => 'Reusable blueprints for records and request forms.',
    domain => 'Check that your server’s domain vouches for its signing key.',
  };

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
      _load();
    });
  }


  void _load() {
    final auth = Stores.auth;
    if (!auth.isAuthenticated) return;
    final ws = auth.activeWorkspace ?? '';
    switch (widget.page) {
      case SettingsPage.appearance:
      case SettingsPage.passkeys:
      case SettingsPage.domain:
        Stores.settings.ensureDomainChecked();
      case SettingsPage.mcp:
        // Load themselves.
        break;
      case SettingsPage.features:
        Stores.features.loadIfDue();
        // Which features the workspace allows comes from the roster.
        if (ws.isNotEmpty) Stores.invites.loadMembers(ws);
      case SettingsPage.encryption:
        // Members after the device list: whether the server shows others this
        // person's own list is checked against it.
        Stores.keys.load().then((_) {
          if (ws.isNotEmpty) Stores.memberKeys.load(ws);
        });
      case SettingsPage.workspaces:
        Stores.settings.loadWorkspaces(auth.userId);
        Stores.invites.loadCatalogue();
      case SettingsPage.members:
        Stores.settings.loadWorkspaces(auth.userId);
        if (ws.isNotEmpty) Stores.invites.loadMembers(ws);
        // The total is what "3 of 16" is measured against.
        Stores.invites.loadCatalogue();
      case SettingsPage.invites:
        if (ws.isNotEmpty) Stores.invites.load(ws);
        // Whether this member may invite decides the New invite button.
        if (ws.isNotEmpty) Stores.invites.loadMembers(ws);
        Stores.invites.loadCatalogue();
      case SettingsPage.identities:
        Stores.identities.loadIdentities();
        Stores.settings.ensureDomainChecked();
      case SettingsPage.connectedTools:
        Stores.connections.load();
        Stores.signIns.loadIfDue();
        Stores.invites.loadCatalogue();
      case SettingsPage.apiKeys:
        Stores.apiKeys.loadApiKeys();
        Stores.invites.loadCatalogue();
        Stores.vault.loadIfDue();
      case SettingsPage.webhooks:
        Stores.webhooks.loadIfDue();
      case SettingsPage.templates:
        Stores.templates.loadTemplates(ws);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageBody(
      children: [
        // The page names itself here, so the top bar carries no title.
        AppCollectionHeader(
          title: widget.page.title,
          description: widget.page.description,
          onBack: () => goBack(context, AppRoutes.settings),
        ),
        switch (widget.page) {
          SettingsPage.appearance => const AppearancePage(),
          SettingsPage.features => const FeaturesPage(),
          SettingsPage.passkeys => const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PasskeysSection(),
              AppSpacing.gapXxl,
              TwoFactorSection(),
            ],
          ),
          SettingsPage.encryption => const SealingSection(),
          SettingsPage.workspaces => const _WorkspacesPage(),
          SettingsPage.members => const _MembersPage(),
          SettingsPage.invites => const _InvitesPage(),
          SettingsPage.identities => const _IdentitiesPage(),
          SettingsPage.connectedTools => const ConnectionsList(),
          SettingsPage.apiKeys => const ApiKeysGroup(),
          SettingsPage.mcp => const McpPage(),
          SettingsPage.webhooks => const WebhooksList(),
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
      child: AppListSkeleton(embedded: true),
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
          'All records, files, templates, members and API keys are deleted. '
          'Every share and request link stops working immediately, and all '
          'identities are revoked. This cannot be undone.',
      confirmLabel: 'Delete workspace',
      cancelLabel: 'Cancel',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final wasActive = auth.activeWorkspace == workspace.id;
    if (!await settings.deleteWorkspace(auth.userId, workspace.id)) {
      if (context.mounted) {
        AppToast.error(
          context,
          'The workspace could not be deleted',
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
            label: 'Switch',
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
        // The active workspace's groups; listing them is open to everyone.
        if (active)
          AppSheetAction(
            icon: AppIcons.person,
            label: 'Groups',
            onTap: () => openGroupsSheet(context),
          ),
        if (Stores.settings.canManageWorkspace(ws.id, Stores.invites.catalogue))
          AppSheetAction(
            icon: AppIcons.personWorkspace,
            label: 'Default visibility',
            onTap: () => openDefaultVisibilitySheet(
              context,
              workspaceId: ws.id,
              current: {
                for (final key in Workspace.builtInAudience.keys)
                  key: ws.audienceFor(key),
              },
              save: (defaults) =>
                  Stores.settings.setDefaultAudience(ws.id, defaults),
              saveError: () => Stores.settings.errorMessage,
            ),
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
          footer: const Text('Separate spaces for records, members and keys.'),
          trailing: _HeaderButton(
            // Not a plus: joining an existing workspace is not a second way
            // to create one.
            icon: AppIcons.key,
            label: 'Join',
            onTap: () => showInviteJoinSheet(context: context),
          ),
          children: [
            if (settings.isLoading && settings.workspaces.isEmpty)
              const _LoadingRow()
            else if (settings.workspaces.isEmpty)
              const AppDetailRow(icon: AppIcons.info, label: 'No workspaces.')
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
          ? 'Access to this workspace ends.'
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
        member.isSelf ? 'Workspace left.' : 'Member removed.',
      );
      if (member.isSelf) await Stores.auth.initialize();
    } else {
      AppToast.error(
        context,
        store.error?.description ?? 'The member could not be removed.',
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
          footer: const Text('Members and their permissions.'),
          children: [
            if (store.isLoadingMembers && store.members.isEmpty)
              const _LoadingRow()
            else if (store.members.isEmpty)
              const AppDetailRow(
                icon: AppIcons.info,
                label: 'No other members.',
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

  /// Withdrawing cannot be undone — the key stops working for whoever holds
  /// it — so it asks first.
  Future<void> _withdraw(BuildContext context, Invite invite) async {
    final label = invite.label.isEmpty ? 'this invite' : invite.label;
    final confirmed = await showAppDialog(
      context: context,
      title: 'Withdraw invite?',
      message:
          'The key for $label stops working and can no longer be used to join.',
      confirmLabel: 'Withdraw',
      confirmIcon: AppIcons.xCircle,
      cancelLabel: 'Cancel',
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
        store.error?.description ?? 'The invite could not be withdrawn.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _list(context);
  }

  Widget _list(BuildContext context) {
    final store = Stores.invites;
    return Observer(
      builder: (_) {
        final open = store.invites.where((i) => i.isActive).toList();
        final total = store.catalogue.length;
        if (open.isEmpty && !store.isLoading) {
          return AppEmptyState(
            icon: AppIcons.personPlus,
            title: 'No pending invites',
            subtitle:
                'Invite keys add members to this workspace with the selected '
                'permissions only.',
            action: AppButton(
              icon: AppIcons.plus,
              label: 'New invite',
              style: AppButtonStyle.accent,
              onTap: () => openInviteCreateSheet(context),
            ),
            example: const AppEmptyExample(
              title: 'Accountant',
              detail: '3 of 16 permissions · valid 7 days',
              badge: 'open',
            ),
            steps: const [
              AppEmptyStep('Permissions', 'Records, requests and more'),
              AppEmptyStep('Key', 'Delivered as a link or QR code'),
              AppEmptyStep('Withdrawal', 'Possible until the key is used'),
            ],
          );
        }
        return AppListGroup(
          title: 'Pending invites',
          footer: const Text('Invite keys not yet used.'),
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
          'The identity is no longer trusted. Checks here and on other '
          'servers reflect this within the hour. Links and requests it '
          'signed keep working but are no longer shown as verified. Its key '
          'is erased from this device.\n\n'
          'This cannot be undone. Signing again requires a new identity.',
      confirmLabel: 'Revoke',
      confirmIcon: AppIcons.xCircle,
      cancelLabel: 'Cancel',
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
        'The identity could not be revoked',
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
        'The primary identity could not be set',
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
        // The old key vouches for the identity that replaces it, so it has to
        // be on this device.
        if (!id.isRevoked && store.hasLocalKey(id.id))
          AppSheetAction(
            icon: AppIcons.arrowRepeat,
            label: 'Replace',
            onTap: () => openIdentityReplaceSheet(context, id),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DeviceKeyAlert(),
        Observer(builder: (_) => _list(context)),
      ],
    );
  }

  Widget _list(BuildContext context) {
    final store = Stores.identities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (store.identities.isEmpty && !store.isLoading)
          AppEmptyState(
            icon: AppIcons.personBoundingBox,
            title: 'No identities',
            subtitle:
                'An identity signs links and responses so recipients can '
                'verify their origin. Its key stays on this device.',
            action: AppButton(
              icon: AppIcons.plus,
              label: 'New identity',
              style: AppButtonStyle.accent,
              onTap: () => openIdentityCreateSheet(context),
            ),
            example: const AppEmptyExample(
              title: 'Laptop',
              detail: 'Primary · 3fa2c1…',
              badge: 'verified',
            ),
            steps: const [
              AppEmptyStep('Key pair', 'Generated on this device'),
              AppEmptyStep('Signature', 'Attached to shares and responses'),
              AppEmptyStep('Revocation', 'Visible to every verifier'),
            ],
          )
        else
          AppListGroup(
            title: 'Identities',
            footer: const Text('Signing identities for shares and responses.'),
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
      // A built-in template is the same for everyone and cannot be changed;
      // it opens to be looked at, and copied.
      onTap: template.isBuiltin
          ? () => openTemplatePreviewSheet(context, template)
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
                  icon: AppIcons.dashboard,
                  label: 'Preview',
                  onTap: () => openTemplatePreviewSheet(context, template),
                ),
                // Only the owner sets who sees it; older templates have none.
                if (template.owner == Stores.auth.userId)
                  AppSheetAction(
                    icon: AppIcons.personWorkspace,
                    label: 'Visibility',
                    onTap: () => openAccessSheet(
                      context,
                      area: AccessArea.templates,
                      id: template.id,
                      name: template.name,
                      audienceKind: template.audienceKind,
                      editing: template.editing,
                      save: (kind, editing, groups) =>
                          Stores.templates.setTemplateAudience(
                            template.id,
                            kind: kind,
                            editing: editing,
                            groups: groups,
                          ),
                      saveError: () => Stores.templates.errorMessage,
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
              title: 'Workspace templates',
              footer: const Text('Reusable field sets for requests.'),
              children: [
                if (loading)
                  const _LoadingRow()
                else if (own.isEmpty)
                  const AppDetailRow(
                    icon: AppIcons.info,
                    label: 'No custom templates.',
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
          if (store.domainVerdict case final verdict?) ...[
            AppTrustBadge(verdict: verdict),
            AppSpacing.gapXxl,
          ],
          AppListGroup(
            title: 'DNS check',
            trailing: const SizedBox.shrink(),
            footer: const Text(
              'Verifies the _revoked DNS record, which lets recipients confirm '
              'that shares and responses originate from this domain.',
            ),
            children: [
              AppDetailRow(
                icon: AppIcons.server,
                label: 'Domain',
                value:
                    store.domainVerdict?.domain ??
                    Uri.tryParse(Stores.api.baseUrl)?.host ??
                    '',
              ),
              if (store.domainVerdict == null || store.isCheckingDomain)
                AppDetailRow(
                  icon: AppIcons.shieldCheck,
                  label: 'Status',
                  value: store.isCheckingDomain ? 'Checking…' : 'Not checked',
                ),
              if (store.domainVerdict?.rootFingerprint case final fingerprint?)
                AppDetailRow(
                  icon: AppIcons.key,
                  label: 'Root key',
                  value: fingerprint,
                  valueMono: true,
                ),
            ],
          ),
          if (store.domainError != null) ...[
            AppSpacing.gapSm,
            AppErrorText(store.domainError!),
          ],
        ],
      ),
    );
  }
}

// Create sheets

String _slugify(String s) =>
    s.toLowerCase().replaceAll(' ', '-').replaceAll(RegExp(r'[^a-z0-9\-]'), '');

/// Opens the new-workspace form.
Future<void> openWorkspaceCreateSheet(BuildContext context) =>
    showAppCreateSheet(
      context,
      label: 'New workspace',
      onOpen: Stores.settings.resetWorkspaceDraft,
      form: (close) => _CreateWorkspaceSheet(onClose: close),
    );

class _CreateWorkspaceSheet extends StatefulWidget {
  final VoidCallback onClose;

  const _CreateWorkspaceSheet({required this.onClose});

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
      AppToast.success(context, 'Workspace created');
      widget.onClose();
    } else {
      settings.setSubmitting(false);
      AppToast.error(context, 'The workspace could not be created');
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
          const Text(
            'Separate records, members and keys by context.',
          ).muted.small,
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
                      : widget.onClose,
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

/// Opens the new-identity form.
Future<void> openIdentityCreateSheet(BuildContext context) =>
    showAppCreateSheet(
      context,
      label: 'New identity',
      onOpen: Stores.settings.resetIdentityDraft,
      form: (close) => _CreateIdentitySheet(onClose: close),
    );

class _CreateIdentitySheet extends StatefulWidget {
  final VoidCallback onClose;

  const _CreateIdentitySheet({required this.onClose});

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
      AppToast.success(context, 'Identity created');
      widget.onClose();
    } else {
      Stores.settings.setSubmitting(false);
      AppToast.error(context, 'The identity could not be created');
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
            'Signs shares and responses so recipients can verify their '
            'origin. Its key stays on this device.',
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
            label: 'Primary identity',
            subtitle: 'Used by default to sign shares and requests.',
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
                      : widget.onClose,
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
