import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/state/refresh_on_entry.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_filter_chips.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/core/widgets/app_tabs.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';
import 'package:revoked_app/features/shares/view/link_groups.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/features/shares/view/share_create_sheet.dart';
import 'package:revoked_app/features/vault/view/vault_create_sheet.dart';
import 'package:revoked_app/features/shares/utils/recipients.dart';
import 'package:revoked_app/features/shares/view/recipient_row.dart';

/// Which links the chips above the list let through.
enum _LinkFilter { all, active, paused, closed }

class SharesScreen extends StatefulWidget {
  /// Narrows the list to one recipient's links, opened from "By person".
  /// Their name, which is what a link's label holds.
  final String? recipient;

  /// The link open beside the list, marked in it. Only in a split.
  final String? selectedId;

  const SharesScreen({super.key, this.recipient, this.selectedId});

  @override
  State<SharesScreen> createState() => _SharesScreenState();
}

class _SharesScreenState extends State<SharesScreen> with RefreshOnEntry {
  late final TableStore<Link> _table;
  final Local<_LinkFilter> _filter = Local(_LinkFilter.all);

  @override
  void initState() {
    super.initState();
    _table = TableStore<Link>(
      getSourceItems: () => Stores.shares.shares.toList(),
      fieldGetters: {
        'label': (l) => l.label,
        'slug': (l) => l.slug,
        'status': (l) => l.status,
        'created': (l) => l.created ?? '',
      },
      defaultSort: 'created_desc',
    );
  }

  @override
  void refresh() {
    Stores.shares.loadIfDue();
    Stores.bookmarks.loadIfDue();
    Stores.vault.loadIfDue();
    Stores.identities.loadIfDue();
  }

  @override
  void dispose() {
    _table.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Access by record moved to the record pages and the Overview, and
    // links others gave you to Requests › Received.
    return AppTabs(
      tabs: [
        AppTab(
          label: 'Links',
          icon: AppIcons.link,
          description: 'Every share link, by status.',
          view: _myLinks(context),
        ),
        const AppTab(
          label: 'By person',
          icon: AppIcons.person,
          description: 'Shared access, grouped by recipient.',
          view: _ByPerson(),
        ),
      ],
    );
  }

