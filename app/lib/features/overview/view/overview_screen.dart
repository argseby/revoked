import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/utils/dates.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/refresh_on_entry.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_chart.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/attention_card.dart';
import 'package:revoked_app/core/widgets/tool_tag.dart';
import 'package:revoked_app/features/shares/utils/record_access.dart';
import 'package:revoked_app/features/shares/utils/recipients.dart';
import 'package:revoked_app/features/shares/view/link_groups.dart';
import 'package:revoked_app/features/shares/view/recipient_row.dart';
import 'package:revoked_app/features/vault/view/vault_create_sheet.dart';

/// Where the app lands: what needs the person, and who can read their data.
///
/// Four counts on top, then attention cards, each counting one kind of thing
/// and opening the list it counts. Below them, everything that can reach the
/// vault right now: people through links, connected tools and API keys, and
/// the records others can read. Someone new sees the three steps to a first
/// link instead.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> with RefreshOnEntry {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellSlots.title.claim(_title);
    });
  }

  @override
  void refresh() {
    Stores.shares.loadIfDue();
    Stores.vault.loadIfDue();
    Stores.connections.load();
    Stores.apiKeys.loadApiKeys();
    Stores.webhooks.loadIfDue();
  }

  @override
  void dispose() {
    ShellSlots.title.release(_title);
    super.dispose();
  }

  Widget _title(BuildContext context) => const AppBarTitle(title: 'Overview');

  @override
  Widget build(BuildContext context) {
    final shares = Stores.shares;
    final vault = Stores.vault;
    return AppLoadFade(
      loading: () =>
          (shares.loadState.isFirstLoad && shares.shares.isEmpty) ||
          (vault.loadState.isFirstLoad && vault.records.isEmpty),
      skeleton: const AppListSkeleton(
        group: 'Data access',
        rows: [
          AppSkeletonRow('IBAN', 'Readable by 2 people', icon: AppIcons.lock),
          AppSkeletonRow(
            'Home address',
            'Readable by 1 person',
            icon: AppIcons.lock,
          ),
        ],
      ),
      builder: (context) {
        if (vault.records.isEmpty &&
            shares.shares.isEmpty &&
            Stores.connections.connections.isEmpty &&
            Stores.apiKeys.apiKeys.isEmpty) {
          return const _FirstSteps();
        }
        return Observer(builder: _overview);
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
      if (answers > 0 && Stores.features.visible(Feature.requests))
        AttentionCard(
          tone: AttentionTone.info,
          icon: AppIcons.inboxFill,
          label: 'New answers',
          value: '$answers ${answers == 1 ? 'answer' : 'answers'}',
          detail: 'Responses to requests',
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
              : 'Expiring or near the view limit',
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
          detail: 'Unavailable until reactivated',
          onTap: () => context.go(AppRoutes.shared),
        ),
    ];

    final failing = Stores.webhooks.endpoints.where((e) => e.isFailing).length;
    if (failing > 0) {
      cards.add(
        AttentionCard(
          tone: AttentionTone.warning,
          icon: AppIcons.send,
          label: 'Webhooks failing',
          value: '$failing ${failing == 1 ? 'webhook' : 'webhooks'}',
          detail: 'Deliveries are not getting through',
          onTap: () => context.go(AppRoutes.webhooks),
        ),
      );
    }
    final keys = Stores.apiKeys.apiKeys;
    final expiring = keys.where((k) => _endsWithinAWeek(k.expiresAt, now));
    if (expiring.isNotEmpty) {
      cards.add(
        AttentionCard(
          tone: AttentionTone.warning,
          icon: AppIcons.key,
          label: 'Keys expiring',
          value: '${expiring.length} ${expiring.length == 1 ? 'key' : 'keys'}',
          detail: 'Within the next seven days',
          onTap: () => context.go(AppRoutes.apiKeys),
        ),
      );
    }

    final recipients = groupByRecipient(
      links,
    ).where(recipientHasAccess).toList();
    final readable = openAccessByRecord(
      links: links,
      sections: Stores.vault.sections,
      records: Stores.vault.records,
    );
    final tools = [
      for (final c in Stores.connections.connections)
        if (!c.isExpired) c,
    ];
    final active = links.where((l) => l.status == 'active').length;

    return AppPageBody(
      children: [
        _Figures(
          tiles: [
            AppStatTile(
              icon: AppIcons.link,
              label: 'Active links',
              value: '$active',
            ),
            AppStatTile(
              icon: AppIcons.person,
              label: 'People with access',
              value: '${recipients.length}',
            ),
            AppStatTile(
              icon: AppIcons.plug,
              label: 'Connected tools',
              value: '${tools.length}',
            ),
            AppStatTile(
              icon: AppIcons.key,
              label: 'API keys',
              value: '${keys.length}',
            ),
          ],
        ),
        AppSpacing.gapLg,
        if (cards.isNotEmpty) ...[_Cards(cards: cards), AppSpacing.gapLg],
        AppListGroup(
          title: 'People',
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
                    title: 'No recipients',
                    subtitle: 'Nothing is currently shared.',
                  ),
                ]
              : [for (final r in recipients) RecipientRow(r)],
        ),
        if (tools.isNotEmpty)
          AppListGroup(
            title: 'Connected tools',
            noun: 'tools',
            previewCount: 5,
            children: [
              for (final c in tools)
                AppListRow(
                  icon: AppIcons.plug,
                  title: c.name,
                  subtitle: [
                    _toolReach(c.allowVaultRead, c.reachedSections.length),
                    _lastUsed(c.lastUsedAt),
                  ].join(' · '),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (c.paused)
                        const AppBadge(
                          icon: AppIcons.pauseCircle,
                          label: 'Paused',
                        )
                      else if (c.allowVaultRead)
                        const AppBadge(
                          icon: AppIcons.exclamationTriangle,
                          label: 'Whole vault',
                          variant: AppBadgeVariant.outline,
                        ),
                      AppSpacing.gapXxs,
                      ToolIdChip(c.id),
                    ],
                  ),
                  onTap: () => context.go(AppRoutes.connectedToolFor(c.id)),
                ),
            ],
          ),
        if (keys.isNotEmpty)
          AppListGroup(
            title: 'API keys',
            noun: 'keys',
            previewCount: 5,
            children: [
              for (final k in keys)
                AppListRow(
                  icon: AppIcons.key,
                  title: k.label,
                  subtitle: [
                    _toolReach(
                      false,
                      k.vaultAccess.isEmpty ? 0 : k.sections.length,
                    ),
                    _lastUsed(k.lastUsedAt),
                    if (dayOf(k.expiresAt) case final day?) 'Expires $day',
                  ].join(' · '),
                  onTap: () => context.go(AppRoutes.apiKeys),
                ),
            ],
          ),
        if (readable.isNotEmpty)
          AppListGroup(
            title: 'Shared records',
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
      ],
    );
  }
}

