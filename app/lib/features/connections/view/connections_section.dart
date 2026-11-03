import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/models/attestation.dart';
import 'package:revoked_app/core/models/attestation_check.dart';
import 'package:revoked_app/core/models/connection.dart';
import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_form_row.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/api_keys/view/api_keys_group.dart';
import 'package:revoked_app/features/attestations/view/attestations_section.dart';
import 'package:revoked_app/features/connections/view/access_summary.dart';
import 'package:revoked_app/features/connections/view/day_label.dart';
import 'package:revoked_app/features/connections/view/sign_ins_section.dart';
import 'package:revoked_app/features/connections/view/tool_permissions.dart';
import 'package:revoked_app/features/requests/view/request_groups.dart';

/// The tools connected to this workspace, one row each; a row opens the
/// tool's own page, which answers "what can this tool do, and what has it
/// done?". The services this account signed in to follow them.
class ConnectionsList extends StatelessWidget {
  const ConnectionsList({super.key});

  @override
  Widget build(BuildContext context) {
    final store = Stores.connections;
    final signIns = Stores.signIns;
    return Observer(
      builder: (_) {
        final noTools = store.connections.isEmpty;
        final nothingYet = noTools && signIns.services.isEmpty;
        // Keys sit beside tools: both are ways in from outside the app.
        final showKeys =
            Stores.features.visible(Feature.developer) ||
            Stores.apiKeys.apiKeys.isNotEmpty;
        if (nothingYet && (store.isLoading || signIns.loadState.isFirstLoad)) {
          return const AppListGroup(
            title: 'Connected tools',
            trailing: SizedBox.shrink(),
            children: [_Loading()],
          );
        }
        if (nothingYet && signIns.loadState.error == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppEmptyState(
                icon: AppIcons.plug,
                title: 'Let tools help, without opening your vault',
                subtitle:
                    'A tool, like an application form, asks to connect when '
                    'you use it. It proposes links for you to confirm. It '
                    'sees only the sections you choose.',
                example: const AppEmptyExample(
                  title: 'Flat application',
                  detail: '2 links · last used today',
                  badge: 'connected',
                ),
                steps: const [
                  AppEmptyStep(
                    'A tool asks to connect',
                    'You approve it in the app',
                  ),
                  AppEmptyStep(
                    'It proposes links',
                    'Nothing is shared until you confirm',
                  ),
                  AppEmptyStep(
                    'Disconnect it any time',
                    'Revoke its links too, if you like',
                  ),
                ],
                learnMoreLabel: 'How tools connect',
                learnMoreUrl: '${AppConfig.docsUrl}/guide/tools/',
              ),
              if (showKeys) const ApiKeysGroup(),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppListGroup(
              title: 'Connected tools',
              trailing: noTools ? const SizedBox.shrink() : null,
              footer: const Text(
                'Tools you connect can propose links, requests and '
                'attestations, and follow how they’re going. They see only '
                'the sections you choose.',
              ),
              children: [
                if (noTools)
                  const AppDetailRow(
                    icon: AppIcons.plug,
                    label: 'No tools connected',
                  ),
                for (final c in store.connections)
                  AppListRow(
                    icon: AppIcons.plug,
                    title: c.name,
                    subtitle: _summary(c),
                    trailing: c.paused
                        ? const AppBadge(label: 'Paused')
                        : c.isExpired
                        ? const AppBadge(label: 'Expired')
                        : null,
                    onTap: () => context.go(AppRoutes.connectedToolFor(c.id)),
                  ),
              ],
            ),
            if (showKeys) const ApiKeysGroup(),
            const SignInServicesGroup(),
          ],
        );
      },
    );
  }

  String _summary(Connection c) {
    final store = Stores.connections;
    String count(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final links = store.linksByConnection[c.id]?.length ?? 0;
    final requests = store.requestsByConnection[c.id]?.length ?? 0;
    final attestations = store.attestationsByConnection[c.id]?.length ?? 0;
    final checks = store.checksByConnection[c.id]?.length ?? 0;
    final parts = [
      if (links > 0) count(links, 'link', 'links'),
      if (requests > 0) count(requests, 'request', 'requests'),
      if (attestations > 0) count(attestations, 'attestation', 'attestations'),
      if (checks > 0) count(checks, 'check', 'checks'),
    ];
    return [
      toolAccessSummary(c),
      if (parts.isEmpty) 'No links yet' else ...parts,
      'last used ${dayLabel(c.lastUsedAt)}',
    ].join(' · ');
  }
}

