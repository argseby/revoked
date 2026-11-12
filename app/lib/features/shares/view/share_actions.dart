import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/router/held_link_keys.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/access_sheet.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/share_sheet.dart';
import 'package:revoked_app/features/shares/view/share_create_sheet.dart';

/// Link mutations share their confirmation and key handling with the detail view.
class ShareActions {
  final BuildContext context;
  final VoidCallback? onDeleted;
  final ValueChanged<String?>? onBusy;
  const ShareActions(this.context, {this.onDeleted, this.onBusy});

  bool mine(Link share) =>
      Stores.auth.userId.isEmpty || share.user == Stores.auth.userId;

  void visibility(Link share) => openAccessSheet(
    context,
    area: AccessArea.shares,
    id: share.id,
    name: share.label,
    audienceKind: share.audienceKind,
    editing: share.editing,
    save: (kind, editing, groups) => Stores.shares.setShareAudience(
      share.id,
      kind: kind,
      editing: editing,
      groups: groups,
    ),
    saveError: () => Stores.shares.errorMessage,
  );

  List<AppSheetAction> forShare(Link share, {required bool editable}) => [
    if (share.status == 'active') ...[
      AppSheetAction(
        icon: AppIcons.share,
        label: 'Share link',
        onTap: () => showShareSheet(
          context: context,
          slug: share.slug,
          title: share.label,
          isRequest: false,
          linkKey: Stores.shares.linkKeyText(share),
          keyUnreadable:
              share.hasKey && Stores.shares.linkKeyText(share) == null,
        ),
      ),
      AppSheetAction(
        icon: AppIcons.eye,
        label: 'View as recipient',
        onTap: () {
          final key = Stores.shares.linkKeyText(share);
          HeldLinkKeys.hold(
            slug: share.slug,
            key: key == null ? null : SealedFormats.parseLinkKey(key),
          );
          context.push('/s/${share.slug}');
        },
      ),
    ],
    if (mine(share))
      AppSheetAction(
        icon: AppIcons.personWorkspace,
        label: 'Visibility',
        onTap: () => visibility(share),
      ),
    if (editable)
      AppSheetAction(
        icon: AppIcons.pencil,
        label: 'Edit',
        onTap: () => openShareCreateSheet(context: context, editShare: share),
      ),
    if (mine(share))
      AppSheetAction(
        icon: AppIcons.duplicate,
        label: 'Duplicate',
        onTap: () =>
            openShareCreateSheet(context: context, initialShare: share),
      ),
    if (editable) ...[
      if (mine(share) &&
          share.hasKey &&
          (share.status == 'active' || share.status == 'paused'))
        AppSheetAction(
          icon: AppIcons.key,
          label: 'Replace link key',
          onTap: () => replaceKey(share),
        ),
      if (share.status == 'active')
        AppSheetAction(
          icon: AppIcons.pause,
          label: 'Pause',
          onTap: () => setStatus(share, 'paused'),
        ),
      if (share.status == 'paused')
        AppSheetAction(
          icon: AppIcons.play,
          label: 'Activate',
          onTap: () => setStatus(share, 'active'),
        ),
      if (share.status != 'revoked')
        AppSheetAction(
          icon: AppIcons.shieldSlash,
          label: 'Revoke',
          destructive: true,
          onTap: () => revoke(share),
        ),
      AppSheetAction(
        icon: AppIcons.trash,
        label: 'Delete',
        destructive: true,
        onTap: () => delete(share),
      ),
    ],
  ];

  Future<void> replaceKey(Link share) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Replace this link’s key?',
      message:
          'Existing copies of this address will no longer open its encrypted entries. '
          'Plain entries stay accessible. The new complete address can be shared afterward. '
          'Values already copied by a recipient remain with them.',
      confirmLabel: 'Replace key',
      confirmIcon: AppIcons.key,
    );
    if (!confirmed || !context.mounted) return;
    onBusy?.call('key');
    final ok = await Stores.shares.replaceLinkKey(share.id);
    onBusy?.call(null);
    if (!context.mounted) return;
    if (!ok) {
      AppToast.error(
        context,
        'The link key could not be replaced.',
        subtitle: Stores.shares.errorMessage,
      );
      return;
    }
    final updated = Stores.shares.findById(share.id)!;
    await showShareSheet(
      context: context,
      slug: updated.slug,
      title: updated.label,
      isRequest: false,
      linkKey: Stores.shares.linkKeyText(updated),
    );
  }

  Future<void> setStatus(Link share, String status) async {
    onBusy?.call(status);
    try {
      await Stores.shares.updateShare(share.id, {'status': status});
    } finally {
      onBusy?.call(null);
    }
  }

  Future<void> revoke(Link share) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Revoke this link?',
      message:
          'The link can no longer be opened. This cannot be undone, but a '
          'new link can be created from it.',
      content: ApiPreview(
        spec: Stores.shares.updateShareSpec(share.id, const {
          'status': 'revoked',
        }),
        title: 'API request · revoke',
      ),
      confirmLabel: 'Revoke',
      confirmIcon: AppIcons.xCircle,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    onBusy?.call('revoked');
    final ok = await Stores.shares.updateShare(share.id, {'status': 'revoked'});
    onBusy?.call(null);
    if (ok && context.mounted) {
      AppToast.success(context, 'Link revoked');
    }
  }

  Future<void> delete(Link share) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete this link?',
      message: 'The link stops working immediately. This cannot be undone.',
      content: ApiPreview(
        spec: Stores.shares.deleteShareSpec(share.id),
        title: 'API request · delete',
      ),
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    onBusy?.call('delete');
    final ok = await Stores.shares.deleteShare(share.id);
    onBusy?.call(null);
    if (ok && context.mounted) {
      AppToast.success(context, 'Link deleted');
      onDeleted?.call();
    }
  }
}

Future<List<AppSheetAction>> shareContextActions(
  BuildContext context,
  Link share,
) async {
  final actions = ShareActions(context);
  final editable =
      actions.mine(share) || await Stores.shares.canEditShare(share.id);
  if (!context.mounted) return [];
  return actions.forShare(share, editable: editable);
}
