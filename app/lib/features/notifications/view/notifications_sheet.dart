import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/notification.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';

void openNotificationsSheet(BuildContext context) {
  showAppSheet(
    context: context,
    builder: (context) => const NotificationsSheet(),
  );
}

class NotificationsSheet extends StatefulWidget {
  const NotificationsSheet({super.key});

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Stores.notifications.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.notifications;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.sm,
              AppSpacing.xxl,
              AppSpacing.lg,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Notifications').header,
                Observer(
                  builder: (_) {
                    if (store.unreadCount > 0) {
                      return AppButton(
                        label: 'Mark all as read',
                        onTap: store.markAllRead,
                        style: AppButtonStyle.accent,
                      );
                    }
                    return const SizedBox();
                  },
                ),
              ],
            ),
          ),
          const AppDivider(),
          Expanded(
            child: Observer(
              builder: (context) {
                if (store.isLoading && store.notifications.isEmpty) {
                  return const Center(child: AppSpinner(large: true));
                }

                if (store.notifications.isEmpty) {
                  return AppEmptyState(
                    icon: AppIcons.bellSlash,
                    title: 'No notifications',
                    subtitle: 'You are all caught up.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: store.notifications.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final notif = store.notifications[index];
                    return _NotificationCard(
                      notification: notif,
                      onMarkRead: () => store.markRead(notif.id, read: true),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onMarkRead;

  const _NotificationCard({
    required this.notification,
    required this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = !notification.read;
    final created = notification.created;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isUnread) ...[
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.xs),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ] else
            const SizedBox(width: AppSpacing.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notification.title),
                const SizedBox(height: AppSpacing.xxs),
                Text(notification.message ?? '').small.muted,
                if (created != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_formatTime(created)).muted.small,
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (isUnread)
            AppButton(
              icon: AppIcons.check,
              tooltip: 'Mark read',
              style: AppButtonStyle.accent,
              onTap: onMarkRead,
            ),
        ],
      ),
    );
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }
}
