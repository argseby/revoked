import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/notification.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_error_text.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_menu_button.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';

void openNotificationsSheet(BuildContext context) {
  Stores.notifications.load();
  showAppSheet(
    context: context,
    dismissible: true,
    builder: (context) => const NotificationsSheet(),
  );
}

/// Sizes to its content: a fixed height left the bottom of the full-height
/// side panel empty, and the bottom sheet already caps how tall it may grow.
class NotificationsSheet extends StatelessWidget {
  const NotificationsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final store = Stores.notifications;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header(),
        Observer(
          builder: (_) => store.errorMessage == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: AppErrorText(store.errorMessage!),
                ),
        ),
        const AppDivider(),
        Flexible(
          child: Observer(
            builder: (context) {
              if (store.isLoading && store.notifications.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: AppListSkeleton(),
                );
              }
              if (store.notifications.isEmpty) {
                return SingleChildScrollView(
                  child: AppEmptyState(
                    icon: AppIcons.bellSlash,
                    title: 'No notifications',
                    subtitle: 'You\'re all caught up.',
                  ),
                );
              }
              final groups = groupNotificationsByDay(
                store.notifications,
                DateTime.now(),
              );
              return ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                children: [
                  for (final (label, items) in groups)
                    AppListGroup(
                      title: label,
                      trailing: const SizedBox.shrink(),
                      children: [for (final n in items) _NotificationRow(n)],
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final store = Stores.notifications;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Observer(
        builder: (context) {
          final unread = store.unreadCount;
          final read = store.readCount;
          return Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Flexible(
                      child: AppText(
                        'Notifications',
                        header: true,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (unread > 0) ...[
                      AppSpacing.gapSm,
                      AppBadge(
                        label: '$unread new',
                        variant: AppBadgeVariant.primary,
                      ),
                    ],
                  ],
                ),
              ),
              AppMenuButton(
                icon: AppIcons.threeDots,
                tooltip: 'More',
                style: AppButtonStyle.ghost,
                chevron: false,
                items: [
                  AppMenuItem(
                    label: 'Mark all as read',
                    icon: AppIcons.check,
                    onSelected: unread > 0 ? store.markAllRead : null,
                  ),
                  AppMenuItem(
                    label: read == 1
                        ? 'Delete 1 read notification'
                        : 'Delete $read read notifications',
                    icon: AppIcons.trash,
                    destructive: true,
                    onSelected: read > 0 ? () => _clearRead(context) : null,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _clearRead(BuildContext context) async {
    final store = Stores.notifications;
    final ok = await showAppDialog(
      context: context,
      title: 'Delete read notifications?',
      message: 'Unread ones stay.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) await store.clearRead();
  }
}

class _NotificationRow extends StatelessWidget {
  final AppNotification notification;

  const _NotificationRow(this.notification);

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final scheme = Theme.of(context).colorScheme;
    final store = Stores.notifications;
    final unread = !n.read;
    final problem = _problemTypes.contains(n.type);
    final created = DateTime.tryParse(n.created ?? '')?.toLocal();
    final message = n.message ?? '';

    final (Color tile, Color glyph) = problem
        ? (scheme.errorContainer, scheme.onErrorContainer)
        : unread
        ? (scheme.primaryContainer, scheme.onPrimaryContainer)
        : (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);

    final row = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xxs,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tile,
                borderRadius: AppRadius.allMd,
              ),
              child: Icon(_iconFor(n.type), size: 18, color: glyph),
            ),
          ),
          AppSpacing.gapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppText(
                        n.title,
                        bold: unread,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (created != null) ...[
                      AppSpacing.gapSm,
                      AppText(
                        notificationTimeAgo(created, DateTime.now()),
                        maxLines: 1,
                      ).small.muted,
                    ],
                  ],
                ),
                if (message.isNotEmpty) ...[
                  AppSpacing.gapXxs,
                  AppText(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ).small.muted,
                ],
              ],
            ),
          ),
          AppSpacing.gapXs,
          SizedBox(
            width: AppSpacing.sm,
            height: AppButton.smallExtent,
            child: unread
                ? Center(
                    child: Semantics(
                      label: 'Unread',
                      child: SizedBox.square(
                        dimension: AppSpacing.sm,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          AppMenuButton(
            icon: AppIcons.threeDotsVertical,
            tooltip: 'Options',
            style: AppButtonStyle.ghost,
            size: AppButtonSize.small,
            chevron: false,
            items: [
              AppMenuItem(
                label: unread ? 'Mark as read' : 'Mark as unread',
                icon: unread ? AppIcons.check : AppIcons.recordCircleFill,
                onSelected: () => store.markRead(n.id, read: unread),
              ),
              AppMenuItem(
                label: 'Delete',
                icon: AppIcons.trash,
                destructive: true,
                onSelected: () => store.delete(n.id),
              ),
            ],
          ),
        ],
      ),
    );

    final open = _opener(n);
    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => store.delete(n.id),
      background: ColoredBox(
        color: scheme.errorContainer,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.xl),
            child: Icon(AppIcons.trash, color: scheme.onErrorContainer),
          ),
        ),
      ),
      child: Semantics(
        button: true,
        child: InkWell(
          // Square on purpose: the row spans its card, whose rounded clip
          // trims the highlight on the first and last row.
          borderRadius: BorderRadius.zero,
          onTap: () {
            if (unread) store.markRead(n.id);
            if (open != null) open(context);
          },
          child: row,
        ),
      ),
    );
  }
}

