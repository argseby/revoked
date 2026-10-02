import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_filter_chips.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_search_field.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/core/widgets/app_tabs.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';
import 'package:revoked_app/features/bookmarks/view/bookmarks_tab.dart';
import 'package:revoked_app/features/shares/view/link_groups.dart';

/// Which links the chips above the list let through.
enum _LinkFilter { all, active, paused, closed }

class SharesScreen extends StatefulWidget {
  final String? filterSlug;

  const SharesScreen({super.key, this.filterSlug});

  @override
  State<SharesScreen> createState() => _SharesScreenState();
}

class _SharesScreenState extends State<SharesScreen> {
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
    if (widget.filterSlug != null) {
      _table.searchQuery = widget.filterSlug!;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ShellSlots.title.claim(_title);
      }
      Stores.shares.loadShares();
      Stores.bookmarks.load();
      Stores.vault.loadRecords();
      Stores.identities.loadIdentities();
    });
  }

  @override
  void dispose() {
    ShellSlots.title.release(_title);
    _table.dispose();
    super.dispose();
  }

  /// The top bar carries the search; its hint carries the count.
  Widget _title(BuildContext context) {
    final count = Stores.shares.shares.length;
    return AppSearchField<Link>(
      controller: _table,
      hint: 'Search $count ${count == 1 ? 'link' : 'links'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppTabs(
      labels: const ['My links', 'Bookmarks'],
      views: [_myLinks(context), const BookmarksTab()],
    );
  }

  Widget _myLinks(BuildContext context) {
    final store = Stores.shares;

    return Observer(
      builder: (_) {
        if (store.isLoading && store.shares.isEmpty) {
          return const Center(child: AppSpinner(large: true));
        }

        if (store.errorMessage != null) {
          return AppLoadError(
            title: 'Failed to load shares',
            message: store.errorMessage!,
            onRetry: store.loadShares,
          );
        }

        if (store.shares.isEmpty) {
          return AppEmptyState(
            icon: AppIcons.share,
            title: 'No shared links',
            subtitle: 'Tap + to securely share data from your vault.',
          );
        }

        final now = DateTime.now();
        final matches = _table.filteredItems;
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
          emptyMessage: nothingShown ? 'No links match your filters.' : null,
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
  final LinkAttention? attention;
  final VoidCallback onTap;

  const _LinkRow({
    required this.share,
    required this.attention,
    required this.onTap,
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
      subtitle: attention?.reason ?? _summary(),
      trailing: attention != null
          ? AppBadge(label: attention.short, accent: theme.colorScheme.warning)
          : AppStatusBadge(share.status),
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
      share.viewCount == 0 ? 'not viewed yet' : 'viewed ${share.viewCount}×',
    );
    return parts.join(' · ');
  }
}
