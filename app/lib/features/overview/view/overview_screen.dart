import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/core/widgets/app_collection_header.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/router/return_to.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/refresh_on_entry.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/features/overview/inbox.dart';
import 'package:revoked_app/features/vault/view/vault_create_sheet.dart';

/// The signed-in landing page: what needs attention and what changed recently.
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
        group: 'Needs attention',
        rows: [
          AppSkeletonRow(
            '2 new answers to Payroll',
            '',
            icon: AppIcons.inboxFill,
          ),
          AppSkeletonRow('Wi-Fi link ends tomorrow', '', icon: AppIcons.clock),
        ],
      ),
      builder: _overview,
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
      limit: 5,
    );

    final sharesFailed = Stores.shares.loadState.error != null;
    final vaultFailed = Stores.vault.loadState.error != null;
    if (records.isEmpty &&
        links.isEmpty &&
        needs.isEmpty &&
        recent.isEmpty &&
        !sharesFailed &&
        !vaultFailed) {
      return const _FirstSteps();
    }

    final attention = AppListGroup(
      title: 'Needs attention',
      noun: 'items',
      previewCount: 6,
      trailing: needs.isEmpty ? const SizedBox.shrink() : null,
      children: [
        if (needs.isEmpty)
          AppListRow(
            icon: AppIcons.checkCircle,
            title: sharesFailed ? 'Share status unavailable' : 'All caught up',
          ),
        for (final item in needs)
          NeedRow(item: item, onTap: () => context.go(item.route)),
      ],
    );
    final activity = AppListGroup(
      title: 'Recent activity',
      trailing: const SizedBox.shrink(),
      children: [
        if (recent.isEmpty)
          const AppListRow(icon: AppIcons.clock, title: 'No recent activity'),
        for (final item in recent)
          AppListRow(
            icon: item.icon,
            title: item.title,
            subtitle: item.subtitle,
            trailing: AppText(ageLabel(item.at, now)).small.muted,
            onTap: () => context.go(item.route),
          ),
      ],
    );
    return AppPageBody(
      children: [
        AppCollectionHeader(
          title: 'Home',
          prominent: true,
          description: 'Review requests and shares that need attention.',
        ),
        if (sharesFailed) AppRefreshFailed(onRetry: Stores.shares.loadShares),
        if (vaultFailed) AppRefreshFailed(onRetry: Stores.vault.loadRecords),
        AppSpacing.gapLg,
        LayoutBuilder(
          builder: (context, box) {
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            if (box.maxWidth < AppSpacing.narrowWidth * scale) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [attention, activity],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: attention),
                AppSpacing.gapXxl,
                Expanded(flex: 4, child: activity),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One row of "Needs attention": a tinted icon, one line saying what and why, and
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
      titleMaxLines: null,
      onTap: onTap,
    );
  }
}

/// Help a new workspace make its first record or open the guided tour.
class _FirstSteps extends StatelessWidget {
  const _FirstSteps();

  @override
  Widget build(BuildContext context) => AppEmptyState(
    icon: AppIcons.safe,
    title: 'Welcome to Revoked',
    subtitle: 'Keep your information in one place and choose what to share.',
    example: const AppEmptyExample(
      title: 'Guest Wi-Fi',
      detail: 'A record in your vault',
      badge: 'Hidden',
    ),
    action: AppButton(
      icon: AppIcons.plus,
      label: 'Add a record',
      onTap: () => openVaultCreateSheet(context),
    ),
    secondaryAction: AppButton(
      icon: AppIcons.link,
      label: 'Take the tour',
      style: AppButtonStyle.outline,
      onTap: () => goReturning(context, AppRoutes.tour),
    ),
  );
}
