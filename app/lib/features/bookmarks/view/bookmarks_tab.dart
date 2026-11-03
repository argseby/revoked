import 'package:flutter/material.dart';
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
import 'package:revoked_app/features/bookmarks/view/bookmark_groups_sheet.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/features/shell/view/link_search_sheet.dart';

/// Share links the user saved from links they were sent, filed into groups
/// the way videos go into playlists. A bookmark in several groups shows in
/// each; one in none is listed after the groups.
class BookmarksTab extends StatelessWidget {
  const BookmarksTab({super.key});

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
      skeleton: const AppListSkeleton(
        group: 'Bookmarks',
        rows: [
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
          AppSkeletonRow('Club card', 'From a club', icon: AppIcons.bookmark),
        ],
      ),
      builder: (_) {
        if (store.error != null && store.bookmarks.isEmpty) {
          return AppLoadError(
            title: store.error!.title,
            message: store.error!.description,
            onRetry: store.load,
          );
        }
        if (store.bookmarks.isEmpty) {
          return AppEmptyState(
            icon: AppIcons.bookmark,
            title: 'No bookmarks',
            subtitle:
                'Bookmarks are shortcuts to links from others, not copies. '
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
          );
        }
        final ungrouped = store.ungrouped;
        return AppListPage(
          filters: Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              icon: AppIcons.plus,
              label: 'New group',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: () => _newGroup(context),
            ),
          ),
          groups: [
            for (final group in store.groups) _GroupCard(group: group),
            if (ungrouped.isNotEmpty)
              AppListGroup(
                title: store.groups.isEmpty ? 'Bookmarks' : 'Not in a group',
                previewCount: 8,
                noun: 'bookmarks',
                children: [
                  for (final bookmark in ungrouped)
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

  const _GroupCard({required this.group});

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
    final members = Stores.bookmarks.inGroup(group.id);
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
      subtitle: [
        asks ? 'Awaiting response' : null,
        ownServer ? 'This server' : bookmark.origin,
        if (saved != null) 'saved $saved',
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
            onSelected: () {
              // Copied links travel to other servers, so they name this one.
              final link = bookmark.deepLink(
                ownServer ? Stores.api.originAuthority : bookmark.origin,
              );
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
