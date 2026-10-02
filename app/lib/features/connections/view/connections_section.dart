import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/connection.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/connections/view/tool_permissions.dart';

/// The tools connected to this workspace, one row each; a row opens the
/// tool's own page, which answers "what can this tool do, and what has it
/// done?".
class ConnectionsList extends StatelessWidget {
  const ConnectionsList({super.key});

  @override
  Widget build(BuildContext context) {
    final store = Stores.connections;
    return Observer(
      builder: (_) {
        if (store.isLoading && store.connections.isEmpty) {
          return const AppListGroup(
            title: 'Connected tools',
            trailing: SizedBox.shrink(),
            children: [_Loading()],
          );
        }
        return AppListGroup(
          title: 'Connected tools',
          footer: const Text(
            'A tool asks to connect when you use it. It can then see the '
            'status of links it proposes, but never read your vault.',
          ),
          children: store.connections.isEmpty
              ? const [
                  AppDetailRow(
                    icon: AppIcons.info,
                    label: 'No tools connected',
                  ),
                ]
              : [
                  for (final c in store.connections)
                    AppListRow(
                      icon: AppIcons.plug,
                      title: c.name,
                      subtitle: _summary(
                        c,
                        store.linksByConnection[c.id] ?? const [],
                      ),
                      trailing: c.isExpired
                          ? const AppBadge(label: 'Expired')
                          : null,
                      onTap: () => context.go(AppRoutes.connectedToolFor(c.id)),
                    ),
                ],
        );
      },
    );
  }

  String _summary(Connection c, List<Link> links) {
    final count = links.isEmpty
        ? 'No links yet'
        : '${links.length} ${links.length == 1 ? 'link' : 'links'}';
    return '$count · last used ${_day(c.lastUsedAt)}';
  }
}

String _day(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.replaceFirst(' ', 'T'))?.toLocal();
  if (d == null) return '—';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
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
    final ok = await showAppDialog(
      context: context,
      title: 'Disconnect ${connection.name}?',
      message:
          'It will no longer see the status of its links. The links stay '
          'yours and keep working until you revoke them, including any you '
          'shared with it.',
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
        'Could not disconnect',
        subtitle: Stores.connections.errorMessage,
      );
    }
  }

  Future<void> _revoke(Link link) async {
    final ok = await showAppDialog(
      context: context,
      title: 'Revoke ${link.label}?',
      message: link.handedOver
          ? 'The tool has this link. Revoking it is the only way to take '
                'it back. Nobody will be able to open it.'
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
        return const Center(child: AppSpinner(large: true));
      }
      return AppEmptyState(
        icon: AppIcons.plug,
        title: 'Tool not found',
        subtitle: 'It may have been disconnected.',
        action: AppButton(
          icon: AppIcons.arrowLeft,
          label: 'Back to connected tools',
          style: AppButtonStyle.accent,
          onTap: _back,
        ),
      );
    }
    final links = store.linksByConnection[connection.id] ?? const <Link>[];

    return AppDetailPage(
      header: AppDetailHeader(
        badges: [if (connection.isExpired) const AppBadge(label: 'Expired')],
        title: connection.name,
        subtitle: connection.clientId,
        subtitleMono: true,
      ),
      sections: [
        AppListGroup(
          title: 'Connection',
          trailing: const SizedBox.shrink(),
          footer: connection.isExpired
              ? const Text(
                  'This connection has expired. Connect again from the tool '
                  'to renew it.',
                )
              : null,
          children: [
            AppDetailRow(
              icon: AppIcons.calendar,
              label: 'Connected',
              value: _day(connection.created),
            ),
            AppDetailRow(
              icon: AppIcons.clock,
              label: 'Last used',
              value: _day(connection.lastUsedAt),
            ),
            AppDetailRow(
              icon: AppIcons.hourglass,
              label: connection.isExpired ? 'Expired' : 'Expires',
              value: _day(connection.expiresAt),
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
            AppButton(
              label: 'Disconnect',
              icon: AppIcons.linkSlash,
              style: AppButtonStyle.destructive,
              onTap: () => _disconnect(connection),
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
      child: Center(child: AppSpinner()),
    );
  }
}
