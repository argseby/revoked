import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/connection.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/connections/view/tool_permissions.dart';

/// The tools connected to this workspace: what each may do, what it did, and
/// the way out. One place answers "what can this tool do, and what
/// has it done?".
class ConnectionsSection extends StatefulWidget {
  const ConnectionsSection({super.key});

  @override
  State<ConnectionsSection> createState() => _ConnectionsSectionState();
}

class _ConnectionsSectionState extends State<ConnectionsSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Stores.connections.load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.connections;
    return Observer(
      builder: (_) {
        if (store.isLoading && store.connections.isEmpty) {
          return const AppCard(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Center(child: AppSpinner(large: true)),
          );
        }
        if (store.connections.isEmpty) {
          return AppCard(
            child: const Text(
              'No tools connected. A tool asks to connect when you use it. '
              'It can then see the status of links it proposes, but never '
              'read your vault.',
            ).muted.small,
          );
        }
        return Column(
          children: [
            for (final c in store.connections)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _ConnectionCard(
                  connection: c,
                  links: store.linksByConnection[c.id] ?? const [],
                ),
              ),
          ],
        );
      },
    );
  }
}

String _day(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.replaceFirst(' ', 'T'))?.toLocal();
  if (d == null) return '—';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _ConnectionCard extends StatelessWidget {
  final Connection connection;
  final List<Link> links;

  const _ConnectionCard({required this.connection, required this.links});

  Future<void> _disconnect(BuildContext context) async {
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
    if (!ok || !context.mounted) return;
    if (!await Stores.connections.disconnect(connection.id) &&
        context.mounted) {
      AppToast.error(
        context,
        'Could not disconnect',
        subtitle: Stores.connections.errorMessage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(connection.name).header,
                    Text(connection.clientId).muted.small,
                  ],
                ),
              ),
              AppButton(
                label: 'Disconnect',
                icon: AppIcons.linkSlash,
                style: AppButtonStyle.destructive,
                size: AppButtonSize.small,
                onTap: () => _disconnect(context),
              ),
            ],
          ),
          AppSpacing.gapXs,
          Text(
            'Connected ${_day(connection.created)} · last used '
            '${_day(connection.lastUsedAt)} · '
            '${connection.isExpired ? 'expired' : 'expires'} '
            '${_day(connection.expiresAt)}',
          ).muted.small,
          if (connection.isExpired) ...[
            AppSpacing.gapXs,
            const Text(
              'This connection has expired. Connect again from the tool to '
              'renew it.',
            ).muted.small,
          ],
          AppSpacing.gapMd,
          ToolPermissions(
            name: connection.name,
            allowRevoke: connection.allowRevoke,
            allowHandOver: connection.allowHandOver,
            onAllowRevoke: (v) => Stores.connections.setPermissions(
              connection.id,
              allowRevoke: v,
            ),
            onAllowHandOver: (v) => Stores.connections.setPermissions(
              connection.id,
              allowHandOver: v,
            ),
          ),
          AppSpacing.gapLg,
          Text(
            links.isEmpty
                ? 'No links from this tool yet.'
                : 'Links from this tool',
          ).muted.small,
          for (final link in links) _LinkRow(link: link),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final Link link;

  const _LinkRow({required this.link});

  Future<void> _revoke(BuildContext context) async {
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
    if (!ok || !context.mounted) return;
    await Stores.connections.revokeLink(link);
  }

  @override
  Widget build(BuildContext context) {
    final live = link.status == 'active' || link.status == 'paused';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(link.label.isEmpty ? link.slug : link.label),
                AppSpacing.gapXxs,
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    AppBadge(label: link.status),
                    AppBadge(
                      label: link.viewCount == 0
                          ? 'not opened'
                          : 'opened ${link.viewCount}×',
                      icon: AppIcons.eye,
                    ),
                    if (link.handedOver)
                      const AppBadge(
                        label: 'shared with tool',
                        icon: AppIcons.share,
                        variant: AppBadgeVariant.primary,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (live)
            AppButton(
              label: 'Revoke',
              icon: AppIcons.linkSlash,
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: () => _revoke(context),
            ),
        ],
      ),
    );
  }
}