  Widget _myLinks(BuildContext context) {
    final store = Stores.shares;

    return AppLoadFade(
      loading: () => store.loadState.isFirstLoad && store.shares.isEmpty,
      skeleton: const AppListSkeleton(
        filters: ['All', 'Active', 'Paused', 'Closed'],
        group: 'Active',
        rows: [
          AppSkeletonRow(
            'Landlord',
            '3 records · opened twice',
            icon: AppIcons.link,
          ),
          AppSkeletonRow('Employer HR', '5 records', icon: AppIcons.link),
          AppSkeletonRow(
            'Insurance',
            '2 records · expires soon',
            icon: AppIcons.link,
          ),
          AppSkeletonRow('Bank', '1 record', icon: AppIcons.link),
        ],
      ),
      builder: (_) {
        if (store.shares.isEmpty && store.loadState.error != null) {
          return AppLoadError(
            title: 'Links could not be loaded',
            message: store.loadState.error!,
            onRetry: store.loadShares,
          );
        }

        if (store.shares.isEmpty) {
          final vault = Stores.vault;
          // A link points at vault records; with none there is nothing to
          // pick, so the first step is the vault, not the link form.
          final vaultEmpty =
              !vault.isLoading &&
              vault.records.isEmpty &&
              vault.sections.isEmpty;
          final newLink = AppButton(
            icon: AppIcons.plus,
            label: 'New link',
            style: vaultEmpty ? AppButtonStyle.accent : AppButtonStyle.primary,
            onTap: () => openShareCreateSheet(context: context),
          );
          return AppEmptyState(
            icon: AppIcons.share,
            title: 'No links',
            subtitle:
                'Links share records without handing over a copy. Recipients '
                'see the current version until the link is revoked.',
            example: const AppEmptyExample(
              title: 'Onboarding pack',
              detail: '3 records',
              badge: 'active',
            ),
            steps: const [
              AppEmptyStep('Records or a section', 'From the vault'),
              AppEmptyStep(
                'Access control',
                'Password, identifier or verified identity',
              ),
              AppEmptyStep('Revocation', 'Paused, expired or revoked'),
            ],
            notice: vaultEmpty
                ? 'The vault is empty. Only existing records can be shared.'
                : null,
            action: vaultEmpty
                ? AppButton(
                    icon: AppIcons.plus,
                    label: 'Add a record',
                    onTap: () => openVaultCreateSheet(context),
                  )
                : newLink,
            secondaryAction: vaultEmpty ? newLink : null,
            learnMoreLabel: 'How sharing works',
            learnMoreUrl: '${AppConfig.docsUrl}/guide/sharing/',
          );
        }

        final now = DateTime.now();
        final recipient = widget.recipient?.trim();
        final matches = recipient == null || recipient.isEmpty
            ? _table.filteredItems
            : _table.filteredItems
                  .where((l) => l.label.trim() == recipient)
                  .toList();
        final byGroup = {for (final g in LinkGroup.values) g: <Link>[]};
        for (final l in matches) {
          byGroup[linkGroup(l, now)]!.add(l);
        }
        final live =
            byGroup[LinkGroup.attention]!.length +
            byGroup[LinkGroup.active]!.length;
        final filter = _filter.value;

        bool shows(LinkGroup g) => switch (filter) {
          _LinkFilter.all => true,
          _LinkFilter.active =>
            g == LinkGroup.attention || g == LinkGroup.active,
          _LinkFilter.paused => g == LinkGroup.paused,
          _LinkFilter.closed => g == LinkGroup.closed,
        };

        Widget group(LinkGroup g, String title, {bool collapsed = false}) {
          final links = byGroup[g]!;
          if (links.isEmpty || !shows(g)) return const SizedBox.shrink();
          return AppListGroup(
            // A new filter starts the group over, so picking "Closed" opens
            // the group it would otherwise keep folded.
            key: ValueKey('$g-$filter'),
            title: title,
            noun: 'links',
            previewCount: g == LinkGroup.attention ? 0 : 5,
            collapsed: collapsed,
            children: [
              for (final l in links)
                _LinkRow(
                  share: l,
                  selected: l.id == widget.selectedId,
                  attention: linkAttention(l, now),
                  onTap: () => context.go(AppRoutes.shareDetailFor(l.id)),
                ),
            ],
          );
        }

        final nothingShown = LinkGroup.values.every(
          (g) => byGroup[g]!.isEmpty || !shows(g),
        );

        return AppListPage(
          banners: [
            if (store.loadState.error != null)
              AppRefreshFailed(onRetry: store.loadShares),
            if (recipient != null && recipient.isNotEmpty)
              AppListBanner(
                icon: AppIcons.person,
                message: 'Links for $recipient',
                action: AppButton(
                  icon: AppIcons.x,
                  label: 'Show all',
                  style: AppButtonStyle.accent,
                  size: AppButtonSize.small,
                  onTap: () => context.go(AppRoutes.shared),
                ),
              ),
          ],
          filters: AppFilterChips<_LinkFilter>(
            selected: filter,
            onSelected: (f) => _filter.value = f,
            options: [
              AppFilterOption(
                value: _LinkFilter.all,
                label: 'All',
                count: matches.length,
              ),
              AppFilterOption(
                value: _LinkFilter.active,
                label: 'Active',
                count: live,
              ),
              AppFilterOption(
                value: _LinkFilter.paused,
                label: 'Paused',
                count: byGroup[LinkGroup.paused]!.length,
              ),
              AppFilterOption(
                value: _LinkFilter.closed,
                label: 'Closed',
                count: byGroup[LinkGroup.closed]!.length,
              ),
            ],
          ),
          emptyMessage: nothingShown ? 'No links match the filters.' : null,
          groups: [
            group(LinkGroup.attention, 'Needs attention'),
            group(LinkGroup.active, 'Active'),
            group(LinkGroup.paused, 'Paused'),
            group(
              LinkGroup.closed,
              'Revoked or expired',
              collapsed: filter != _LinkFilter.closed,
            ),
          ],
        );
      },
    );
  }
}

