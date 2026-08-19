import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/models/workspace.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_avatar.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_entity_card.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_screen_header.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_tabs.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/app_trust_badge.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/invites/view/invite_create_sheet.dart';
import 'package:revoked_app/features/invites/view/member_permissions_sheet.dart';
import 'package:revoked_app/features/settings/store/settings_store.dart';

/// The Account tab — a single, calm, scrollable surface grouped into sections
/// (profile, workspaces, identities, developer tools, connection) instead of
/// the old crude pill-tabs. Create flows are bottom sheets, matching the rest
/// of the app; signing out lives quietly at the bottom rather than as a red
/// button up top.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

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
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.screenH(context),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: AppSpacing.md),
              AppScreenHeader(title: 'Settings'),
            ],
          ),
        ),
        Expanded(
          child: Observer(
            builder: (context) {
              final activeId = auth.activeWorkspace ?? '';
              return AppTabs(
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
        _buildConnection(context),

        const SizedBox(height: AppSpacing.xl),
        _SignOutButton(
          onSignOut: () async {
            await auth.logout();
            if (context.mounted) context.go(AppRoutes.login);
          },
        ),
      ],
    );
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
          action: _AddButton(
            onPressed: () => _openCreateWorkspace(settings, auth),
          ),
        ),
        _buildWorkspaces(context, settings, auth, activeId),

        const SizedBox(height: AppSpacing.xxl),
        _GroupHeader(
          title: 'Members',
          subtitle: 'Who has access, and what they may do.',
          action: _AddButton(
            onPressed: () => _openCreateInvite(context, activeId),
          ),
        ),
        _MembersSection(workspaceId: activeId),

        const SizedBox(height: AppSpacing.xxl),
        const _GroupHeader(
          title: 'Pending invites',
          subtitle: 'Keys handed out but not yet used.',
        ),
        _InvitesSection(workspaceId: activeId),

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
          action: _AddButton(onPressed: () => context.go(AppRoutes.apiKeys)),
        ),
        const _ApiKeysSummary(),

        const SizedBox(height: AppSpacing.xxl),
        const _GroupHeader(
          title: 'Templates',
          subtitle: 'Reusable blueprints for requests.',
        ),
        _buildTemplatesTile(context),

        const SizedBox(height: AppSpacing.xxl),
        const _GroupHeader(
          title: 'Domain verification',
          subtitle: 'Prove this server controls its domain over DNS.',
        ),
        const _DomainVerificationCard(),
      ],
    );
  }

  Widget _buildTemplatesTile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _GroupCard(
      rows: [
        _Tile(
          leading: const _IconAvatar(icon: AppIcons.cardList),
          title: 'Request templates',
          subtitle: 'Define what a request asks for.',
          onTap: () => context.go(AppRoutes.templates),
          trailing: Icon(
            AppIcons.chevronRight,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // --- Workspaces -----------------------------------------------------------

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
            tags: [
              if (ws.id == activeId)
                const AppBadge(
                  label: 'Active',
                  variant: AppBadgeVariant.primary,
                ),
            ],
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

  // --- Identities -----------------------------------------------------------

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
            subtitle: id.domainAtIssue.isNotEmpty
                ? '${id.shortFingerprint} · ${id.domainAtIssue}'
                : id.shortFingerprint,
            subtitleMono: true,
            tags: [
              if (id.isPrimary)
                const AppBadge(icon: AppIcons.stars, label: 'Primary'),
            ],
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
              if (!id.isPrimary)
                AppSheetAction(
                  icon: AppIcons.stars,
                  label: 'Set as primary',
                  onTap: () => store.togglePrimary(id.id),
                ),
              if (!id.isPrimary)
                AppSheetAction(
                  icon: AppIcons.trash,
                  label: 'Delete',
                  destructive: true,
                  onTap: () => store.deleteIdentity(id.id),
                ),
            ],
          ),
      ],
    );
  }

  // --- Developer ------------------------------------------------------------

  // --- Appearance ----------------------------------------------------------

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

  // --- Connection (read-only) ----------------------------------------------

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
        Text('Connected to $host').muted.small,
      ],
    );
  }

  // --- Create sheets --------------------------------------------------------

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
  bool _checking = false;
  TrustVerdict? _verdict;
  String? _error;

  Future<void> _verify() async {
    setState(() {
      _checking = true;
      _verdict = null;
      _error = null;
    });
    try {
      final server = await Stores.api.get('/api/server');
      final domain = (server is Map && server['domain'] is String)
          ? server['domain'] as String
          : '';
      if (domain.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = 'This server does not advertise a domain to verify.';
          _checking = false;
        });
        return;
      }
      final res = await Stores.api.post(
        '/api/verify-peer',
        body: {'domain': domain},
      );
      if (!mounted) return;
      setState(() {
        _verdict = _verdictFrom(res as Map<String, dynamic>);
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _checking = false;
      });
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Checks the _revoked DNS record for this server is published and '
            'pins its root key. Run it after setting up DNS to confirm '
            'recipients can verify you.',
          ).muted.small,
          if (_verdict != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppTrustBadge(verdict: _verdict!),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppErrorText(_error!),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            icon: AppIcons.shieldCheck,
            label: 'Verify DNS setup',
            style: AppButtonStyle.accent,
            busy: _checking,
            onTap: _verify,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Profile
// ===========================================================================

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
          AppAvatar(source: email, size: AppAvatarSize.large, emphasized: true),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email.isEmpty ? 'Signed in' : email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                if (loading)
                  const Text('Loading workspace…').muted.small
                else
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active != null
                              ? scheme.primary
                              : scheme.outline,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          active?.name ?? 'No active workspace',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ).muted.small,
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

