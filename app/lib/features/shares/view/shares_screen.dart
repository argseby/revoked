import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/models/bookmark.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_segmented.dart';
import 'package:revoked_app/features/bookmarks/view/bookmarks_tab.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/refresh_on_entry.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
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

class SharesScreen extends StatefulWidget {
  /// Narrows the list to one recipient's links, opened from "By person".
  /// Their name, which is what a link's label holds.
  final String? recipient;

  /// The link open beside the list, marked in it. Only in a split.
  final String? selectedId;

  /// 1 opens on Received, the shares others gave this account.
  final int initialTab;

  const SharesScreen({
    super.key,
    this.recipient,
    this.selectedId,
    this.initialTab = 0,
  });

  @override
  State<SharesScreen> createState() => _SharesScreenState();
}

class _SharesScreenState extends State<SharesScreen> with RefreshOnEntry {
  late final TableStore<Link> _table;

  /// Sent links by status, or by the person they went to.
  final Local<bool> _byPerson = Local(false);

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
    // Access by record moved to the record pages and the Overview. The same
    // two tabs as Requests: what this account gave, and what it was given.
    return AppTabs(
      initialIndex: widget.initialTab,
      tabs: [
        AppTab(
          label: 'Sent',
          icon: AppIcons.send,
          description: 'Share links made here, by status or by person.',
          view: _sent(context),
        ),
        const AppTab(
          label: 'Received',
          icon: AppIcons.bookmark,
          description: 'Shares others gave this account, and ones saved.',
          view: BookmarksTab(kind: BookmarkKind.share),
        ),
      ],
    );
  }

  /// The links, with a switch between grouping them by status and by the
  /// person they went to: two views of the same list, so not tabs of their
  /// own.
  Widget _sent(BuildContext context) {
    final inset = AppSpacing.screenH(context);
    return Observer(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(inset, AppSpacing.xxs, inset, 0),
            // At the end of the row, like the other tabs' tools: a view of
            // the list, not a second row of tabs.
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AppSegmented<bool>(
                value: _byPerson.value,
                onChanged: (v) => _byPerson.value = v,
                items: const [
                  AppSegmentedItem(
                    value: false,
                    label: 'By status',
                    icon: AppIcons.cardList,
                  ),
                  AppSegmentedItem(
                    value: true,
                    label: 'By person',
                    icon: AppIcons.person,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _byPerson.value ? 1 : 0,
              children: [_myLinks(context), const _ByPerson()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _myLinks(BuildContext context) {
    final store = Stores.shares;

    return AppLoadFade(
      loading: () => store.loadState.isFirstLoad && store.shares.isEmpty,
      skeleton: const AppListSkeleton(
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
        // The groups are the filter: each says how many it holds, and the
        // closed ones stay folded until asked for.
        Widget group(LinkGroup g, String title, {bool collapsed = false}) {
          final links = byGroup[g]!;
          if (links.isEmpty) return const SizedBox.shrink();
          return AppListGroup(
            key: ValueKey(g),
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
                  // The group already says active or paused; only the closed
                  // one mixes revoked and expired.
                  showStatus: g == LinkGroup.closed,
                  onTap: () => context.go(AppRoutes.shareDetailFor(l.id)),
                ),
            ],
          );
        }

        final nothingShown = matches.isEmpty;

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
          emptyMessage: !nothingShown
              ? null
              : recipient != null && recipient.isNotEmpty
              ? 'No links for $recipient.'
              : 'No links match the search.',
          groups: [
            group(LinkGroup.attention, 'Needs attention'),
            group(LinkGroup.active, 'Active'),
            group(LinkGroup.paused, 'Paused'),
            group(LinkGroup.closed, 'Closed', collapsed: true),
          ],
        );
      },
    );
  }
}

/// One link in the list: what it is, one line on where it stands, and a badge
/// when the group does not already say it.
/// Its flags, slug and actions live on its detail page.
class _LinkRow extends StatelessWidget {
  final Link share;
  final bool selected;
  final LinkAttention? attention;
  final VoidCallback onTap;

  /// Off inside a group named for the status, which would only repeat it.
  final bool showStatus;

  const _LinkRow({
    required this.share,
    required this.attention,
    required this.onTap,
    this.selected = false,
    this.showStatus = true,
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
          : showStatus
          ? StatusLabel(share.status)
          : null,
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
