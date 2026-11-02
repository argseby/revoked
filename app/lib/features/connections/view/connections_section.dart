import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/connection.dart';
import 'package:revoked_app/core/models/link.dart';
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
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/connections/view/day_label.dart';
import 'package:revoked_app/features/connections/view/sign_ins_section.dart';
import 'package:revoked_app/features/connections/view/tool_permissions.dart';

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
        if (nothingYet && (store.isLoading || signIns.loadState.isFirstLoad)) {
          return const AppListGroup(
            title: 'Connected tools',
            trailing: SizedBox.shrink(),
            children: [_Loading()],
          );
        }
        if (nothingYet && signIns.loadState.error == null) {
          return AppEmptyState(
            icon: AppIcons.plug,
            title: 'Let tools help, without opening your vault',
            subtitle:
                'A tool, like an application form, asks to connect when you '
                'use it. It proposes links for you to confirm. It never sees '
                'the records themselves.',
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
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppListGroup(
              title: 'Connected tools',
              trailing: noTools ? const SizedBox.shrink() : null,
              footer: const Text(
                'Tools you connect can propose links and follow their status. '
                'They never read your vault.',
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
                    subtitle: _summary(
                      c,
                      store.linksByConnection[c.id] ?? const [],
                    ),
                    trailing: c.paused
                        ? const AppBadge(label: 'Paused')
                        : c.isExpired
                        ? const AppBadge(label: 'Expired')
                        : null,
                    onTap: () => context.go(AppRoutes.connectedToolFor(c.id)),
                  ),
              ],
            ),
            const SignInServicesGroup(),
          ],
        );
      },
    );
  }

  String _summary(Connection c, List<Link> links) {
    final count = links.isEmpty
        ? 'No links yet'
        : '${links.length} ${links.length == 1 ? 'link' : 'links'}';
    return '$count · last used ${dayLabel(c.lastUsedAt)}';
  }
}

/// One connected tool: when it was connected, what it may do, the links it
/// proposed, and the way to disconnect it.
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
    runInAction(() => store.revokeLinksOnDisconnect = false);
    final ok = await showAppDialog(
      context: context,
      title: 'Disconnect ${connection.name}?',
      message: connection.paused
          ? 'It stops seeing its links. Its paused links stay paused until you '
                'activate or revoke them.'
          : 'It stops seeing its links. The links stay yours and keep working '
                'until you revoke them, even ones you sent to it.',
      content: live == 0
          ? null
          : Observer(
              builder: (_) => AppCheckRow(
                label: 'Revoke its links too',
                subtitle:
                    'Nobody will be able to open '
                    '${live == 1 ? 'this link' : 'these $live links'}.',
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
              store.setPermissions(connection.id, allowRevoke: v),
          onAllowHandOver: (v) =>
              store.setPermissions(connection.id, allowHandOver: v),
        ),
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
