import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/identity.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/models/workspace.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_entity_card.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_tabs.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/app_trust_badge.dart';
import 'package:revoked_app/core/widgets/trust_panel.dart';
import 'package:revoked_app/features/api_keys/view/api_key_create_sheet.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/identities/store/identities_store.dart';
import 'package:revoked_app/features/invites/view/invite_create_sheet.dart';
import 'package:revoked_app/features/invites/view/invite_join_sheet.dart';
import 'package:revoked_app/features/invites/view/member_permissions_sheet.dart';
import 'package:revoked_app/features/settings/store/settings_store.dart';
import 'package:revoked_app/features/templates/view/templates_screen.dart';

/// The Account tab — a single, calm, scrollable surface grouped into sections
/// (profile, workspaces, identities, developer tools, connection) instead of
/// the old crude pill-tabs. Create flows are bottom sheets, matching the rest
/// of the app; signing out lives quietly at the bottom rather than as a red
/// button up top.
class SettingsScreen extends StatefulWidget {
  /// 0 = Account, 1 = Workspace, 2 = Developer.
  final int initialTab;

  const SettingsScreen({super.key, this.initialTab = 0});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Stores.auth;
      if (auth.isAuthenticated) {
        Stores.settings.loadWorkspaces(auth.userId);
        Stores.identities.loadIdentities();
        Stores.apiKeys.loadApiKeys();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Stores.auth;
    final settings = Stores.settings;

    return Column(
      children: [
        Flexible(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.sm),
            child: Observer(
              builder: (context) {
                final activeId = auth.activeWorkspace ?? '';
                return AppTabs(
                  initialIndex: widget.initialTab,
                  labels: const ['Account', 'Workspace', 'Developer'],
                  views: [
                    _accountTab(context, settings, auth, activeId),
                    _workspaceTab(context, settings, auth, activeId),
                    _developerTab(context),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _accountTab(
    BuildContext context,
    SettingsStore settings,
    AuthStore auth,
    String activeId,
  ) {
    final pad = AppSpacing.screenH(context);
    final active = settings.workspaces
        .where((w) => w.id == activeId)
        .cast<Workspace?>()
        .firstWhere((_) => true, orElse: () => null);

    return ListView(
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.sm, pad, AppSpacing.huge),
      children: [
        const _GroupHeader(
          title: 'You',
          subtitle: 'Active workspace and email.',
        ),
        _ProfileCard(
          email: auth.userEmail,
          active: active,
          loading: settings.isLoading && settings.workspaces.isEmpty,
        ),

        const SizedBox(height: AppSpacing.xxl),
        const _GroupHeader(
          title: 'Appearance',
          subtitle: 'Match your system, or force light or dark.',
        ),
        _buildAppearance(context),

        const SizedBox(height: AppSpacing.xxl),
        const _GroupHeader(
          title: 'Session',
          subtitle: 'Sign out of this device, or close your account for good.',
        ),
        _buildAccountActions(context),
      ],
    );
  }

  Widget _buildAccountActions(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Signing out leaves everything on the server — sign back in any '
            'time to pick up where you left off.',
          ).muted.small,
          AppSpacing.gapMd,
          AppButton(
            icon: AppIcons.boxArrowLeft,
            label: 'Log out',
            style: AppButtonStyle.accent,
            onTap: () async {
              final confirmed = await showAppDialog(
                context: context,
                title: 'Log out?',
                message:
                    'Your session on this device ends. Everything stays '
                    'on the server - log back in any time.',
                confirmLabel: 'Log out',
              );
              if (confirmed) await Stores.auth.logout();
            },
          ),
          const SizedBox(height: AppSpacing.xxl),

          const AppDivider(),
          const SizedBox(height: AppSpacing.xxl),

          const Text(
            'Deleting your account removes your workspaces, records and '
            'identities, and stops every share and request link you created. '
            'It cannot be undone.',
          ).muted.small,
          AppSpacing.gapMd,
          Observer(
            builder: (_) => AppButton(
              icon: AppIcons.trash,
              label: 'Delete account',
              style: AppButtonStyle.destructive,
              busy: Stores.auth.isDeletingAccount,
              onTap: () => _confirmDeleteAccount(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete your account?',
      message:
          'Your workspaces, records and identities are deleted, and every '
          'share and request link you created stops working — anyone still '
          'holding one loses access immediately. This cannot be undone.',
      confirmLabel: 'Delete account',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    if (!await Stores.auth.deleteAccount() && context.mounted) {
      AppToast.error(
        context,
        'Could not delete the account',
        subtitle: Stores.auth.errorMessage,
      );
    }
  }

  Future<void> _confirmRevokeIdentity(
    BuildContext context,
    IdentitiesStore store,
    Identity identity,
  ) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Revoke ${identity.name}?',
      message:
          'This server stops vouching for the identity, and anyone verifying '
          'it — here or on another server — is told so within the hour. Links '
          'and requests it signed keep working but no longer show as verified, '
          'and the private key is erased from this device.\n\n'
          'Revoking cannot be undone. Create a new identity to sign again.',
      confirmLabel: 'Revoke',
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
        'Could not revoke the identity',
        subtitle: store.errorMessage,
      );
    }
  }

  Widget _workspaceTab(
    BuildContext context,
    SettingsStore settings,
    AuthStore auth,
    String activeId,
  ) {
    final pad = AppSpacing.screenH(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.sm, pad, AppSpacing.huge),
      children: [
        _GroupHeader(
          title: 'Workspaces',
          subtitle: 'Separate your data and sharing per context.',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _JoinButton(onPressed: () => _openJoinWorkspace(context)),
              AppSpacing.gapSm,
              _AddButton(onPressed: () => _openCreateWorkspace(settings, auth)),
            ],
          ),
        ),
        _buildWorkspaces(context, settings, auth, activeId),

        const SizedBox(height: AppSpacing.xxl),
        _GroupHeader(
          title: 'Pending invites',
          subtitle: 'Keys handed out but not yet used.',
          action: _AddButton(
            onPressed: () => _openCreateInvite(context, activeId),
          ),
        ),
        _InvitesSection(workspaceId: activeId),

        const SizedBox(height: AppSpacing.xxl),
        const _GroupHeader(
          title: 'Members',
          subtitle: 'Who has access, and what they may do.',
        ),
        _MembersSection(workspaceId: activeId),

        const SizedBox(height: AppSpacing.xxl),
        _GroupHeader(
          title: 'Identities',
          subtitle: 'Cryptographic profiles for verified sharing.',
          action: _AddButton(onPressed: _openCreateIdentity),
        ),
        _buildIdentities(context),
      ],
    );
  }

  Widget _developerTab(BuildContext context) {
    final pad = AppSpacing.screenH(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.sm, pad, AppSpacing.huge),
      children: [
        _GroupHeader(
          title: 'API keys',
          subtitle: 'Credentials for programmatic access.',
          action: _AddButton(onPressed: () => openApiKeyCreateSheet(context)),
        ),
        const _ApiKeysSummary(),

        const SizedBox(height: AppSpacing.xxl),
        _GroupHeader(
          title: 'Templates',
          subtitle: 'Reusable blueprints for requests.',
          action: _AddButton(onPressed: () => openTemplateEditorSheet(context)),
        ),
        const _TemplatesSummary(),

        const SizedBox(height: AppSpacing.xxl),
        const _GroupHeader(
          title: 'Domain verification',
          subtitle: 'Prove this server controls its domain over DNS.',
        ),
        const _DomainVerificationCard(),
        const SizedBox(height: AppSpacing.md),
        _buildConnection(context),
      ],
    );
  }

  Widget _buildWorkspaces(
    BuildContext context,
    SettingsStore settings,
    AuthStore auth,
    String activeId,
  ) {
    if (settings.isLoading && settings.workspaces.isEmpty) {
      return const _LoadingCard();
    }
    if (settings.workspaces.isEmpty) {
      return const _EmptyCard(
        icon: AppIcons.personWorkspace,
        label: 'No workspaces yet',
        hint: 'Create one to separate your data and sharing.',
      );
    }
    return Column(
      children: [
        for (final ws in settings.workspaces)
          AppEntityCard(
            icon: AppIcons.personWorkspace,
            title: ws.name,
            titleBadge: ws.id == activeId
                ? const AppBadge(
                    label: 'Active',
                    variant: AppBadgeVariant.primary,
                  )
                : null,
            actions: [
              if (ws.id != activeId)
                AppSheetAction(
                  icon: AppIcons.arrowRight,
                  label: 'Switch to this workspace',
                  primary: true,
                  onTap: () => Stores.workspaceContext.switchTo(
                    userId: auth.userId,
                    workspaceId: ws.id,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  TrustCheckState _identityClaimState(String domain) {
    final verdict = Stores.settings.domainVerdict;
    if (verdict?.state == TrustState.verified && verdict?.domain == domain) {
      return TrustCheckState.verified;
    }
    return TrustCheckState.failed;
  }

  Widget _buildIdentities(BuildContext context) {
    final store = Stores.identities;
    if (store.isLoading && store.identities.isEmpty) {
      return const _LoadingCard();
    }
    if (store.identities.isEmpty) {
      return const _EmptyCard(
        icon: AppIcons.personBoundingBox,
        label: 'No identities yet',
        hint: 'Generate one to sign and verify what you share.',
      );
    }
    return Column(
      children: [
        for (final id in store.identities)
          AppEntityCard(
            icon: AppIcons.personBoundingBox,
            title: id.name,
            subtitle: id.shortFingerprint,
            subtitleMono: true,
            tags: [
              if (id.domainAtIssue.isNotEmpty)
                TrustClaimText(
                  domain: id.domainAtIssue,
                  state: _identityClaimState(id.domainAtIssue),
                ),
            ],
            titleBadge: id.isRevoked
                ? const AppBadge(icon: AppIcons.shieldSlash, label: 'Revoked')
                : id.isPrimary
                ? const AppBadge(icon: AppIcons.stars, label: 'Primary')
                : null,
            actions: [
              AppSheetAction(
                icon: AppIcons.copy,
                label: 'Copy public key',
                primary: true,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: id.publicKey));
                  AppToast.success(context, 'Public key copied');
                },
              ),
              if (!id.isPrimary && !id.isRevoked)
                AppSheetAction(
                  icon: AppIcons.stars,
                  label: 'Set as primary',
                  onTap: () async {
                    final ok = await store.setPrimary(id.id);
                    if (!context.mounted) return;
                    if (ok) {
                      AppToast.success(context, 'Primary identity updated');
                    } else {
                      AppToast.error(
                        context,
                        'Could not set primary identity',
                        subtitle: store.errorMessage,
                      );
                    }
                  },
                ),
              // Revoking, not deleting, is the answer to a leaked key: the
              // holder of a copy keeps passing every check until this server
              // says otherwise, and it can only say so about an identity it
              // still has a record of.
              if (!id.isRevoked)
                AppSheetAction(
                  icon: AppIcons.shieldSlash,
                  label: 'Revoke',
                  destructive: true,
                  onTap: () => _confirmRevokeIdentity(context, store, id),
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
          ),
      ],
    );
  }

  Widget _buildAppearance(BuildContext context) {
    final controller = Stores.theme;
    return Observer(
      builder: (context) {
        return AppCard(
          child: SizedBox(
            width: double.infinity,
            child: AppSegmented<ThemeMode>(
              value: controller.mode,
              items: const [
                AppSegmentedItem(
                  value: ThemeMode.system,
                  icon: AppIcons.brightnessAuto,
                  label: 'System',
                ),
                AppSegmentedItem(
                  value: ThemeMode.light,
                  icon: AppIcons.brightnessLight,
                  label: 'Light',
                ),
                AppSegmentedItem(
                  value: ThemeMode.dark,
                  icon: AppIcons.brightnessDark,
                  label: 'Dark',
                ),
              ],
              onChanged: controller.setMode,
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String host;
    try {
      final parsed = Uri.parse(Stores.api.baseUrl);
      host = parsed.host.isEmpty ? Stores.api.baseUrl : parsed.host;
    } catch (_) {
      host = Stores.api.baseUrl;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(AppIcons.server, size: 13, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text('Connected to $host. Sign out to change').muted.small,
        ),
      ],
    );
  }

  void _openJoinWorkspace(BuildContext context) {
    showInviteJoinSheet(context: context);
  }

  void _openCreateWorkspace(SettingsStore settings, AuthStore auth) {
    showAppSheet(
      context: context,
      builder: (_) => _CreateWorkspaceSheet(settings: settings, auth: auth),
    );
  }

  void _openCreateIdentity() {
    showAppSheet(
      context: context,
      builder: (_) => const _CreateIdentitySheet(),
    );
  }

  Future<void> _openCreateInvite(
    BuildContext context,
    String workspaceId,
  ) async {
    if (workspaceId.isEmpty) {
      AppToast.error(context, 'Select a workspace first.');
      return;
    }
    await showInviteCreateSheet(context: context, workspaceId: workspaceId);
    if (context.mounted) {
      await Stores.invites.load(workspaceId);
    }
  }
}

/// Outstanding invites for the active workspace.
class _InvitesSection extends StatefulWidget {
  final String workspaceId;

  const _InvitesSection({required this.workspaceId});

  @override
  State<_InvitesSection> createState() => _InvitesSectionState();
}

class _InvitesSectionState extends State<_InvitesSection> {
  @override
  void initState() {
    super.initState();
    if (widget.workspaceId.isNotEmpty) {
      Stores.invites.load(widget.workspaceId);
      Stores.invites.loadCatalogue();
    }
  }

  @override
  void didUpdateWidget(covariant _InvitesSection old) {
    super.didUpdateWidget(old);
    if (old.workspaceId != widget.workspaceId &&
        widget.workspaceId.isNotEmpty) {
      Stores.invites.load(widget.workspaceId);
    }
  }

  /// Withdrawing cannot be undone — the key stops working for whoever holds it
  /// — so it asks first.
  Future<void> _withdraw(BuildContext context, Invite invite) async {
    final label = invite.label.isEmpty ? 'this invite' : invite.label;
    final confirmed = await showAppDialog(
      context: context,
      title: 'Withdraw invite?',
      message:
          'The key for $label will stop working. Anyone still holding it will '
          'not be able to join.',
      confirmLabel: 'Withdraw',
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
        store.error?.description ?? 'Could not withdraw the invite.',
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
        if (open.isEmpty) {
          return AppCard(
            child: Text(
              'No open invites. Create one to give someone access.',
            ).muted.small,
          );
        }
        return Column(
          children: [
            for (final invite in open)
              AppEntityCard(
                icon: AppIcons.key,
                title: invite.label.isEmpty ? 'Invite' : invite.label,
                tags: [
                  AppBadge(
                    icon: AppIcons.shieldCheck,
                    label: _permissionCount(
                      permissionsFromScopes(
                        store.catalogue,
                        invite.permissions,
                      ).length,
                      total,
                    ),
                  ),
                  if (invite.isSingleUse)
                    const AppBadge(icon: AppIcons.key, label: 'Single use'),
                  // Only shown when the invite is pinned to an address; an
                  // unpinned one needs no tag at all.
                  if (invite.email != null)
                    AppBadge(icon: AppIcons.envelope, label: invite.email!),
                ],
                actions: [
                  AppSheetAction(
                    icon: AppIcons.xCircle,
                    label: 'Withdraw invite',
                    destructive: true,
                    onTap: () => _withdraw(context, invite),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// Runs the server-side DNS trust check (`/api/verify-peer` against this
/// server's own advertised domain) so the operator can confirm their
/// `_revoked` TXT record is published and pins the right root key — the proof
/// that lets recipients trust what they share. Surfaces the result as the same
/// [AppTrustBadge] used on the request-fill screen.
class _DomainVerificationCard extends StatefulWidget {
  const _DomainVerificationCard();

  @override
  State<_DomainVerificationCard> createState() =>
      _DomainVerificationCardState();
}

class _DomainVerificationCardState extends State<_DomainVerificationCard> {
  Future<void> _verify() async {
    final store = Stores.settings;
    store.startDomainCheck();
    try {
      final server = await Stores.api.get('/api/server');
      final domain = (server is Map && server['domain'] is String)
          ? server['domain'] as String
          : '';
      if (domain.isEmpty) {
        store.finishDomainCheck(
          error: 'This server does not advertise a domain to verify.',
        );
        return;
      }
      final res = await Stores.api.post(
        '/api/verify-peer',
        body: {'domain': domain},
      );
      store.finishDomainCheck(
        verdict: _verdictFrom(res as Map<String, dynamic>),
      );
    } catch (e) {
      store.finishDomainCheck(error: e.toString());
    }
  }

  TrustVerdict _verdictFrom(Map<String, dynamic> r) {
    final domain = r['domain'] as String? ?? '';
    final reason = r['reason'] as String? ?? '';
    switch (r['state'] as String? ?? 'unverified') {
      case 'verified':
        return TrustVerdict.verified(
          domain: domain,
          rootFingerprint: r['rootFingerprint'] as String? ?? '',
          identityFingerprint: r['identityFingerprint'] as String? ?? '',
        );
      case 'spoofed':
        return TrustVerdict.spoofed(domain: domain, reason: reason);
      case 'dnsMissing':
        return TrustVerdict.dnsMissing(domain: domain, reason: reason);
      default:
        return TrustVerdict.unverified(domain: domain, reason: reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Checks the _revoked DNS record for this server is published and '
            'pins its root key. Run it after setting up DNS to confirm '
            'recipients can verify you.',
          ).muted.small,
          if (Stores.settings.domainVerdict != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppTrustBadge(verdict: Stores.settings.domainVerdict!),
          ],
          if (Stores.settings.domainError != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppErrorText(Stores.settings.domainError!),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            icon: AppIcons.shieldCheck,
            label: 'Verify DNS setup',
            style: AppButtonStyle.accent,
            busy: Stores.settings.isCheckingDomain,
            onTap: _verify,
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String email;
  final Workspace? active;
  final bool loading;

  const _ProfileCard({
    required this.email,
    required this.active,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  bold: true,
                  email.isEmpty ? 'Signed in' : email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (loading)
                  const Text('Loading workspace…').muted.small
                else
                  Column(
                    mainAxisAlignment: .start,
                    crossAxisAlignment: .start,
                    children: [
                      AppText(
                        muted: true,
                        small: true,
                        selectable: true,

                        'Workspace - Name: ${active?.name ?? 'No active workspace'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      AppText(
                        selectable: true,
                        muted: true,
                        small: true,
                        'Workspace - ID: ${active?.id ?? 'No active workspace'}',

                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;

  const _GroupHeader({required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitle!).muted.small,
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return AppButton(
      icon: AppIcons.plus,
      label: 'New',
      style: AppButtonStyle.accent,
      size: AppButtonSize.small,
      onTap: onPressed,
    );
  }
}

class _JoinButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _JoinButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return AppButton(
      // Not the plus the New button carries: joining an existing workspace is
      // not a second way to create one, and two identical icons side by side
      // say it is.
      icon: AppIcons.key,
      label: 'Join',
      style: AppButtonStyle.accent,
      size: AppButtonSize.small,
      onTap: onPressed,
    );
  }
}

/// Wraps a list of [_Tile]s in a bordered card with hairline dividers between.

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Center(child: AppSpinner(large: true)),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;

  const _EmptyCard({
    required this.icon,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xxl,
        horizontal: AppSpacing.lg,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: scheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.sm),
            Text(label).small,
            const SizedBox(height: AppSpacing.xxs),
            Text(hint).muted.small,
          ],
        ),
      ),
    );
  }
}

String _slugify(String s) =>
    s.toLowerCase().replaceAll(' ', '-').replaceAll(RegExp(r'[^a-z0-9\-]'), '');

class _CreateWorkspaceSheet extends StatefulWidget {
  final SettingsStore settings;
  final AuthStore auth;

  const _CreateWorkspaceSheet({required this.settings, required this.auth});

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
    if (Stores.settings.workspaceName.text.trim().isEmpty ||
        Stores.settings.workspaceSlug.text.trim().isEmpty) {
      return;
    }
    Stores.settings.setSubmitting(true);
    final ok = await widget.settings.createWorkspace(
      name: Stores.settings.workspaceName.text.trim(),
      slug: Stores.settings.workspaceSlug.text.trim(),
      userId: widget.auth.userId,
    );
    if (!mounted) return;
    if (ok) {
      await widget.auth.initialize();
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.success(context, 'Workspace created');
    } else {
      Stores.settings.setSubmitting(false);
      AppToast.error(context, 'Could not create workspace');
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
            'Keep separate contexts — personal, a team, a client — apart.',
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
          AppButton(
            label: 'Create workspace',
            busy: Stores.settings.isSubmittingDrawer,
            onTap: _submit,
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
      AppToast.success(context, 'Identity generated');
    } else {
      Stores.settings.setSubmitting(false);
      AppToast.error(context, 'Could not generate identity');
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
            'A cryptographic profile that signs what you share, so recipients '
            'can verify it came from you.',
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
            label: 'Set as primary identity',
            subtitle: 'Used by default when signing shares or requests.',
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
                  label: 'Generate keys',
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

/// The Developer tab's view of API keys: the same card language as the rest of
/// settings, with the full management screen one tap away.
class _ApiKeysSummary extends StatefulWidget {
  const _ApiKeysSummary();

  @override
  State<_ApiKeysSummary> createState() => _ApiKeysSummaryState();
}

class _ApiKeysSummaryState extends State<_ApiKeysSummary> {
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
    return Observer(
      builder: (_) {
        if (store.isLoading && store.apiKeys.isEmpty) {
          return const _LoadingCard();
        }
        if (store.apiKeys.isEmpty) {
          return const _EmptyCard(
            icon: AppIcons.key,
            label: 'No API keys yet',
            hint: 'Create one to reach this workspace programmatically.',
          );
        }
        return Column(
          children: [for (final key in store.apiKeys) ApiKeyCard(apiKey: key)],
        );
      },
    );
  }
}

/// The workspace's templates as expanding cards, edited in place.
class _TemplatesSummary extends StatefulWidget {
  const _TemplatesSummary();

  @override
  State<_TemplatesSummary> createState() => _TemplatesSummaryState();
}

class _TemplatesSummaryState extends State<_TemplatesSummary> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Stores.templates.loadTemplates(Stores.auth.activeWorkspace ?? '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.templates;
    return Observer(
      builder: (_) {
        if (store.isLoading && store.templates.isEmpty) {
          return const _LoadingCard();
        }
        if (store.templates.isEmpty) {
          return const _EmptyCard(
            icon: AppIcons.cardList,
            label: 'No templates yet',
            hint: 'Define what a request asks for, once.',
          );
        }
        return Column(
          children: [
            for (final template in store.templates)
              AppEntityCard(
                icon: AppIcons.cardList,
                title: template.name,
                subtitle: _schemaSummary(template),
                actions: [
                  AppSheetAction(
                    icon: AppIcons.pencil,
                    label: 'Edit',
                    primary: true,
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
          ],
        );
      },
    );
  }

  String _schemaSummary(dynamic template) {
    final sections = template.schema['sections'] as List<dynamic>? ?? [];
    final records = template.schema['records'] as List<dynamic>? ?? [];
    return '${sections.length} sections · ${records.length} root records';
  }
}

/// The people currently in the workspace, with what each may do.
class _MembersSection extends StatefulWidget {
  final String workspaceId;

  const _MembersSection({required this.workspaceId});

  @override
  State<_MembersSection> createState() => _MembersSectionState();
}

class _MembersSectionState extends State<_MembersSection> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _MembersSection old) {
    super.didUpdateWidget(old);
    if (old.workspaceId != widget.workspaceId) _load();
  }

  void _load() {
    if (widget.workspaceId.isEmpty) return;
    Stores.invites.loadMembers(widget.workspaceId);
    // The total is what "3 of 16" is measured against.
    Stores.invites.loadCatalogue();
  }

  Future<void> _edit(WorkspaceMemberDetail member) async {
    await showMemberPermissionsSheet(
      context: context,
      workspaceId: widget.workspaceId,
      member: member,
    );
  }

  Future<void> _remove(WorkspaceMemberDetail member) async {
    final confirmed = await showAppDialog(
      context: context,
      title: member.isSelf ? 'Leave workspace?' : 'Remove member?',
      message: member.isSelf
          ? 'You will lose access to this workspace.'
          : '${member.email} will lose access to this workspace.',
      confirmLabel: member.isSelf ? 'Leave' : 'Remove',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final store = Stores.invites;
    final ok = await store.removeMember(widget.workspaceId, member.id);
    if (!mounted) return;
    if (ok) {
      AppToast.success(
        context,
        member.isSelf ? 'You left the workspace.' : 'Member removed.',
      );
      if (member.isSelf) await Stores.auth.initialize();
    } else {
      AppToast.error(
        context,
        store.error?.description ?? 'Could not remove the member.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.invites;

    return Observer(
      builder: (_) {
        if (store.isLoadingMembers && store.members.isEmpty) {
          return const _LoadingCard();
        }
        final error = store.membersError;
        if (error != null && store.members.isEmpty) {
          return _ErrorCard(
            title: error.title,
            hint: error.description,
            onRetry: _load,
          );
        }
        if (store.members.isEmpty) {
          return const _EmptyCard(
            icon: AppIcons.personBoundingBox,
            label: 'No members yet',
            hint: 'Invite someone to share this workspace.',
          );
        }

        final total = store.catalogue.length;
        return Column(
          children: [
            for (final member in store.members)
              AppEntityCard(
                icon: AppIcons.personBoundingBox,
                title: member.isSelf ? '${member.email} (you)' : member.email,
                tags: [
                  AppBadge(
                    icon: AppIcons.shieldCheck,
                    label: _permissionCount(member.permissions.length, total),
                  ),
                  if (member.isLastAdmin)
                    const AppBadge(
                      icon: AppIcons.shieldLock,
                      label: 'Only admin',
                    ),
                ],
                actions: [
                  if (store.canManageMembers)
                    AppSheetAction(
                      icon: AppIcons.shieldCheck,
                      label: 'Edit permissions',
                      primary: true,
                      onTap: () => _edit(member),
                    ),
                  if (store.canManageMembers || member.isSelf)
                    AppSheetAction(
                      icon: AppIcons.xCircle,
                      label: member.isSelf
                          ? 'Leave workspace'
                          : 'Remove member',
                      destructive: true,
                      // The workspace must keep someone able to invite, so the
                      // last one cannot be removed at all.
                      enabled: !member.isLastAdmin,
                      onTap: () => _remove(member),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// Shown when a section fails to load, so a failure is never mistaken for an
/// empty list or an unfinished one.
class _ErrorCard extends StatelessWidget {
  final String title;
  final String hint;
  final VoidCallback onRetry;

  const _ErrorCard({
    required this.title,
    required this.hint,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: AppSpacing.xxs),
          Text(hint).muted.small,
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Retry',
              onTap: onRetry,
              style: AppButtonStyle.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// "3/16 permissions", or a bare count while the catalogue is still loading.
String _permissionCount(int granted, int total) =>
    total > 0 ? '$granted/$total permissions' : '$granted permissions';
