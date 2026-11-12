import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/access_sheet.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/share_sheet.dart';
import 'package:revoked_app/features/requests/store/requests_store.dart';
import 'package:revoked_app/features/requests/view/request_create_sheet.dart';
import 'package:revoked_app/features/requests/view/request_groups.dart';

class RequestActions {
  final BuildContext context;
  final VoidCallback? onDeleted;
  final ValueChanged<String?>? onBusy;
  const RequestActions(this.context, {this.onDeleted, this.onBusy});

  bool mine(DataRequest request) =>
      Stores.auth.userId.isEmpty || request.user == Stores.auth.userId;

  void visibility(DataRequest request) => openAccessSheet(
    context,
    area: AccessArea.requests,
    id: request.id,
    name: request.label,
    audienceKind: request.audienceKind,
    editing: request.editing,
    save: (kind, editing, groups) => Stores.requests.setRequestAudience(
      request.id,
      kind: kind,
      editing: editing,
      groups: groups,
    ),
    saveError: () => Stores.requests.errorMessage,
  );

  List<AppSheetAction> forRequest(
    DataRequest request, {
    required bool editable,
  }) => [
    AppSheetAction(
      icon: AppIcons.cardList,
      label: 'View responses',
      onTap: () {
        Stores.notifications.markResponsesRead(request.id);
        context.go(AppRoutes.requestDataFor(request.id));
      },
    ),
    AppSheetAction(
      icon: AppIcons.table,
      label: 'View as sheet',
      onTap: () {
        Stores.notifications.markResponsesRead(request.id);
        context.go(AppRoutes.requestSheetFor(request.id));
      },
    ),
    if (!isRequestClosed(request))
      AppSheetAction(
        icon: AppIcons.share,
        label: 'Share',
        onTap: () => showShareSheet(
          context: context,
          slug: request.slug,
          title: request.label,
          isRequest: true,
        ),
      ),
    if (mine(request))
      AppSheetAction(
        icon: AppIcons.personWorkspace,
        label: 'Visibility',
        onTap: () => visibility(request),
      ),
    if (editable) ...[
      AppSheetAction(
        icon: AppIcons.pencil,
        label: 'Edit',
        onTap: () => openRequestCreateSheet(
          context: context,
          store: Stores.requests,
          authStore: Stores.auth,
          editRequest: request,
        ),
      ),
      if (!isRequestClosed(request))
        AppSheetAction(
          icon: AppIcons.xCircle,
          label: 'Revoke',
          destructive: true,
          onTap: () => revoke(request),
        ),
      AppSheetAction(
        icon: AppIcons.trash,
        label: 'Delete',
        destructive: true,
        onTap: () => delete(request),
      ),
    ],
  ];

  Future<void> revoke(DataRequest req) async {
    final store = Stores.requests;
    final confirmed = await showAppDialog(
      context: context,
      title: 'Revoke this request?',
      message:
          'The link stops working immediately and accepts no new '
          'responses. Existing responses are kept.',
      content: ApiPreview(
        spec: RequestsStore.updateRequestSpec(req.id, const {
          'status': 'revoked',
        }),
        title: 'API request · revoke',
      ),
      confirmLabel: 'Revoke',
      confirmIcon: AppIcons.xCircle,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    onBusy?.call('revoke');
    final ok = await store.updateRequest(req.id, {'status': 'revoked'});
    onBusy?.call(null);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'Request revoked');
    } else {
      AppToast.error(
        context,
        'The request could not be revoked.',
        subtitle: store.errorMessage,
      );
    }
  }

  Future<void> delete(DataRequest req) async {
    final store = Stores.requests;
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete this request?',
      message:
          'The request and its responses are deleted permanently. This '
          'cannot be undone.',
      content: ApiPreview(
        spec: RequestsStore.deleteRequestSpec(req.id),
        title: 'API request · delete',
      ),
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    onBusy?.call('delete');
    final ok = await store.deleteRequest(req.id);
    onBusy?.call(null);
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'Request deleted');
      onDeleted?.call();
    } else {
      AppToast.error(
        context,
        'The request could not be deleted.',
        subtitle: store.errorMessage,
      );
    }
  }
}

Future<List<AppSheetAction>> requestContextActions(
  BuildContext context,
  DataRequest request,
) async {
  final actions = RequestActions(context);
  final editable =
      actions.mine(request) || await Stores.requests.canEditRequest(request.id);
  if (!context.mounted) return [];
  return actions.forRequest(request, editable: editable);
}
