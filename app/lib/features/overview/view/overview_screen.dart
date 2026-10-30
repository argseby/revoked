import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/notification.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/attention_card.dart';
import 'package:revoked_app/features/notifications/view/notifications_sheet.dart';
import 'package:revoked_app/features/shares/utils/record_access.dart';
import 'package:revoked_app/features/shares/utils/recipients.dart';
import 'package:revoked_app/features/shares/view/link_groups.dart';
import 'package:revoked_app/features/shares/view/recipient_row.dart';
import 'package:revoked_app/features/vault/view/vault_create_sheet.dart';

/// Where the app lands: what needs the person, and who can read their data.
///
/// Each attention card counts one kind of thing and opens the list it
/// counts. Below them, the recipients who can see something right now, the
/// records others can read, and what happened lately. Someone new sees the
/// three steps to a first link instead.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellSlots.title.claim(_title);
      Stores.shares.loadShares();
      Stores.vault.loadRecords();
    });
  }

  @override
  void dispose() {
    ShellSlots.title.release(_title);
    super.dispose();
  }

  Widget _title(BuildContext context) => const AppBarTitle(title: 'Overview');

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final shares = Stores.shares;
        final vault = Stores.vault;
        if ((shares.isLoading && shares.shares.isEmpty) ||
            (vault.isLoading && vault.records.isEmpty)) {
          return const Center(child: AppSpinner(large: true));
        }
        if (vault.records.isEmpty && shares.shares.isEmpty) {
          return const _FirstSteps();
        }
        return _overview(context);
      },
    );
  }

  Widget _overview(BuildContext context) {
    final now = DateTime.now();
    final links = Stores.shares.shares;
    final answers = Stores.notifications.unreadResponseCount;
    final soon = [
      for (final l in links)
        if (linkGroup(l, now) == LinkGroup.attention) l,
    ];
    final paused = links.where((l) => l.status == 'paused').length;

    final cards = <Widget>[
      if (answers > 0)
        AttentionCard(
          tone: AttentionTone.info,
          icon: AppIcons.inboxFill,
          label: 'New answers',
          value: '$answers ${answers == 1 ? 'answer' : 'answers'}',
          detail: 'To your requests',
          onTap: () => context.go(AppRoutes.requests),
        ),
      if (soon.isNotEmpty)
        AttentionCard(
          tone: AttentionTone.warning,
          icon: AppIcons.clock,
          label: 'Ends soon',
          value: '${soon.length} ${soon.length == 1 ? 'link' : 'links'}',
          detail: soon.length == 1
              ? '${soon.first.label}: ${linkAttention(soon.first, now)!.reason}'
              : 'Running out of time or views',
          onTap: () => context.go(
            soon.length == 1
                ? AppRoutes.shareDetailFor(soon.first.id)
                : AppRoutes.shared,
          ),
        ),
      if (paused > 0)
        AttentionCard(
          tone: AttentionTone.warning,
          icon: AppIcons.pauseCircle,
          label: 'Paused',
          value: '$paused ${paused == 1 ? 'link' : 'links'}',
          detail: 'Nobody can open them until you turn them back on',
          onTap: () => context.go(AppRoutes.shared),
        ),
    ];

    final recipients = groupByRecipient(
      links,
    ).where(recipientHasAccess).toList();
    final readable = openAccessByRecord(
      links: links,
      sections: Stores.vault.sections,
      records: Stores.vault.records,
    );
    final recent = Stores.notifications.notifications.take(5).toList();

    return AppPageBody(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Semantics(
            liveRegion: true,
            child: Text(
              cards.isEmpty
                  ? 'Nothing needs you right now.'
                  : cards.length == 1
                  ? 'One thing needs you.'
                  : '${cards.length} things need you.',
            ),
          ),
        ),
        if (cards.isNotEmpty) ...[_Cards(cards: cards), AppSpacing.gapLg],
        AppListGroup(
          title: 'Who can see your data',
          noun: 'recipients',
          previewCount: 5,
          trailing: recipients.isEmpty
              ? const SizedBox.shrink()
              : AppButton(
                  icon: AppIcons.arrowRight,
                  label: 'All',
                  style: AppButtonStyle.ghost,
                  size: AppButtonSize.small,
                  onTap: () => context.go(AppRoutes.shared),
                ),
          children: recipients.isEmpty
              ? [
                  AppListRow(
                    icon: AppIcons.lock,
                    title: 'Nobody',
                    subtitle: 'You aren\'t sharing anything right now.',
                  ),
                ]
              : [for (final r in recipients) RecipientRow(r)],
        ),
        if (readable.isNotEmpty)
          AppListGroup(
            title: 'What others can see',
            noun: 'records',
            previewCount: 5,
            children: [
              for (final (record, access) in readable)
                AppListRow(
                  icon: record.isFile ? AppIcons.fileEarmark : AppIcons.key,
                  title: record.label.isEmpty ? record.key : record.label,
                  subtitle:
                      '${access.length} '
                      '${access.length == 1 ? 'link' : 'links'}',
                  onTap: () => context.go(AppRoutes.recordDetailFor(record.id)),
                ),
            ],
          ),
        if (recent.isNotEmpty)
          AppListGroup(
            title: 'Recent activity',
            noun: 'notifications',
            trailing: const SizedBox.shrink(),
            children: [for (final n in recent) _ActivityRow(n)],
          ),
      ],
    );
  }
}

/// Side by side where there is room, stacked on a phone.
class _Cards extends StatelessWidget {
  final List<Widget> cards;

  const _Cards({required this.cards});

  @override
  Widget build(BuildContext context) {
    if (AppSpacing.isNarrow(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) AppSpacing.gapSm,
            cards[i],
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) AppSpacing.gapMd,
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final AppNotification notification;

  const _ActivityRow(this.notification);

  @override
  Widget build(BuildContext context) {
    return AppListRow(
      icon: notification.read ? AppIcons.bell : AppIcons.recordCircleFill,
      title: notification.title,
      subtitle: notification.message,
      onTap: () => openNotificationsSheet(context),
    );
  }
}

/// Someone new: an empty vault and no links. Three steps to a first link,
/// the first already done by getting here.
class _FirstSteps extends StatelessWidget {
  const _FirstSteps();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppPageBody(
      children: [
        const AppText('Welcome').header,
        AppSpacing.gapXxs,
        const Text(
          'You\'re in. Get started with a short tour of the two things that '
          'matter most: adding something to your vault and sharing it. It '
          'takes a minute, and you can undo all of it.',
        ).muted,
        AppSpacing.gapLg,
        AppListGroup(
          title: 'Getting started',
          trailing: const SizedBox.shrink(),
          children: [
            AppListRow(
              leading: Center(
                child: Icon(AppIcons.checkCircle, color: scheme.primary),
              ),
              title: 'Create your account',
              subtitle: 'Done',
            ),
            AppListRow(
              icon: AppIcons.key,
              title: 'Add your first record',
              subtitle: 'A name, an address or an IBAN',
              onTap: () => openVaultCreateSheet(context),
            ),
            AppListRow(
              icon: AppIcons.link,
              title: 'Share it, then take it back',
              subtitle: 'Try it with your own data in a one-minute tour',
              onTap: () => context.go(AppRoutes.tour),
            ),
          ],
        ),
      ],
    );
  }
}