// ===========================================================================
// Section scaffolding
// ===========================================================================

class _GroupHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;

  const _GroupHeader({required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: AppSpacing.md,
        left: AppSpacing.xxs,
        right: AppSpacing.xxs,
      ),
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

/// Wraps a list of [_Tile]s in a bordered card with hairline dividers between.
class _GroupCard extends StatelessWidget {
  final List<Widget> rows;
  const _GroupCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const AppDivider(inset: true),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// One row inside a [_GroupCard]: leading visual, title (+ optional badge),
/// optional subtitle, optional trailing control.
/// One row inside a [_GroupCard]: a leading visual, a title and subtitle, and
/// a trailing affordance. For navigating somewhere — anything with actions of
/// its own is an [AppEntityCard] instead.
class _Tile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _Tile({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).muted.small,
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, borderRadius: AppRadius.allMd, child: row);
  }
}

class _IconAvatar extends StatelessWidget {
  final IconData icon;
  const _IconAvatar({required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: AppRadius.allMd,
      ),
      child: Icon(icon, size: 20, color: scheme.primary),
    );
  }
}

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

class _SignOutButton extends StatelessWidget {
  final Future<void> Function() onSignOut;
  const _SignOutButton({required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AppButton(
        icon: AppIcons.boxArrowLeft,
        label: 'Sign out',
        style: AppButtonStyle.destructive,
        onTap: onSignOut,
      ),
    );
  }
}

// ===========================================================================
// Create sheets
// ===========================================================================

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
  final _name = TextEditingController();
  final _slug = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => _slug.text = _slugify(_name.text));
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _slug.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final ok = await widget.settings.createWorkspace(
      name: _name.text.trim(),
      slug: _slug.text.trim(),
      userId: widget.auth.userId,
    );
    if (!mounted) return;
    if (ok) {
      await widget.auth.initialize();
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.success(context, 'Workspace created');
    } else {
      setState(() => _busy = false);
      AppToast.error(context, 'Could not create workspace');
    }
  }

  @override
  Widget build(BuildContext context) {
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
          AppTextField(controller: _name, hint: 'My Team'),
          const SizedBox(height: AppSpacing.md),
          const Text('Slug').small,
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: _slug,
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
          AppButton(label: 'Create workspace', busy: _busy, onTap: _submit),
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
  final _name = TextEditingController();
  bool _primary = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final ok = await Stores.identities.createIdentity(
      name: _name.text.trim(),
      isPrimary: _primary,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      AppToast.success(context, 'Identity generated');
    } else {
      setState(() => _busy = false);
      AppToast.error(context, 'Could not generate identity');
    }
  }

  @override
  Widget build(BuildContext context) {
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
          AppTextField(controller: _name, hint: 'e.g. Personal, Recruiter'),
          const SizedBox(height: AppSpacing.sm),
          AppFormToggleRow(
            label: 'Set as primary identity',
            subtitle: 'Used by default when signing shares.',
            value: _primary,
            onChanged: (v) => setState(() => _primary = v),
            inset: false,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            icon: AppIcons.shieldCheck,
            label: 'Generate keys',
            busy: _busy,
            onTap: _submit,
          ),
        ],
      ),
    );
  }
}

/// The Developer tab's view of API keys: the same card language as the rest of
/// settings, with the full management screen one tap away.
class _ApiKeysSummary extends StatelessWidget {
  const _ApiKeysSummary();

  @override
  Widget build(BuildContext context) {
    final store = Stores.apiKeys;
    final scheme = Theme.of(context).colorScheme;

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
        return _GroupCard(
          rows: [
            for (final key in store.apiKeys)
              _Tile(
                leading: const _IconAvatar(icon: AppIcons.key),
                title: key.label,
                subtitle: key.neverExpires
                    ? 'Never expires'
                    : 'Expires ${AppEntityCard.formatDate(key.expiresAt) ?? key.expiresAt}',
                onTap: () => context.go(AppRoutes.apiKeys),
                trailing: Icon(
                  AppIcons.chevronRight,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        );
      },
    );
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
