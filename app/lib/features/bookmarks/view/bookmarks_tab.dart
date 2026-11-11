import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:flutter/material.dart';
import 'package:revoked_app/core/widgets/app_collection_header.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/utils/dates.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/bookmark.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_menu_button.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_edit_sheet.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_filter_menu.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';
import 'package:revoked_app/features/bookmarks/view/bookmark_groups_sheet.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/features/shell/view/link_search_sheet.dart';

/// What others gave this account, of one [kind]: shares to read under
/// Shares › Received, requests to answer under Requests › To answer. Each is
/// filed into groups the way videos go into playlists; a bookmark in several
/// groups shows in each. One in none is listed after the groups — first what
/// someone on this server handed over, then what the person saved.
///
/// The list's toolbar searches names and servers, filters by how a bookmark
/// arrived, and sorts within each group.
class BookmarksTab extends StatefulWidget {
  final BookmarkKind kind;

  const BookmarksTab({super.key, required this.kind});

  @override
  State<BookmarksTab> createState() => _BookmarksTabState();
}

/// How a bookmark arrived, as the Filter offers it.
enum _Source { handed, saved }

class _BookmarksTabState extends State<BookmarksTab> {
  late final TableStore<Bookmark> _table = TableStore<Bookmark>(
    getSourceItems: () => [
      for (final b in Stores.bookmarks.bookmarks)
        if (b.kind == widget.kind) b,
    ],
    fieldGetters: {
      'title': (b) => b.title,
      'origin': (b) => b.origin,
      'created': (b) => b.created ?? '',
    },
    defaultSort: 'created_desc',
    searchFields: const ['title', 'origin'],
  );

  /// The sources the Filter lets through; none ticked lets all through.
  final Local<Set<_Source>> _sources = Local(const {});

  BookmarkKind get kind => widget.kind;

  bool get _asks => kind == BookmarkKind.request;

  @override
  void dispose() {
    _table.dispose();
    super.dispose();
  }

  static _Source _sourceOf(Bookmark b) =>
      b.sender.isNotEmpty ? _Source.handed : _Source.saved;

  AppListToolbar _toolbar(List<Bookmark> all) => AppListToolbar(
    key: ValueKey('bookmarks-toolbar-${kind.name}'),
    query: _table.query,
    onQueryChanged: _table.setQuery,
    searchHint: _asks ? 'Search requests' : 'Search shares',
    onClearFilters: () => _sources.value = const {},
    sections: () => [
      AppChecklistSection(
        title: 'Show',
        selected: {for (final s in _sources.value) s.name},
        onToggle: (id, on) {
          final s = _Source.values.byName(id);
          _sources.value = on
              ? {..._sources.value, s}
              : ({..._sources.value}..remove(s));
        },
        items: [
          AppChecklistItem(
            id: _Source.handed.name,
            label: _asks ? 'Sent to you' : 'Handed to you',
            count: all.where((b) => _sourceOf(b) == _Source.handed).length,
          ),
          AppChecklistItem(
            id: _Source.saved.name,
            label: 'Saved',
            count: all.where((b) => _sourceOf(b) == _Source.saved).length,
          ),
        ],
      ),
    ],
    sort: () => _table.sortBy,
    onSort: _table.setSort,
    defaultSort: _table.defaultSort,
    sortOptions: const [
      AppSortOption('created_desc', 'Newest first'),
      AppSortOption('created_asc', 'Oldest first'),
      AppSortOption('title_asc', 'Name A–Z'),
    ],
  );

