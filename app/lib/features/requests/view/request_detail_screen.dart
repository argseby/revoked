import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deadline.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_entity_card.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/core/widgets/share_sheet.dart';
import 'package:revoked_app/features/requests/store/requests_store.dart';
import 'package:revoked_app/features/requests/view/request_create_sheet.dart';
import 'package:revoked_app/features/requests/view/request_groups.dart';

/// One request, opened from the Requests list: what it asks for, who may
/// answer, what came in, and the actions that end it.
class RequestDetailScreen extends StatefulWidget {
  final String requestId;

  const RequestDetailScreen({super.key, required this.requestId});

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  /// Set while a revoke or delete is in flight, so its button spins and the
  /// other cannot fire on top of it.
  final Local<String?> _busy = Local(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellSlots.title.claim(_title);
      // Opened straight from a link, the list has not loaded anything yet.
      if (Stores.requests.requests.isEmpty) Stores.requests.loadRequests();
      if (Stores.templates.templates.isEmpty) {
        Stores.templates.loadTemplates(Stores.auth.activeWorkspace ?? '');
      }
    });
  }

  @override
  void dispose() {
    ShellSlots.title.release(_title);
    super.dispose();
  }

  DataRequest? get _request {
    for (final r in Stores.requests.requests) {
      if (r.id == widget.requestId) return r;
    }
    return null;
  }

  void _back() => context.go(AppRoutes.inbox);

  Widget _title(BuildContext context) {
    return AppBarTitle(title: _request?.label ?? 'Request', onBack: _back);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final request = _request;
        if (request == null) {
          if (Stores.requests.isLoading) {
            return const Center(child: AppSpinner(large: true));
          }
          return AppEmptyState(
            icon: AppIcons.inboxFill,
            title: 'Request not found',
            subtitle: 'It may have been deleted.',
            action: AppButton(
              icon: AppIcons.arrowLeft,
              label: 'Back to requests',
              style: AppButtonStyle.accent,
              onTap: _back,
            ),
          );
        }

        return AppDetailPage(
          header: _header(context, request),
          sections: [
            _asked(request),
            _access(request),
            _details(request),
            _manage(context, request),
          ],
        );
      },
    );
  }

  AppDetailHeader _header(BuildContext context, DataRequest request) {
    final theme = Theme.of(context);
    final unread = Stores.notifications.unreadResponses(request.id);
    final expiry = isRequestClosed(request)
        ? null
        : expiryNotice(request.expiresAt, DateTime.now());

    return AppDetailHeader(
      badges: [
        AppStatusBadge(request.status),
        if (unread > 0)
          AppBadge(label: '$unread new', accent: theme.colorScheme.primary),
        if (expiry != null)
          AppBadge(
            icon: AppIcons.clock,
            label: expiry,
            accent: theme.colorScheme.warning,
          ),
      ],
      title: request.label,
      subtitle: request.slug,
      subtitleMono: true,
      primaryAction: AppButton(
        icon: AppIcons.cardList,
        label: 'View responses · ${request.responseCount}',
        onTap: () {
          Stores.notifications.markResponsesRead(request.id);
          context.go('${AppRoutes.requestData}?requestId=${request.id}');
        },
      ),
      secondaryActions: [
        AppButton(
          icon: AppIcons.table,
          tooltip: 'View as sheet',
          style: AppButtonStyle.accent,
          onTap: () {
            Stores.notifications.markResponsesRead(request.id);
            context.go('${AppRoutes.requestSheet}?requestId=${request.id}');
          },
        ),
        if (!isRequestClosed(request))
          AppButton(
            icon: AppIcons.share,
            tooltip: 'Share',
            style: AppButtonStyle.accent,
            onTap: () => showShareSheet(
              context: context,
              slug: request.slug,
              title: request.label,
              isRequest: true,
            ),
          ),
        AppButton(
          icon: AppIcons.pencil,
          tooltip: 'Edit',
          style: AppButtonStyle.accent,
          onTap: () => openRequestCreateSheet(
            context: context,
            store: Stores.requests,
            authStore: Stores.auth,
            editRequest: request,
          ),
        ),
      ],
    );
  }

  /// The fields the request asks for, read from its template.
  Widget _asked(DataRequest request) {
    Template? template;
    for (final t in Stores.templates.templates) {
      if (t.id == request.templateId) template = t;
    }

    final rows = <Widget>[];
    var fieldCount = 0;
    if (template != null) {
      final schema = template.schema;
      for (final raw in (schema['records'] as List? ?? const [])) {
        if (raw is! Map) continue;
        fieldCount++;
        rows.add(
          AppDetailRow(
            icon: AppIcons.fileText,
            label: (raw['label'] as String?) ?? (raw['key'] as String? ?? ''),
            value: raw['required'] == true ? 'Required' : 'Optional',
          ),
        );
      }
      for (final raw in (schema['sections'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final n = (raw['records'] as List? ?? const []).length;
        fieldCount += n;
        rows.add(
          AppDetailRow(
            icon: AppIcons.folder,
            label: (raw['name'] as String?) ?? (raw['key'] as String? ?? ''),
            value: '$n ${n == 1 ? 'field' : 'fields'}',
          ),
        );
      }
    }

    if (rows.isEmpty) {
      rows.add(
        AppDetailRow(
          icon: AppIcons.info,
          label: request.templateId.isEmpty
              ? 'No template'
              : Stores.templates.isLoading
              ? 'Loading…'
              : 'Template not available',
        ),
      );
    }
    if (request.allowExtraFields) {
      rows.add(
        const AppDetailRow(
          icon: AppIcons.plus,
          label: 'Extra fields',
          value: 'Allowed',
        ),
      );
    }

    return AppListGroup(
      title: template == null
          ? "What's asked"
          : "What's asked · ${template.name} · $fieldCount",
      previewCount: 6,
      trailing: const SizedBox.shrink(),
      children: rows,
    );
  }

  Widget _access(DataRequest request) {
    return AppListGroup(
      title: 'Access',
      trailing: const SizedBox.shrink(),
      children: [
        AppDetailRow(
          icon: AppIcons.lock,
          label: 'Password',
          value: request.hasPassword ? 'On' : 'Off',
        ),
        AppDetailRow(
          icon: AppIcons.shieldCheck,
          label: 'Who can answer',
          value: _audience(request),
        ),
        if (request.requireHandshake)
          AppDetailRow(
            icon: AppIcons.shieldLock,
            label: 'Accepted identities',
            value: request.identityScope == 'from_root'
                ? 'From this root'
                : 'Any',
          ),
        if (request.identifier.isNotEmpty)
          AppDetailRow(
            icon: AppIcons.tag,
            label: 'Identifier',
            value: request.identifier,
            valueMono: true,
          ),
        AppDetailRow(
          icon: AppIcons.clock,
          label: 'Expires',
          value: AppEntityCard.formatDate(request.expiresAt) ?? 'Never',
        ),
        AppDetailRow(
          icon: AppIcons.collection,
          label: 'Responses',
          value: responsesSummary(request),
        ),
      ],
    );
  }

  /// The same four modes the request form describes when it is set up.
  String _audience(DataRequest request) {
    final hs = request.requireHandshake;
    final id = request.identifier.isNotEmpty;
    if (hs && id) return 'Locked to one recipient';
    if (hs) return 'Verified identities';
    if (id) return 'Identifier holders';
    return 'Open to anyone';
  }

  Widget _details(DataRequest request) {
    return AppListGroup(
      title: 'Details',
      trailing: const SizedBox.shrink(),
      children: [
        if (request.callbackUrl.isNotEmpty)
          AppDetailRow(
            icon: AppIcons.send,
            label: 'Callback',
            value: request.callbackUrl,
            valueMono: true,
          ),
        AppDetailRow(
          icon: AppIcons.plus,
          label: 'Created',
          value: AppEntityCard.formatDate(request.created) ?? '—',
        ),
        AppDetailRow(
          icon: AppIcons.pen,
          label: 'Last changed',
          value: AppEntityCard.formatDate(request.updated) ?? '—',
        ),
      ],
    );
  }

  Widget _manage(BuildContext context, DataRequest request) {
    final busy = _busy.value;
    final locked = busy != null;
    return AppDetailManage(
      actions: [
        if (!isRequestClosed(request))
          AppButton(
            icon: AppIcons.xCircle,
            label: 'Revoke',
            style: AppButtonStyle.destructive,
            size: AppButtonSize.small,
            busy: busy == 'revoke',
            onTap: locked ? null : () => _confirmRevoke(context, request),
          ),
        AppButton(
          icon: AppIcons.trash,
          label: 'Delete',
          style: AppButtonStyle.destructive,
          size: AppButtonSize.small,
          busy: busy == 'delete',
          onTap: locked ? null : () => _confirmDelete(context, request),
        ),
      ],
    );
  }

  Future<void> _confirmRevoke(BuildContext context, DataRequest req) async {
    final store = Stores.requests;
    final confirmed = await showAppDialog(
      context: context,
      title: 'Revoke request?',
      message:
          'The link stops working immediately and collects '
          'no further responses. Data already collected is '
          'kept.',
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
    _busy.value = 'revoke';
    final ok = await store.updateRequest(req.id, {'status': 'revoked'});
    _busy.value = null;
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'Request revoked');
    } else {
      AppToast.error(context, 'Failed to revoke', subtitle: store.errorMessage);
    }
  }

  Future<void> _confirmDelete(BuildContext context, DataRequest req) async {
    final store = Stores.requests;
    final confirmed = await showAppDialog(
      context: context,
      title: 'Delete request?',
      message:
          'This permanently deletes the request and its '
          'collected responses. This cannot be undone.',
      content: ApiPreview(
        spec: RequestsStore.deleteRequestSpec(req.id),
        title: 'API request · delete',
      ),
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    _busy.value = 'delete';
    final ok = await store.deleteRequest(req.id);
    _busy.value = null;
    if (!context.mounted) return;
    if (ok) {
      AppToast.success(context, 'Request deleted');
      _back();
    } else {
      AppToast.error(context, 'Failed to delete', subtitle: store.errorMessage);
    }
  }
}
