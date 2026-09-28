import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_sheet.dart';
import 'package:revoked_app/core/widgets/app_text_field.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';

/// Picks which groups a bookmark sits in, and makes new ones on the spot.
/// With [offerRemove], the sheet also removes the bookmark — the share view
/// opens it from its "Bookmarked" button, where that is the other thing a
/// reader may want.
Future<void> showBookmarkGroupsSheet(
  BuildContext context, {
  required String bookmarkId,
  bool offerRemove = false,
}) {
  Stores.bookmarks.groupName.clear();
  return showAppSheet(
    context: context,
    builder: (sheetCtx) => _BookmarkGroupsSheet(
      bookmarkId: bookmarkId,
      offerRemove: offerRemove,
      parentContext: context,
    ),
  );
}

class _BookmarkGroupsSheet extends StatelessWidget {
  final String bookmarkId;
  final bool offerRemove;
  final BuildContext parentContext;

  const _BookmarkGroupsSheet({
    required this.bookmarkId,
    required this.offerRemove,
    required this.parentContext,
  });

  Future<void> _toggle(String groupId, bool on) async {
    final store = Stores.bookmarks;
    final ok = await store.setInGroup(bookmarkId, groupId, on);
    if (!ok && parentContext.mounted) {
      AppToast.error(
        parentContext,
        'Could not update the group',
        subtitle: store.error?.description,
      );
    }
  }

  Future<void> _create() async {
    final store = Stores.bookmarks;
    final ok = await store.createGroup(
      user: Stores.auth.userId,
      bookmarkId: bookmarkId,
    );
    if (!ok && store.error != null && parentContext.mounted) {
      AppToast.error(
        parentContext,
        'Could not create the group',
        subtitle: store.error?.description,
      );
    }
  }

  Future<void> _remove(BuildContext context) async {
    Navigator.of(context).pop();
    final store = Stores.bookmarks;
    final ok = await store.remove(bookmarkId);
    if (!parentContext.mounted) return;
    if (ok) {
      AppToast.success(parentContext, 'Bookmark removed');
    } else {
      AppToast.error(
        parentContext,
        'Could not remove the bookmark',
        subtitle: store.error?.description,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) => _build(context));
  }

  Widget _build(BuildContext context) {
    final store = Stores.bookmarks;
    final bookmark = store.bookmarks
        .where((b) => b.id == bookmarkId)
        .firstOrNull;
    if (bookmark == null) return const SizedBox.shrink();
    final canCreate =
        store.groupName.text.trim().isNotEmpty && !store.isCreatingGroup;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxs,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Save to group').header,
          AppSpacing.gapXxs,
          Text(bookmark.title).muted.small,
          AppSpacing.gapLg,
          if (store.groups.isEmpty)
            const Text('No groups yet. Name one below.').muted.small
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final group in store.groups)
                    AppCheckRow(
                      label: group.name,
                      value: bookmark.groups.contains(group.id),
                      onChanged: (on) => _toggle(group.id, on),
                    ),
                ],
              ),
            ),
          AppSpacing.gapMd,
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: store.groupName,
                  hint: 'New group, e.g. Read later',
                  onSubmitted: canCreate ? (_) => _create() : null,
                ),
              ),
              AppSpacing.gapSm,
              AppButton(
                icon: AppIcons.plus,
                tooltip: 'Create group',
                style: AppButtonStyle.accent,
                busy: store.isCreatingGroup,
                onTap: canCreate ? _create : null,
              ),
            ],
          ),
          AppSpacing.gapLg,
          AppButton(
            icon: AppIcons.check,
            label: 'Done',
            onTap: () => Navigator.of(context).pop(),
          ),
          if (offerRemove) ...[
            AppSpacing.gapMd,
            const AppDivider(),
            AppSpacing.gapMd,
            AppButton(
              icon: AppIcons.trash,
              label: 'Remove bookmark',
              style: AppButtonStyle.destructive,
              onTap: () => _remove(context),
            ),
          ],
        ],
      ),
    );
  }
}
