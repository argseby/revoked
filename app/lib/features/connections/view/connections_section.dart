import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/design/app_icons.dart';
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

  /// What the tool's own section is called, or will be once it has one.
  String _ownSectionName(Connection connection) {
    for (final s in Stores.vault.sections) {
      if (s.id == connection.section) return s.name.isEmpty ? s.key : s.name;
    }
    return connection.name;
  }

  /// The tool's section, or another it may read, picked in the vault.
  void _editSection(Section section) {
    Stores.vault.editSection(section.id);
    context.go(AppRoutes.vault);
  }

  /// The owner's own sections the tool doesn't reach yet. A section made for
  /// a request's answers or a sign-in isn't theirs to hand on.
  List<Section> _addable(Connection connection) => [
    for (final s in Stores.vault.sections)
      if (!s.isRequested &&
          !s.isSignIn &&
          s.user == Stores.auth.userId &&
          !connection.reachedSections.contains(s.id))
        s,
  ];

  Future<void> _addSection(Connection connection) async {
    final addable = _addable(connection);
    await showAppOptionsSheet(
      context: context,
      title: 'Let ${connection.name} read a section',
      subtitle: 'It can read every record in it. It can’t change them.',
      actions: [
        for (final s in addable)
          AppSheetAction(
            icon: AppIcons.folder,
            label: _sectionName(s),
            onTap: () => _change(
              Stores.connections.setSectionReached(connection, s.id, true),
            ),
          ),
      ],
    );
  }

  Future<void> _removeSection(Connection connection, Section section) async {
    final ok = await showAppDialog(
      context: context,
      title: 'Remove ${_sectionName(section)} from ${connection.name}?',
      message:
          'It can’t read the records in it anymore. The section stays in '
          'your vault.',
      confirmLabel: 'Remove',
      confirmIcon: AppIcons.shieldSlash,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _change(
      Stores.connections.setSectionReached(connection, section.id, false),
    );
  }

  static String _sectionName(Section s) => s.name.isEmpty ? s.key : s.name;

  String _recordCount(Section s) =>
      '${s.records.length} ${s.records.length == 1 ? 'record' : 'records'}';

  /// Its own section and the ones the owner added: what in the vault it
  /// reaches, with the way to change that.
  Widget _sections(Connection connection) {
    Section? find(String id) {
      for (final s in Stores.vault.sections) {
        if (s.id == id) return s;
      }
      return null;
    }

    final own = connection.section.isEmpty ? null : find(connection.section);
    final added = [
      for (final id in connection.sections)
        if (id != connection.section) ?find(id),
    ];
    final readable = connection.vaultAccess.isNotEmpty;
    return AppListGroup(
      title: 'Sections ${connection.name} can read',
      trailing: _addable(connection).isEmpty
          ? const SizedBox.shrink()
          : AppButton(
              icon: AppIcons.plus,
              label: 'Add',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: () => _addSection(connection),
            ),
      footer: Text(
        readable
            ? 'It can read every record in these sections. It can only change '
                  'records it added to its own.'
            : 'It can read these once you allow it to read your vault above.',
      ),
      children: [
        if (own == null && added.isEmpty)
          const AppDetailRow(icon: AppIcons.info, label: 'No sections yet'),
        if (own != null)
          AppListRow(
            icon: AppIcons.folder,
            title: _sectionName(own),
            subtitle: 'Its own section · ${_recordCount(own)}',
            onTap: () => showAppOptionsSheet(
              context: context,
              title: _sectionName(own),
              subtitle: 'Its own section',
              actions: [
                AppSheetAction(
                  icon: AppIcons.plusSlashMinus,
                  label: 'Add or remove records',
                  onTap: () => _editSection(own),
                ),
              ],
            ),
          ),
        for (final s in added)
          AppListRow(
            icon: AppIcons.folder,
            title: _sectionName(s),
            subtitle: 'You added it · ${_recordCount(s)}',
            onTap: () => showAppOptionsSheet(
              context: context,
              title: _sectionName(s),
              subtitle: 'You added it',
              actions: [
                AppSheetAction(
                  icon: AppIcons.plusSlashMinus,
                  label: 'Add or remove records',
                  onTap: () => _editSection(s),
                ),
                AppSheetAction(
                  icon: AppIcons.shieldSlash,
                  label: 'Remove',
                  destructive: true,
                  onTap: () => _removeSection(connection, s),
                ),
              ],
            ),
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
          showSection: true,
          ownSection: connection.hasOwnSection,
          onOwnSection: (v) => _change(store.setOwnSection(connection, v)),
          sectionName: _ownSectionName(connection),
          sectionIsNew: connection.section.isEmpty,
          sectionWrite: connection.vaultAccess != 'read',
          onSectionWrite: (v) => _change(
            store.setSectionAccess(connection, v, Stores.invites.catalogue),
          ),
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
            if (connection.paused)
              AppButton(
                label: 'Activate',
                icon: AppIcons.play,
                busy: store.isChanging,
                onTap: store.isChanging
                    ? null
                    : () => _setPaused(connection, false),
              )
            else if (!connection.isExpired)
              AppButton(
                label: 'Pause',
                icon: AppIcons.pause,
                style: AppButtonStyle.accent,
                busy: store.isChanging,
                onTap: store.isChanging
                    ? null
                    : () => _setPaused(connection, true),
              ),
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
