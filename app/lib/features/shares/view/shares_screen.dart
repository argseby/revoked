import 'package:flutter/material.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/bookmark.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/audience_tag.dart';
import 'package:revoked_app/core/widgets/app_filter_menu.dart';
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

class SharesScreen extends StatefulWidget {
  /// Narrows the list to one recipient's links, opened from a recipient row:
  /// their name, which is what a link's label holds. It ticks them in the
  /// Filter.
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

  /// The statuses the Filter lets through; none ticked lets all through.
  final Local<Set<LinkGroup>> _statuses = Local(const {});

  /// The recipients the Filter lets through, by [_personKey]. The `recipient`
  /// route parameter ticks its person.
  late final Local<Set<String>> _people = Local(_peopleFrom(widget.recipient));

  /// Who sees a link, as the Filter's "Visible to" ticks it (`private`,
  /// `workspace`, `group:<id>`); none ticked lets all through.
  final Local<Set<String>> _audiences = Local(const {});

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
      searchFields: const ['label', 'slug'],
    );
  }

  @override
  void didUpdateWidget(SharesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The split keeps this screen while the route changes, so a new
    // `recipient` arrives here rather than through initState.
    if (oldWidget.recipient != widget.recipient) {
      _people.value = _peopleFrom(widget.recipient);
    }
  }

  static Set<String> _peopleFrom(String? recipient) {
    final key = _personKey(recipient ?? '');
    return key.isEmpty ? const {} : {key};
  }

  /// How [groupByRecipient] tells recipients apart.
  static String _personKey(String label) => label.trim().toLowerCase();

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
          description: 'Share links made here, by status and by person.',
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

  /// The links, grouped by status, under the list's header: the search,
  /// and Filter and sort by status and by the person a link went to. The
  /// grouping stays.
  Widget _sent(BuildContext context) => _myLinks(context);

  AppListToolbar _toolbar() => AppListToolbar(
    key: const ValueKey('shares-toolbar'),
    query: _table.query,
    onQueryChanged: _table.setQuery,
    searchHint: 'Search links',
    sections: _filterSections,
    onClearFilters: _clearFilters,
    sort: () => _table.sortBy,
    onSort: _table.setSort,
    defaultSort: _table.defaultSort,
    sortOptions: const [
      AppSortOption('created_desc', 'Newest first'),
      AppSortOption('created_asc', 'Oldest first'),
      AppSortOption('label_asc', 'Label A–Z'),
      AppSortOption('status_asc', 'Status'),
    ],
  );

  void _clearFilters() {
    _statuses.value = const {};
    _people.value = const {};
    _audiences.value = const {};
  }

  static const _groupTitles = {
    LinkGroup.attention: 'Needs attention',
    LinkGroup.active: 'Active',
    LinkGroup.paused: 'Paused',
    LinkGroup.closed: 'Closed',
  };

  List<AppChecklistSection> _filterSections() {
    final links = Stores.shares.shares.toList();
    final now = DateTime.now();
    final counts = {for (final g in LinkGroup.values) g: 0};
    for (final l in links) {
      counts[linkGroup(l, now)] = counts[linkGroup(l, now)]! + 1;
    }
    final people = groupByRecipient(links)
      ..sort(
        (a, b) =>
            _personKey(a.first.label).compareTo(_personKey(b.first.label)),
      );
    return [
      AppChecklistSection(
        title: 'Status',
        selected: {for (final g in _statuses.value) g.name},
        onToggle: (id, on) {
          final g = LinkGroup.values.byName(id);
          _statuses.value = on
              ? {..._statuses.value, g}
              : ({..._statuses.value}..remove(g));
        },
        items: [
          for (final g in LinkGroup.values)
            AppChecklistItem(
              id: g.name,
              label: _groupTitles[g]!,
              count: counts[g],
            ),
        ],
      ),
      if (people.isNotEmpty)
        AppChecklistSection(
          title: 'Person',
          selected: _people.value,
          onToggle: (id, on) => _people.value = on
              ? {..._people.value, id}
              : ({..._people.value}..remove(id)),
          items: [
            for (final p in people)
              AppChecklistItem(
                id: _personKey(p.first.label),
                label: p.first.label.trim().isEmpty
                    ? 'Unnamed link'
                    : p.first.label.trim(),
                count: p.length,
              ),
          ],
        ),
      ?audienceFilterSection(
        items: [
          for (final l in [...links, ...Stores.shares.sharedShares])
            [_audienceOf(l)],
        ],
        selected: _audiences.value,
        onToggle: (id, on) => _audiences.value = on
            ? {..._audiences.value, id}
            : ({..._audiences.value}..remove(id)),
      ),
    ];
  }

  static Audience _audienceOf(Link l) =>
      Audience(l.audienceKind, l.audienceGroups);

  /// The one recipient ticked, as they named the link; null unless exactly
  /// one is.
  String? _singlePerson() {
    final people = _people.value;
    if (people.length != 1) return null;
    final key = people.single;
    for (final l in Stores.shares.shares) {
      if (_personKey(l.label) == key) return l.label.trim();
    }
    // Not among the links (yet): the route's spelling, if it named them.
    final fromRoute = widget.recipient?.trim();
    if (fromRoute != null && _personKey(fromRoute) == key) return fromRoute;
    return key;
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
        // Nothing to list still keeps Search and filter in the top bar.
        Widget bare(Widget child) =>
            AppListEmpty(toolbar: _toolbar(), child: child);
        if (store.shares.isEmpty &&
            store.sharedShares.isEmpty &&
            store.loadState.error != null) {
          return bare(
            AppLoadError(
              title: 'Links could not be loaded',
              message: store.loadState.error!,
              onRetry: store.loadShares,
            ),
          );
        }

        if (store.shares.isEmpty && store.sharedShares.isEmpty) {
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
          return bare(
            AppEmptyState(
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
            ),
          );
        }

        final now = DateTime.now();
        final statuses = _statuses.value;
        final people = _people.value;
        final audiences = _audiences.value;
        final recipient = _singlePerson();
        final matches = _table.filteredItems
            .where(
              (l) =>
                  (statuses.isEmpty || statuses.contains(linkGroup(l, now))) &&
                  (people.isEmpty || people.contains(_personKey(l.label))) &&
                  audienceMatches(audiences, [_audienceOf(l)]),
            )
            .toList();
        final sharedShown = store.sharedShares
            .where((l) => audienceMatches(audiences, [_audienceOf(l)]))
            .toList();
        // What each status holds under the search and the other filters, so
        // a chip says what picking it would show.
        final statusCounts = {for (final g in LinkGroup.values) g: 0};
        for (final l in _table.filteredItems) {
          if ((people.isEmpty || people.contains(_personKey(l.label))) &&
              audienceMatches(audiences, [_audienceOf(l)])) {
            final g = linkGroup(l, now);
            statusCounts[g] = statusCounts[g]! + 1;
          }
        }
        final byGroup = {for (final g in LinkGroup.values) g: <Link>[]};
        for (final l in matches) {
          byGroup[linkGroup(l, now)]!.add(l);
        }
        // Each group says how many it holds, and the closed ones stay folded
        // until asked for, by the group or by ticking Closed in the Filter.
        Widget group(LinkGroup g, String title, {bool collapsed = false}) {
          final links = byGroup[g]!;
          if (links.isEmpty) return const SizedBox.shrink();
          return AppListGroup(
            key: ValueKey((g, collapsed)),
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

        final nothingShown =
            matches.isEmpty &&
            (sharedShown.isEmpty || statuses.isNotEmpty || people.isNotEmpty);

        return _sharingPage(
          context,
          now: now,
          toolbar: _toolbar(),
          filters: AppStatusChips<LinkGroup>(
            selected: statuses,
            onChanged: (v) => _statuses.value = v,
            options: [
              for (final g in LinkGroup.values)
                AppFilterOption(
                  value: g,
                  label: _groupTitles[g]!,
                  count: statusCounts[g]!,
                ),
            ],
          ).orNull,
          banners: [
            if (store.loadState.error != null)
              AppRefreshFailed(onRetry: store.loadShares),
            if (recipient != null)
              AppListBanner(
                icon: AppIcons.person,
                message: 'Links for $recipient',
                action: AppButton(
                  icon: AppIcons.x,
                  label: 'Show all',
                  style: AppButtonStyle.accent,
                  size: AppButtonSize.small,
                  onTap: () {
                    _people.value = const {};
                    // Drop the parameter too, so the address says the same.
                    if (widget.recipient != null) {
                      context.go(AppRoutes.shared);
                    }
                  },
                ),
              ),
          ],
          emptyMessage: !nothingShown
              ? null
              : recipient != null && statuses.isEmpty
              ? 'No links for $recipient.'
              : 'No links match the search or filters.',
          groups: [
            group(LinkGroup.attention, 'Needs attention'),
            group(LinkGroup.active, 'Active'),
            group(LinkGroup.paused, 'Paused'),
            group(
              LinkGroup.closed,
              'Closed',
              collapsed: !statuses.contains(LinkGroup.closed),
            ),
            // Shares other members opened to this person, apart from their
            // own and outside the filters, which are about their own links.
            if (sharedShown.isNotEmpty && statuses.isEmpty && people.isEmpty)
              AppListGroup(
                title: 'Shared by members',
                noun: 'links',
                previewCount: 5,
                children: [
                  for (final l in sharedShown)
                    _LinkRow(
                      share: l,
                      selected: l.id == widget.selectedId,
                      attention: null,
                      showStatus: true,
                      onTap: () => context.go(AppRoutes.shareDetailFor(l.id)),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _sharingPage(
    BuildContext context, {
    required DateTime now,
    required AppListToolbar toolbar,
    required Widget? filters,
    required List<Widget> banners,
    required String? emptyMessage,
    required List<Widget> groups,
  }) {
    final shares = Stores.shares.shares;
    final compact = widget.selectedId != null;
    final totals = {for (final g in LinkGroup.values) g: 0};
    for (final link in shares) {
      final group = linkGroup(link, now);
      totals[group] = totals[group]! + 1;
    }
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(compact ? 'Your links' : 'Your sharing').title,
        AppSpacing.gapSm,
        AppText(
          compact
              ? 'Choose a link to manage its access.'
              : 'Share from your Vault. Stay in control of access.',
        ).small.muted,
      ],
    );
    final create = AppButton(
      icon: AppIcons.plus,
      label: 'Share items',
      onTap: () => openShareCreateSheet(context: context),
    );
    return AppPageBody(
      bottomPadding: AppSpacing.gigantic,
      children: [
        AppSpacing.gapLg,
        LayoutBuilder(
          builder: (context, box) =>
              box.maxWidth < 600 ||
                  MediaQuery.textScalerOf(context).scale(16) > 24
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, AppSpacing.gapLg, create],
                )
              : Row(
                  children: [
                    Expanded(child: heading),
                    AppSpacing.gapLg,
                    create,
                  ],
                ),
        ),
        AppSpacing.gapXxl,
        if (!compact && shares.isNotEmpty) ...[
          LayoutBuilder(
            builder: (context, box) {
              final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final columns = (box.maxWidth / (180 * scale)).floor().clamp(
                1,
                3,
              );
              final width =
                  (box.maxWidth - AppSpacing.md * (columns - 1)) / columns;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final g in [
                    LinkGroup.active,
                    LinkGroup.paused,
                    LinkGroup.closed,
                  ])
                    SizedBox(
                      width: width,
                      child: _SharingStatusTile(
                        group: g,
                        compact: columns == 1,
                        count:
                            totals[g]! +
                            (g == LinkGroup.active
                                ? totals[LinkGroup.attention]!
                                : 0),
                        selected: g == LinkGroup.active
                            ? _statuses.value.length == 2 &&
                                  _statuses.value.containsAll({
                                    LinkGroup.active,
                                    LinkGroup.attention,
                                  })
                            : _statuses.value.length == 1 &&
                                  _statuses.value.contains(g),
                        onTap: () {
                          final next = g == LinkGroup.active
                              ? {LinkGroup.active, LinkGroup.attention}
                              : {g};
                          _statuses.value =
                              _statuses.value.length == next.length &&
                                  _statuses.value.containsAll(next)
                              ? const {}
                              : next;
                        },
                      ),
                    ),
                ],
              );
            },
          ),
          AppSpacing.gapXxl,
        ],

        if (filters != null) ...[filters, AppSpacing.gapLg],
        toolbar.pill(),
        if (toolbar.chips(context) case final chips?) ...[
          AppSpacing.gapSm,
          chips,
        ],
        AppSpacing.gapXl,
        for (final banner in banners) ...[banner, AppSpacing.gapLg],
        if (emptyMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.huge),
            child: AppText(emptyMessage).muted,
          )
        else
          ...groups,
      ],
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
      title: share.label.trim().isEmpty ? 'Unnamed link' : share.label,
      selected: selected,
      accent: attention != null ? theme.colorScheme.warning : null,
      subtitleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_contentsSummary().isNotEmpty)
            AppText(
              _contentsSummary(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ).small,
          AppText(
            attention?.reason ?? _summary(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ).small.muted,
        ],
      ),
      audience: AudienceTag(Audience(share.audienceKind, share.audienceGroups)),
      trailing: attention != null
          ? AppBadge(label: attention.short, accent: theme.colorScheme.warning)
          : showStatus
          ? StatusLabel(share.status)
          : null,
      onTap: onTap,
    );
  }

  String _contentsSummary() {
    final own = Stores.auth.userId.isEmpty || share.user == Stores.auth.userId;
    if (!own) return 'Shared by a workspace member';
    final vault = Stores.vault;
    final byId = {
      for (final r in [...vault.sharedRecords, ...vault.records]) r.id: r,
    };
    final sections = {
      for (final s in [...vault.sharedSections, ...vault.sections]) s.id: s,
    };
    final ids = <String>{...share.records};
    for (final id in share.sections) {
      ids.addAll(sections[id]?.records ?? const <String>[]);
    }
    final names = [
      for (final id in ids)
        if (byId[id] case final r?) r.label.isEmpty ? r.key : r.label,
    ];
    if (names.isEmpty) return '';
    final preview = names.take(2).toList();
    final remaining = ids.length - preview.length;
    return '${preview.join(', ')}${remaining > 0 ? ' +$remaining more' : ''}';
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

/// Access states are destinations: live links, reversible pauses, and history.
class _SharingStatusTile extends StatelessWidget {
  final LinkGroup group;
  final int count;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _SharingStatusTile({
    required this.group,
    required this.count,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (title, description, icon, color) = switch (group) {
      LinkGroup.active => (
        'Active links',
        'Manage current sharing',
        AppIcons.link,
        scheme.success,
      ),
      LinkGroup.paused => (
        'Paused links',
        'Access is on hold',
        AppIcons.pauseCircle,
        scheme.warning,
      ),
      _ => (
        'Closed links',
        'Revoked or expired',
        AppIcons.linkSlash,
        scheme.onSurfaceVariant,
      ),
    };
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.allMd,
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: compact
                ? Row(
                    children: [
                      Icon(icon, size: 20, color: color),
                      AppSpacing.gapMd,
                      Expanded(child: AppText(title).small.bold),
                      AppSpacing.gapMd,
                      AppText('$count').header,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 20, color: color),
                          const Spacer(),
                          AppText('$count').header,
                        ],
                      ),
                      AppSpacing.gapMd,
                      AppText(title).bold,
                      AppSpacing.gapXxs,
                      AppText(description).small.muted,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