String _toolReach(bool wholeVault, int sections) {
  if (wholeVault) return 'Whole vault';
  if (sections == 0) return 'No vault access';
  return '$sections ${sections == 1 ? 'section' : 'sections'}';
}

String _lastUsed(String? at) {
  final day = dayOf(at);
  return day == null ? 'Never used' : 'Last used $day';
}

bool _endsWithinAWeek(String? at, DateTime now) {
  final end = parseInstant(at);
  return end != null &&
      end.isAfter(now) &&
      end.isBefore(now.add(const Duration(days: 7)));
}

/// The four counts, in a row where there is room and two by two on a phone.
class _Figures extends StatelessWidget {
  final List<Widget> tiles;

  const _Figures({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth < 520 ? 2 : tiles.length;
        return Column(
          children: [
            for (var r = 0; r < tiles.length; r += columns) ...[
              if (r > 0) AppSpacing.gapSm,
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var i = r;
                      i < r + columns && i < tiles.length;
                      i++
                    ) ...[
                      if (i > r) AppSpacing.gapSm,
                      Expanded(child: tiles[i]),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
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
          'A short tour covers the two core functions: storing data in the '
          'vault and sharing it. It takes about a minute, and every change '
          'can be undone.',
        ).muted,
        AppSpacing.gapLg,
        AppListGroup(
          title: 'Setup',
          trailing: const SizedBox.shrink(),
          children: [
            AppListRow(
              leading: Center(
                child: Icon(AppIcons.checkCircle, color: scheme.primary),
              ),
              title: 'Create account',
              subtitle: 'Done',
            ),
            AppListRow(
              icon: AppIcons.key,
              title: 'Add a record',
              subtitle: 'Such as a name, address or IBAN',
              onTap: () => openVaultCreateSheet(context),
            ),
            AppListRow(
              icon: AppIcons.link,
              title: 'Share and revoke',
              subtitle: 'One-minute tour with real data',
              onTap: () => context.go(AppRoutes.tour),
            ),
          ],
        ),
      ],
    );
  }
}