/// Where tapping a notification takes the reader, when it names something.
void Function(BuildContext)? _opener(AppNotification n) {
  final id = n.refId ?? '';
  final String? route = switch (n.refCollection) {
    AppConfig.recordsCollection when id.isNotEmpty => AppRoutes.recordDetailFor(
      id,
    ),
    AppConfig.requestsCollection when id.isNotEmpty =>
      AppRoutes.requestDetailFor(id),
    AppConfig.linksCollection when id.isNotEmpty => AppRoutes.shareDetailFor(
      id,
    ),
    AppConfig.attestationChecksCollection => AppRoutes.attestationsChecked,
    AppConfig.bookmarksCollection => AppRoutes.requestsReceived,
    _ => null,
  };
  if (route == null) return null;
  return (context) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(route);
  };
}

const _problemTypes = {'callback_failed', 'email_undelivered', 'sealing_reset'};

IconData _iconFor(String type) => switch (type) {
  'request_response' => AppIcons.inboxFill,
  'request_complete' => AppIcons.checkCircle,
  'request_expired' || 'link_expired' => AppIcons.hourglass,
  'link_revoked' => AppIcons.linkSlash,
  'link_max_views' || 'link_opened' => AppIcons.eye,
  'callback_failed' => AppIcons.exclamationTriangle,
  'invite_accepted' => AppIcons.personPlus,
  'sealing_reset' => AppIcons.shieldSlash,
  'reminder' => AppIcons.clock,
  'attestation_accepted' => AppIcons.attestation,
  'attestation_checked' => AppIcons.shieldCheck,
  'contact_share' => AppIcons.share,
  'contact_ask' => AppIcons.askFor,
  'email_undelivered' => AppIcons.envelope,
  _ => AppIcons.bell,
};

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// "Just now", "5 min ago", "3 h ago", "Yesterday", "Tue", "12 Oct",
/// "12 Oct 2025".
String notificationTimeAgo(DateTime t, DateTime now) {
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  final days = _day(now).difference(_day(t)).inDays;
  if (days == 0) return '${diff.inHours} h ago';
  if (days == 1) return 'Yesterday';
  if (days < 7) return _weekdays[t.weekday - 1];
  final date = '${t.day} ${_months[t.month - 1]}';
  return t.year == now.year ? date : '$date ${t.year}';
}

/// Splits a newest-first list into Today, Yesterday, This week and Earlier,
/// leaving out the groups that would be empty.
List<(String, List<AppNotification>)> groupNotificationsByDay(
  Iterable<AppNotification> items,
  DateTime now,
) {
  const labels = ['Today', 'Yesterday', 'This week', 'Earlier'];
  final buckets = [for (final _ in labels) <AppNotification>[]];
  final today = _day(now);
  for (final n in items) {
    final t = DateTime.tryParse(n.created ?? '')?.toLocal();
    final days = t == null ? 7 : today.difference(_day(t)).inDays;
    final i = days <= 0
        ? 0
        : days == 1
        ? 1
        : days < 7
        ? 2
        : 3;
    buckets[i].add(n);
  }
  return [
    for (var i = 0; i < labels.length; i++)
      if (buckets[i].isNotEmpty) (labels[i], buckets[i]),
  ];
}