/// What a tool may do and where, counted as the rows ticked on its page.
String toolAccessSummary(Connection c) {
  final keys = c.permissionKeys(Stores.invites.catalogue);
  return accessSummary(
    permissions:
        keys.length +
        (c.allowRevoke ? 1 : 0) +
        (c.allowHandOver && !keys.contains('shares:read') ? 1 : 0),
    sections: c.vaultAccess.isEmpty ? 0 : c.reachedSections.length,
    wholeVault: c.allowVaultRead,
  );
}

/// One connected tool: when it was connected, what it may do, what came of
/// its proposals, and the way to disconnect it.
class ConnectedToolPage extends StatefulWidget {
  final String connectionId;

  const ConnectedToolPage({super.key, required this.connectionId});

  @override
  State<ConnectedToolPage> createState() => _ConnectedToolPageState();
}

class _ConnectedToolPageState extends State<ConnectedToolPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellSlots.title.claim(_title);
      // Opened straight from a link, the list has not loaded anything yet.
      if (Stores.connections.connections.isEmpty) Stores.connections.load();
      // Permissions are named from the catalogue, sections from the vault.
      Stores.invites.loadCatalogue();
      Stores.vault.loadIfDue();
    });
  }

  @override
  void dispose() {
    ShellSlots.title.release(_title);
    super.dispose();
  }

  Connection? get _connection {
    for (final c in Stores.connections.connections) {
      if (c.id == widget.connectionId) return c;
    }
    return null;
  }

  void _back() => context.go(AppRoutes.connectedTools);

  Widget _title(BuildContext context) =>
      AppBarTitle(title: _connection?.name ?? 'Connected tool', onBack: _back);

  Future<void> _disconnect(Connection connection) async {
    final store = Stores.connections;
    final live = (store.linksByConnection[connection.id] ?? const <Link>[])
        .where((l) => l.status == 'active' || l.status == 'paused')
        .length;
    final open =
        (store.requestsByConnection[connection.id] ?? const <DataRequest>[])
            .where((r) => !isRequestClosed(r))
            .length;
    runInAction(() => store.revokeLinksOnDisconnect = false);
    final ok = await showAppDialog(
      context: context,
      title: 'Disconnect ${connection.name}?',
      message: connection.paused
          ? 'It stops seeing its links. Its paused links stay paused until you '
                'activate or revoke them.'
          : 'It stops seeing its links. The links stay yours and keep working '
                'until you revoke them, even ones you sent to it.',
      content: live == 0 && open == 0
          ? null
          : Observer(
              builder: (_) => AppCheckRow(
                label: 'Revoke its links too',
                subtitle: [
                  if (live > 0)
                    'Nobody will be able to open '
                        '${live == 1 ? 'this link' : 'these $live links'}.',
                  if (open > 0)
                    open == 1
                        ? 'Its request stops taking answers.'
                        : 'Its $open requests stop taking answers.',
                ].join(' '),
                value: store.revokeLinksOnDisconnect,
                onChanged: (v) =>
                    runInAction(() => store.revokeLinksOnDisconnect = v),
              ),
            ),
      confirmLabel: 'Disconnect',
      confirmIcon: AppIcons.linkSlash,
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (await Stores.connections.disconnect(connection.id)) {
      if (mounted) _back();
    } else if (mounted) {
      AppToast.error(
        context,
        'Couldn’t disconnect',
        subtitle: Stores.connections.errorMessage,
      );
    }
  }

  Future<void> _setPaused(Connection connection, bool paused) async {
    final store = Stores.connections;
    final ok = paused
        ? await store.pause(connection.id)
        : await store.activate(connection.id);
    if (!ok && mounted) {
      AppToast.error(
        context,
        paused ? 'Couldn’t pause' : 'Couldn’t activate',
        subtitle: store.errorMessage,
      );
    }
  }

  Future<void> _revoke(Link link) async {
    final ok = await showAppDialog(
      context: context,
      title: 'Revoke ${link.label}?',
      message: link.handedOver
          ? 'The tool has this link. Revoke it to take it back. Nobody will '
                'be able to open it.'
          : 'Nobody will be able to open this link.',
      confirmLabel: 'Revoke',
      confirmIcon: AppIcons.linkSlash,
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await Stores.connections.revokeLink(link);
  }

  /// Runs a change to what the tool may do, and says so when it fails.
  Future<void> _change(Future<bool> change) async {
    if (await change || !mounted) return;
    AppToast.error(
      context,
      'Couldn’t change it',
      subtitle: Stores.connections.errorMessage,
    );
  }

  static String _sectionName(Section s) => s.name.isEmpty ? s.key : s.name;

  String _recordCount(Section s) =>
      '${s.records.length} ${s.records.length == 1 ? 'record' : 'records'}';

  /// Every section of the owner's a tool may be given, its own first, each
  /// with a switch: on, the tool reads it. A section made for a request's
  /// answers or a sign-in isn't the owner's to hand on.
  Widget _sections(Connection connection) {
    final store = Stores.connections;
    Section? own;
    final others = <Section>[];
    for (final s in Stores.vault.sections) {
      if (s.id == connection.section) {
        own = s;
      } else if (!s.isRequested &&
          !s.isSignIn &&
          s.user == Stores.auth.userId) {
        others.add(s);
      }
    }
    final ownOn = connection.hasOwnSection;
    final access = connection.vaultAccess == 'read' ? 'Read' : 'Manage';
    return AppListGroup(
      title: 'Vault sections',
      trailing: const SizedBox.shrink(),
      footer: const Text(
        'It reads every record in the sections that are on. It changes only '
        'what it added to its own.',
      ),
      children: [
        AppFormToggleRow(
          icon: AppIcons.folder,
          label: own == null ? connection.name : _sectionName(own),
          badge: 'Its own',
          badgeVariant: AppBadgeVariant.outline,
          subtitle: own == null
              ? 'New'
              : ownOn
              ? '$access · ${_recordCount(own)}'
              : _recordCount(own),
          value: ownOn,
          onChanged: (v) => _change(store.setOwnSection(connection, v)),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
        if (ownOn)
          SectionAccessChoice(
            write: connection.vaultAccess != 'read',
            onChanged: (v) => _change(
              store.setSectionAccess(connection, v, Stores.invites.catalogue),
            ),
          ),
        for (final s in others)
          AppFormToggleRow(
            icon: AppIcons.folder,
            label: _sectionName(s),
            subtitle: connection.sections.contains(s.id)
                ? 'Read · ${_recordCount(s)}'
                : _recordCount(s),
            value: connection.sections.contains(s.id),
            onChanged: (v) =>
                _change(store.setSectionReached(connection, s.id, v)),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final store = Stores.connections;
    final connection = _connection;
    if (connection == null) {
      if (store.isLoading) {
        return const AppListSkeleton();
      }
      return AppEmptyState(
        icon: AppIcons.plug,
        title: 'Tool not found',
        subtitle: 'It may have been disconnected.',
        action: AppButton(
          icon: AppIcons.arrowLeft,
          label: 'Back to tools',
          style: AppButtonStyle.accent,
          onTap: _back,
        ),
      );
    }
    final links = store.linksByConnection[connection.id] ?? const <Link>[];
    final requests =
        store.requestsByConnection[connection.id] ?? const <DataRequest>[];
    final attestations =
        store.attestationsByConnection[connection.id] ?? const <Attestation>[];
    final checks =
        store.checksByConnection[connection.id] ?? const <AttestationCheck>[];

    return AppDetailPage(
      header: AppDetailHeader(
        badges: [
          if (connection.paused) const AppBadge(label: 'Paused'),
          if (connection.isExpired) const AppBadge(label: 'Expired'),
        ],
        title: connection.name,
        subtitle: connection.clientId,
        subtitleMono: true,
      ),
      sections: [
        AppListGroup(
          title: 'Connection',
          trailing: const SizedBox.shrink(),
          footer: connection.paused
              ? Text(
                  '${connection.name} can’t do anything while it’s paused. Its '
                  'links are paused too.',
                )
              : connection.isExpired
              ? const Text(
                  'This connection expired. Connect again from the tool to '
                  'renew it.',
                )
              : null,
          children: [
            AppDetailRow(
              icon: AppIcons.calendar,
              label: 'Connected',
              value: dayLabel(connection.created),
            ),
            AppDetailRow(
              icon: AppIcons.clock,
              label: 'Last used',
              value: dayLabel(connection.lastUsedAt),
            ),
            AppDetailRow(
              icon: AppIcons.hourglass,
              label: connection.isExpired ? 'Expired' : 'Expires',
              value: dayLabel(connection.expiresAt),
            ),
            if (!connection.isExpired)
              AppFormToggleRow(
                icon: AppIcons.pause,
                label: 'Active',
                subtitle: 'Off pauses it and its links',
                value: !connection.paused,
                onChanged: store.isChanging
                    ? null
                    : (on) => _setPaused(connection, !on),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              ),
          ],
        ),
        ToolPermissions(
          name: connection.name,
          allowRevoke: connection.allowRevoke,
          allowHandOver: connection.allowHandOver,
          onAllowRevoke: (v) =>
              _change(store.setPermissions(connection.id, allowRevoke: v)),
          onAllowHandOver: (v) =>
              _change(store.setPermissions(connection.id, allowHandOver: v)),
          // Shown only while it is on: granting it again takes a connect
          // the tool starts, so the owner sees what it asks for.
          showVault: connection.allowVaultRead,
          allowVaultRead: connection.allowVaultRead,
          onAllowVaultRead: (v) =>
              _change(store.setPermissions(connection.id, allowVaultRead: v)),
          permissions: [
            for (final p in Stores.invites.catalogue)
              if (Connection.toolPermissions.contains(p.key)) p,
          ],
          granted: connection.permissionKeys(Stores.invites.catalogue).toSet(),
          onPermission: (key, on) => _change(
            store.setPermission(connection, key, on, Stores.invites.catalogue),
          ),
          // Its sections have a group of their own below.
          ownSection: connection.reachedSections.isNotEmpty,
        ),
        _sections(connection),
        AppListGroup(
          title: 'Links from ${connection.name}',
          noun: 'links',
          previewCount: 5,
          children: links.isEmpty
              ? const [
                  AppDetailRow(
                    icon: AppIcons.info,
                    label: 'No links from this tool yet',
                  ),
                ]
              : [for (final link in links) _linkRow(link)],
        ),
        if (requests.isNotEmpty)
          AppListGroup(
            title: 'Requests from ${connection.name}',
            noun: 'requests',
            previewCount: 5,
            children: [
              for (final r in requests)
                AppListRow(
                  icon: AppIcons.inboxFill,
                  title: r.label,
                  subtitle: requestSummary(r, 0, DateTime.now()),
                  trailing: StatusLabel(r.status),
                  onTap: () => context.go(AppRoutes.requestDetailFor(r.id)),
                ),
            ],
          ),
        if (attestations.isNotEmpty)
          AppListGroup(
            title: 'Attestations from ${connection.name}',
            noun: 'attestations',
            previewCount: 5,
            children: [
              for (final a in attestations)
                AppListRow(
                  icon: AppIcons.shieldLock,
                  title: a.title,
                  subtitle: issuedAttestationSubtitle(a),
                  trailing: issuedAttestationBadge(a),
                  onTap: () => context.go(AppRoutes.attestationsIssued),
                ),
            ],
          ),
        if (checks.isNotEmpty)
          AppListGroup(
            title: 'Checks from ${connection.name}',
            noun: 'checks',
            previewCount: 5,
            children: [
              for (final c in checks)
                AppListRow(
                  icon: AppIcons.shieldCheck,
                  title: c.title,
                  subtitle: checkSubtitle(c),
                  trailing: checkBadge(context, c),
                  onTap: () => context.go(AppRoutes.attestationsChecked),
                ),
            ],
          ),
        AppDetailManage(
          actions: [
            AppButton(
              label: 'Disconnect',
              icon: AppIcons.linkSlash,
              style: AppButtonStyle.destructive,
              onTap: store.isChanging ? null : () => _disconnect(connection),
            ),
          ],
        ),
      ],
    );
  }

  Widget _linkRow(Link link) {
    final live = link.status == 'active' || link.status == 'paused';
    final opened = link.viewCount == 0
        ? 'not opened'
        : 'opened ${link.viewCount}×';
    return AppListRow(
      icon: AppIcons.link,
      title: link.label.isEmpty ? link.slug : link.label,
      subtitle: [
        link.status,
        opened,
        if (link.handedOver) 'shared with the tool',
      ].join(' · '),
      onTap: () => showAppOptionsSheet(
        context: context,
        title: link.label.isEmpty ? link.slug : link.label,
        subtitle: link.slug,
        actions: [
          AppSheetAction(
            icon: AppIcons.share,
            label: 'Open link',
            onTap: () => context.go(AppRoutes.shareDetailFor(link.id)),
          ),
          if (live)
            AppSheetAction(
              icon: AppIcons.linkSlash,
              label: 'Revoke',
              destructive: true,
              onTap: () => _revoke(link),
            ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: AppListSkeleton(embedded: true),
    );
  }
}
