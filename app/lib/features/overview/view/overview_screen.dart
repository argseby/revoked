import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/core/widgets/app_collection_header.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/router/return_to.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
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
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/tool_tag.dart';
import 'package:revoked_app/features/overview/inbox.dart';
import 'package:revoked_app/features/shares/utils/record_access.dart';
import 'package:revoked_app/features/shares/utils/recipients.dart';
import 'package:revoked_app/features/shares/view/recipient_row.dart';
import 'package:revoked_app/features/vault/view/vault_create_sheet.dart';

/// Where the app lands, read like an inbox: what needs the person, then what
/// changed lately.
///
/// One line of counts on top, each opening the list it counts. Below it
/// "Needs you", one row per concrete thing — an answer to read, a link about
/// to end, a failing webhook — and "Recent", the records, links and answers
/// that changed last. People, connected tools and API keys follow as short
/// previews. Someone new sees the three steps to a first link instead.
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
    // Only for the names of the requests that got answers.
    if (Stores.features.visible(Feature.requests)) {
      Stores.requests.loadIfDue();
    }
  }

  @override
  void dispose() {
    ShellSlots.title.release(_title);
    super.dispose();
  }

  Widget _title(BuildContext context) => const AppBarTitle(title: 'Home');

  @override
  Widget build(BuildContext context) {
    final shares = Stores.shares;
    final vault = Stores.vault;
    return AppLoadFade(
      loading: () =>
          (shares.loadState.isFirstLoad && shares.shares.isEmpty) ||
          (vault.loadState.isFirstLoad && vault.records.isEmpty),
      skeleton: const AppListSkeleton(
        group: 'Needs you',
        rows: [
          AppSkeletonRow(
            '2 new answers to Payroll',
            '',
            icon: AppIcons.inboxFill,
          ),
          AppSkeletonRow('Wi-Fi link ends tomorrow', '', icon: AppIcons.clock),
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
    final showAnswers = Stores.features.visible(Feature.requests);
    final notifications = Stores.notifications.notifications;
    final requests = Stores.requests.requests;
    final keys = Stores.apiKeys.apiKeys;
    final records = Stores.vault.records;

    final needs = needsYouItems(
      links: links,
      notifications: notifications,
      requests: requests,
      webhooks: Stores.webhooks.endpoints,
      apiKeys: keys,
      now: now,
      showAnswers: showAnswers,
    );
    final recent = recentItems(
      records: records,
      sections: Stores.vault.sections,
      links: links,
      notifications: notifications,
      requests: requests,
      showAnswers: showAnswers,
    );

    final recipients = groupByRecipient(
      links,
    ).where(recipientHasAccess).toList();
    final readable = openAccessByRecord(
      links: links,
      sections: Stores.vault.sections,
      records: records,
    );
    final tools = [
      for (final c in Stores.connections.connections)
        if (!c.isExpired) c,
    ];
    final active = links.where((l) => l.status == 'active').length;
    final recordCount = records.where((r) => !r.isAlias).length;

    return AppPageBody(
      children: [
        AppCollectionHeader(
          title: 'Home',
          description: 'Your inbound and outgoing information at a glance.',
          action: AppButton(
            icon: AppIcons.plus,
            label: 'Add item',
            onTap: () => openVaultCreateSheet(context),
          ),
        ),
        AppListGroup(
          title: needs.isEmpty ? 'All clear' : 'Needs your attention',
          noun: 'items',
          previewCount: 6,
          trailing: needs.isEmpty
              ? const SizedBox.shrink()
              : AppText('${needs.length}').small.muted,
          children: needs.isEmpty
              ? [
                  AppListRow(
                    icon: AppIcons.checkCircle,
                    title: 'You’re up to date',
                    subtitle: 'Nothing needs your attention right now.',
                  ),
                ]
              : [
                  for (final item in needs)
                    NeedRow(item: item, onTap: () => context.go(item.route)),
                ],
        ),
        _Stats(
          figures: [
            _Figure(
              active,
              AppRoutes.shared,
              AppIcons.link,
            ),
            _Figure(
              recipients.length,
              AppRoutes.shared,
              AppIcons.person,
            ),
            _Figure(
              recordCount,
              AppRoutes.vault,
              AppIcons.lock,
            ),
          ],
        ),
        AppSpacing.gapLg,
        if (recent.isNotEmpty)
          AppListGroup(
            title: 'Recent activity',
            previewCount: 5,
            trailing: const SizedBox.shrink(),
            children: [
              for (final item in recent)
                AppListRow(
                  icon: item.icon,
                  title: item.title,
                  subtitle: item.subtitle,
                  trailing: AppText(ageLabel(item.at, now)).small.muted,
                  onTap: () => context.go(item.route),
                ),
            ],
          ),
        AppListGroup(
          title: 'People',
          noun: 'recipients',
          previewCount: 3,
          trailing: recipients.isEmpty
              ? const SizedBox.shrink()
              : _AllButton(route: AppRoutes.shared),
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
            collapsed: true,
            noun: 'tools',
            previewCount: 3,
            trailing: _AllButton(route: AppRoutes.connectedTools),
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
        // While nothing is connected, a way to find what can be: on a phone
        // the Works with Revoked tab sits behind More.
        if (tools.isEmpty &&
            Stores.features.visible(Feature.tools) &&
            Stores.worksWith.services.isNotEmpty)
          AppListGroup(
            title: 'Works with Revoked',
            trailing: _AllButton(route: AppRoutes.worksWith),
            children: [
              AppListRow(
                icon: AppIcons.worksWith,
                title: 'Services that work with Revoked',
                subtitle: [
                  for (final s in Stores.worksWith.services.take(3)) s.name,
                ].join(', '),
                onTap: () => context.go(AppRoutes.worksWith),
              ),
            ],
          ),
        if (keys.isNotEmpty)
          AppListGroup(
            title: 'API keys',
            collapsed: true,
            noun: 'keys',
            previewCount: 3,
            trailing: _AllButton(route: AppRoutes.apiKeys),
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
        // Recent shows what changed; this is the full answer to "who can
        // read what", folded away until asked for.
        if (readable.isNotEmpty)
          AppListGroup(
            title: 'Shared records',
            noun: 'records',
            collapsed: true,
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

class _AllButton extends StatelessWidget {
  final String route;

  const _AllButton({required this.route});

  @override
  Widget build(BuildContext context) {
    return AppButton(
      icon: AppIcons.arrowRight,
      label: 'All',
      style: AppButtonStyle.ghost,
      size: AppButtonSize.small,
      onTap: () => context.go(route),
    );
  }
}

/// One row of "Needs you": a tinted icon, one line saying what and why, and
/// a chevron to the thing itself.
class NeedRow extends StatelessWidget {
  final NeedItem item;
  final VoidCallback onTap;

  const NeedRow({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (item.tone) {
      NeedTone.info => scheme.accent,
      NeedTone.warning => scheme.warning,
    };
    return AppListRow(
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: AppRadius.allMd,
        ),
        child: Icon(item.icon, size: 18, color: color),
      ),
      title: item.text,
      onTap: onTap,
    );
  }
}

/// One count in the strip: "12 active links".
class _Figure {
  final int count;
  final String route;
  final IconData icon;

  const _Figure(this.count, this.route, this.icon);
}

/// Clear destinations instead of one dense strip of counters.
class _Stats extends StatelessWidget {
  final List<_Figure> figures;
  const _Stats({required this.figures});

  @override
  Widget build(BuildContext context) => AppCollectionGrid(
    children: [
      for (final figure in figures)
        AppCollectionTile(
          title: figure.route == AppRoutes.vault
              ? 'Your vault'
              : figure.icon == AppIcons.person
              ? 'People'
              : 'Shared by you',
          value: '${figure.count}',
          description: figure.route == AppRoutes.vault
              ? 'Browse your saved information'
              : figure.icon == AppIcons.person
              ? 'Review who holds your links'
              : 'Manage shared access',
          icon: figure.icon,
          onTap: () => context.go(figure.route),
        ),
    ],
  );
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
        const AppCollectionHeader(
          title: 'Welcome to Revoked',
          description:
              'Keep your information in one place. Share only what you choose.',
        ),
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
              onTap: () => goReturning(context, AppRoutes.tour),
            ),
          ],
        ),
      ],
    );
  }
}