  Future<void> _newGroup(BuildContext context) async {
    final store = Stores.bookmarks;
    store.groupName.clear();
    final create = await showAppEditSheet(
      context: context,
      title: 'New group',
      description: 'Groups collect bookmarks under a name.',
      controller: store.groupName,
      hint: 'e.g. Read later',
      doneLabel: 'Create',
    );
    if (!create) return;
    final ok = await store.createGroup(user: Stores.auth.userId);
    if (!ok && store.error != null && context.mounted) {
      AppToast.error(
        context,
        'The group could not be created.',
        subtitle: store.error?.description,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = Stores.bookmarks;
    return AppLoadFade(
      loading: () => store.loadState.isFirstLoad && store.bookmarks.isEmpty,
      skeleton: AppListSkeleton(
        group: 'Saved',
        rows: _asks
            ? const [
                AppSkeletonRow(
                  'Club membership',
                  'From a club',
                  icon: AppIcons.askFor,
                ),
                AppSkeletonRow(
                  'Payroll details',
                  'From an employer',
                  icon: AppIcons.askFor,
                ),
              ]
            : const [
                AppSkeletonRow(
                  'Lease details',
                  'From a landlord',
                  icon: AppIcons.bookmark,
                ),
                AppSkeletonRow(
                  'Pay slip',
                  'From an employer',
                  icon: AppIcons.bookmark,
                ),
              ],
      ),
      builder: (_) {
        // Nothing to list still keeps Search and filter in the top bar.
        Widget bare(Widget child) => AppPageBody(
          children: [
            AppCollectionHeader(
              title: _asks ? 'Requests to answer' : 'Shared with you',
              description: _asks
                  ? 'Information others have asked you to share.'
                  : 'Links from others, kept together for easy access.',
            ),
            child,
          ],
        );
        if (store.error != null && store.bookmarks.isEmpty) {
          return bare(
            AppLoadError(
              title: store.error!.title,
              message: store.error!.description,
              onRetry: store.load,
            ),
          );
        }
        final mine = [
          for (final b in store.bookmarks)
            if (b.kind == kind) b,
        ];
        if (mine.isEmpty && _asks) {
          return bare(
            AppEmptyState(
              icon: AppIcons.askFor,
              title: 'Nothing to answer',
              subtitle:
                  'Requests others send to this account, and ones saved from a '
                  'link, wait here until they are answered from the vault.',
              action: AppButton(
                icon: AppIcons.link,
                label: 'Open a link',
                style: AppButtonStyle.accent,
                onTap: () => openLinkSearchSheet(context),
              ),
              learnMoreLabel: 'About requests',
              learnMoreUrl: '${AppConfig.docsUrl}/guide/requests/',
            ),
          );
        }
        if (mine.isEmpty) {
          return bare(
            AppEmptyState(
              icon: AppIcons.bookmark,
              title: 'Nothing received',
              subtitle:
                  'Shares from others are kept here as shortcuts, not copies. '
                  'Passwords and identity checks still apply, and revoked links '
                  'stay closed.',
              steps: const [
                AppEmptyStep('Received link', 'Opened from a message'),
                AppEmptyStep('Bookmark', 'Saved from the open link'),
                AppEmptyStep('Bookmarks list', 'Optionally sorted into groups'),
              ],
              action: AppButton(
                icon: AppIcons.link,
                label: 'Open a link',
                style: AppButtonStyle.accent,
                onTap: () => openLinkSearchSheet(context),
              ),
              learnMoreLabel: 'About bookmarks',
              learnMoreUrl:
                  '${AppConfig.docsUrl}/guide/sharing/'
                  '#bookmarking-a-share-you-received',
            ),
          );
        }
        // What the search, Filter and Sort let through, in the sorted order;
        // every group and list below keeps that order.
        final sources = _sources.value;
        final visible = [
          for (final b in _table.filteredItems)
            if (sources.isEmpty || sources.contains(_sourceOf(b))) b,
        ];
        final narrowed = sources.isNotEmpty || _table.query.trim().isNotEmpty;
        final ungroupedIds = {for (final b in store.ungrouped) b.id};
        final ungrouped = [
          for (final b in visible)
            if (ungroupedIds.contains(b.id)) b,
        ];
        // Handed over by someone on this server: it names a sender, who can
        // be refused. Saved: the person kept it from a link they opened.
        final handed = [
          for (final b in ungrouped)
            if (b.sender.isNotEmpty) b,
        ];
        final saved = [
          for (final b in ungrouped)
            if (b.sender.isEmpty) b,
        ];
        // A group shows where it has something of this kind, and an empty
        // one in both, so a group just made is not lost. While the list is
        // narrowed only the groups holding a match show.
        final groups = <(BookmarkGroup, List<Bookmark>)>[];
        for (final g in store.groups) {
          final inGroup = {for (final b in store.inGroup(g.id)) b.id};
          final members = [
            for (final b in visible)
              if (inGroup.contains(b.id)) b,
          ];
          final keep = narrowed
              ? members.isNotEmpty
              : store.inGroup(g.id).isEmpty ||
                    store.inGroup(g.id).any((b) => b.kind == kind);
          if (keep) groups.add((g, members));
        }
        final nothingShown =
            narrowed && handed.isEmpty && saved.isEmpty && groups.isEmpty;
        return AppListPage(
          inlineToolbar: true,
          toolbar: _toolbar(mine),
          emptyMessage: nothingShown
              ? 'Nothing matches the search or filters.'
              : null,
          filters: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCollectionHeader(
                title: _asks ? 'Requests to answer' : 'Shared with you',
                description: _asks
                    ? 'Information others have asked you to share.'
                    : 'Links from others, kept together for easy access.',
              ),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  icon: AppIcons.plus,
                  label: 'New group',
                  style: AppButtonStyle.accent,
                  size: AppButtonSize.small,
                  onTap: () => _newGroup(context),
                ),
              ),
            ],
          ),
          groups: [
            if (handed.isNotEmpty)
              AppListGroup(
                title: _asks ? 'Sent to you' : 'Handed to you',
                previewCount: 8,
                noun: _asks ? 'requests' : 'shares',
                children: [
                  for (final bookmark in handed)
                    _BookmarkRow(bookmark: bookmark),
                ],
              ),
            for (final (group, members) in groups)
              _GroupCard(group: group, members: members),
            if (saved.isNotEmpty)
              AppListGroup(
                title: groups.isEmpty ? 'Saved' : 'Saved, not in a group',
                previewCount: 8,
                noun: 'bookmarks',
                children: [
                  for (final bookmark in saved)
                    _BookmarkRow(bookmark: bookmark),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _GroupCard extends StatelessWidget {
  final BookmarkGroup group;

  /// What it lists here: only the tab's kind, as the toolbar lets through
  /// and in its order; the rest shows in the other tab.
  final List<Bookmark> members;

  const _GroupCard({required this.group, required this.members});

  Future<void> _rename(BuildContext context) async {
    final store = Stores.bookmarks;
    store.groupName.text = group.name;
    final saved = await showAppEditSheet(
      context: context,
      title: 'Rename group',
      controller: store.groupName,
      doneLabel: 'Save',
    );
    if (!saved) return;
    final ok = await store.renameGroup(group.id);
    if (!ok && store.error != null && context.mounted) {
      AppToast.error(
        context,
        'The group could not be renamed.',
        subtitle: store.error?.description,
      );
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete "${group.name}"?',
      message: 'Only the group is deleted. Its bookmarks are kept.',
      confirmLabel: 'Delete group',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final store = Stores.bookmarks;
    final ok = await store.deleteGroup(group.id);
    if (!ok && context.mounted) {
      AppToast.error(
        context,
        'The group could not be deleted.',
        subtitle: store.error?.description,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppListGroup(
      title: group.name,
      previewCount: 8,
      noun: 'bookmarks',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText('${members.length}').small.muted,
          AppSpacing.gapXs,
          AppMenuButton(
            icon: AppIcons.threeDotsVertical,
            tooltip: 'Group actions',
            size: AppButtonSize.small,
            chevron: false,
            items: [
              AppMenuItem(
                icon: AppIcons.pencil,
                label: 'Rename',
                onSelected: () => _rename(context),
              ),
              AppMenuItem(
                icon: AppIcons.trash,
                label: 'Delete group',
                destructive: true,
                onSelected: () => _delete(context),
              ),
            ],
          ),
        ],
      ),
      children: members.isEmpty
          ? const [
              AppDetailRow(
                icon: AppIcons.info,
                label: 'No bookmarks in this group',
              ),
            ]
          : [for (final bookmark in members) _BookmarkRow(bookmark: bookmark)],
    );
  }
}

class _BookmarkRow extends StatelessWidget {
  final Bookmark bookmark;

  const _BookmarkRow({required this.bookmark});

  Future<void> _rename(BuildContext context) async {
    final store = Stores.bookmarks;
    store.renameLabel.text = bookmark.label;
    final saved = await showAppEditSheet(
      context: context,
      title: 'Rename bookmark',
      controller: store.renameLabel,
      hint: bookmark.slug,
      doneLabel: 'Save',
    );
    if (!saved) return;
    final ok = await store.rename(bookmark.id);
    if (!ok && context.mounted) {
      AppToast.error(
        context,
        'The bookmark could not be renamed.',
        subtitle: store.error?.description,
      );
    }
  }

  /// Refuses the account that sent this. Offered only on a bookmark that was
  /// handed over, because only those name a sender.
  Future<void> _blockSender(BuildContext context) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Refuse this sender?',
      message:
          'Nothing they send reaches this account again, from any of their '
          'workspaces. What they have already sent stays until it is '
          'removed, and the links themselves keep working. They are not '
          'told.',
      confirmLabel: 'Refuse',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final store = Stores.bookmarks;
    final ok = await store.blockSender(
      user: Stores.auth.userId,
      sender: bookmark.sender,
    );
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'Sender refused');
    } else {
      AppToast.error(
        context,
        'The sender could not be refused.',
        subtitle: store.error?.description,
      );
    }
  }

  Future<void> _remove(BuildContext context) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Remove bookmark?',
      message: 'Only the bookmark is removed. The link itself keeps working.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final store = Stores.bookmarks;
    final ok = await store.remove(bookmark.id);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'Bookmark removed');
    } else {
      AppToast.error(
        context,
        'The bookmark could not be removed.',
        subtitle: store.error?.description,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownServer = Stores.api.isOwnOrigin(bookmark.origin);
    final saved = dayOf(bookmark.created);
    final asks = bookmark.kind == BookmarkKind.request;
    return AppListRow(
      icon: asks ? AppIcons.askFor : AppIcons.bookmark,
      title: bookmark.title,
      // The tab already says what it is; whether it was answered is not
      // known here, so it is not guessed at.
      subtitle: [
        ownServer ? 'This server' : bookmark.origin,
        // One handed over was received, not saved by the person.
        if (saved != null)
          bookmark.sender.isNotEmpty ? 'received $saved' : 'saved $saved',
      ].nonNulls.join(' · '),
      onTap: () => context.push(bookmark.location),
      showChevron: false,
      trailing: AppMenuButton(
        icon: AppIcons.threeDotsVertical,
        tooltip: 'Bookmark actions',
        size: AppButtonSize.small,
        chevron: false,
        items: [
          AppMenuItem(
            icon: AppIcons.copy,
            label: 'Copy link',
            onSelected: () async {
              // Copied links travel to other servers, so they name this one.
              final key = await Stores.bookmarks.keyFor(bookmark);
              if (!context.mounted) return;
              if (bookmark.sealedKey.isNotEmpty && key == null) {
                AppToast.error(
                  context,
                  'The saved link key is not readable on this device.',
                );
                return;
              }
              final base = bookmark.deepLink(
                ownServer ? Stores.api.originAuthority : bookmark.origin,
              );
              final link = key == null
                  ? base
                  : '$base#k=${SealedFormats.linkKeyText(key)}';
              Clipboard.setData(ClipboardData(text: link));
              AppToast.success(context, 'Link copied');
            },
          ),
          AppMenuItem(
            icon: AppIcons.folder,
            label: 'Groups',
            onSelected: () =>
                showBookmarkGroupsSheet(context, bookmarkId: bookmark.id),
          ),
          AppMenuItem(
            icon: AppIcons.pencil,
            label: 'Rename',
            onSelected: () => _rename(context),
          ),
          if (bookmark.sender.isNotEmpty)
            AppMenuItem(
              icon: AppIcons.shieldSlash,
              label: 'Refuse sender',
              destructive: true,
              onSelected: () => _blockSender(context),
            ),
          AppMenuItem(
            icon: AppIcons.trash,
            label: 'Remove',
            destructive: true,
            onSelected: () => _remove(context),
          ),
        ],
      ),
    );
  }
}