/// One link in the list: what it is, one line on where it stands, one badge.
/// Its flags, slug and actions live on its detail page.
class _LinkRow extends StatelessWidget {
  final Link share;
  final bool selected;
  final LinkAttention? attention;
  final VoidCallback onTap;

  const _LinkRow({
    required this.share,
    required this.attention,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attention = this.attention;

    return AppListRow(
      icon: share.isFromTool
          ? AppIcons.globe
          : share.isFromRequest
          ? AppIcons.inboxFill
          : AppIcons.link,
      title: share.label,
      selected: selected,
      subtitle: attention?.reason ?? _summary(),
      trailing: attention != null
          ? AppBadge(label: attention.short, accent: theme.colorScheme.warning)
          : StatusLabel(share.status),
      onTap: onTap,
    );
  }

  /// "From notfallkarte.example · 3 records · viewed 2×"
  String _summary() {
    final parts = <String>[];
    if (share.isFromTool) {
      parts.add('From ${share.proposedByHost}');
    } else if (share.isFromRequest) {
      parts.add('For a request');
    }

    final sections = share.sections.length;
    final records = share.records.length;
    if (sections == 0 && records == 0) {
      parts.add('Nothing selected');
    } else {
      if (sections > 0) {
        parts.add('$sections ${sections == 1 ? 'section' : 'sections'}');
      }
      if (records > 0) {
        parts.add('$records ${records == 1 ? 'record' : 'records'}');
      }
    }

    parts.add(
      share.viewCount == 0 ? 'not viewed' : 'viewed ${share.viewCount}×',
    );
    return parts.join(' · ');
  }
}

/// The same links, one row per recipient: who can see the person's data, and
/// who no longer can.
class _ByPerson extends StatelessWidget {
  const _ByPerson();

  @override
  Widget build(BuildContext context) {
    return AppLoadFade(
      loading: () =>
          Stores.shares.loadState.isFirstLoad && Stores.shares.shares.isEmpty,
      skeleton: const AppListSkeleton(
        group: 'With access',
        rows: [
          AppSkeletonRow(
            'Landlord',
            '2 links · 5 records',
            icon: AppIcons.person,
          ),
          AppSkeletonRow(
            'Employer',
            '1 link · 3 records',
            icon: AppIcons.person,
          ),
          AppSkeletonRow(
            'Insurance',
            '1 link · 2 records',
            icon: AppIcons.person,
          ),
        ],
      ),
      builder: (context) {
        final groups = groupByRecipient(Stores.shares.shares);
        if (groups.isEmpty) {
          return AppEmptyState(
            icon: AppIcons.lock,
            title: 'No recipients',
            subtitle:
                'Each recipient is listed once, with everything they can see.',
            example: const AppEmptyExample(
              title: 'Landlord',
              detail: '2 links · 5 records',
              badge: 'can see',
            ),
            steps: const [
              AppEmptyStep(
                'Recipient per link',
                'A person, a company or a service',
              ),
              AppEmptyStep(
                'Grouped links',
                'One row per recipient, however many links',
              ),
              AppEmptyStep(
                'Revocation',
                'Revoked links stop working immediately',
              ),
            ],
            action: AppButton(
              icon: AppIcons.plus,
              label: 'New link',
              onTap: () => openShareCreateSheet(context: context),
            ),
          );
        }
        final current = groups.where(recipientHasAccess).toList();
        final former = groups.where((g) => !recipientHasAccess(g)).toList();
        return AppListPage(
          groups: [
            if (current.isNotEmpty)
              AppListGroup(
                title: 'With access',
                noun: 'recipients',
                footer: const Text(
                  'Grouped by link name. Paused links count until revoked.',
                ),
                children: [for (final links in current) RecipientRow(links)],
              ),
            if (former.isNotEmpty)
              AppListGroup(
                title: 'Access ended',
                noun: 'recipients',
                collapsed: true,
                children: [for (final links in former) RecipientRow(links)],
              ),
          ],
        );
      },
    );
  }
}
