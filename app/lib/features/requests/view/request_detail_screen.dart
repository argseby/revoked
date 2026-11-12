import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/features/requests/view/request_actions.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/utils/dates.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/template.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deadline.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/audience_tag.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/access_sheet.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/core/widgets/share_sheet.dart';
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

  DataRequest? get _request => Stores.requests.findById(widget.requestId);

  /// Whether this person owns the request. A colleague's request, opened to
  /// them (VISIBILITY.md), can be changed here only when it is also open to
  /// them for editing ([_editable]); who sees it stays its owner's.
  bool _mine(DataRequest request) =>
      Stores.auth.userId.isEmpty || request.user == Stores.auth.userId;

  /// Whether this person may change a colleague's request: asked of the
  /// server once the request is known, null until then.
  final Local<bool?> _canEdit = Local(null);
  bool _askedCanEdit = false;

  void _askCanEdit(DataRequest request) {
    if (_askedCanEdit || _mine(request)) return;
    _askedCanEdit = true;
    Stores.requests.canEditRequest(request.id).then((v) {
      if (mounted) _canEdit.value = v;
    });
  }

  /// The owner, or a member the request is open to for editing.
  bool _editable(DataRequest request) =>
      _mine(request) || _canEdit.value == true;

  void _openAccess(BuildContext context, DataRequest request) =>
      openAccessSheet(
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

  void _back() => context.go(AppRoutes.requests);

  Widget _title(BuildContext context) {
    return AppBarTitle(title: 'Requests', onBack: _back);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final request = _request;
        if (request == null) {
          if (Stores.requests.isLoading) {
            return const AppDetailSkeleton(
              badges: ['open'],
              primary: 'View responses',
              sections: [
                AppSkeletonGroup('Fields', rows: 3),
                AppSkeletonGroup('Access', rows: 3),
              ],
              aside: [AppSkeletonGroup('Details', rows: 3)],
            );
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

        _askCanEdit(request);
        return AppDetailPage(
          header: _header(context, request),
          sections: [_asked(request), _access(request)],
          aside: [
            _details(request),
            if (_editable(request)) _manage(context, request),
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

    final mine = _mine(request);
    return AppDetailHeader(
      badges: [
        StatusLabel(request.status),
        if (!mine)
          const AppBadge(
            icon: AppIcons.personWorkspace,
            label: 'Shared by a member',
          ),
        AudienceTag(Audience(request.audienceKind, request.audienceGroups)),
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
          context.go(AppRoutes.requestDataFor(request.id));
        },
      ),
      secondaryActions: [
        AppButton(
          icon: AppIcons.table,
          tooltip: 'View as sheet',
          style: AppButtonStyle.accent,
          onTap: () {
            Stores.notifications.markResponsesRead(request.id);
            context.go(AppRoutes.requestSheetFor(request.id));
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
        if (mine) ...[
          AppButton(
            icon: AppIcons.personWorkspace,
            tooltip: 'Visibility',
            style: AppButtonStyle.accent,
            onTap: () => _openAccess(context, request),
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
        ] else if (_editable(request))
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
          ? 'Fields'
          : 'Fields · ${template.name} · $fieldCount',
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
          label: 'Respondents',
          value: _audience(request),
        ),
        if (request.requireHandshake)
          AppDetailRow(
            icon: AppIcons.shieldLock,
            label: 'Accepted identities',
            value: request.identityScope == 'from_root'
                ? 'This server only'
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
          value: dayTimeOf(request.expiresAt) ?? 'Never',
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
    if (id) return 'People with the identifier';
    return 'Anyone signed in';
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
          value: dayTimeOf(request.created) ?? '—',
        ),
        AppDetailRow(
          icon: AppIcons.pen,
          label: 'Last changed',
          value: dayTimeOf(request.updated) ?? '—',
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
            style: AppButtonStyle.danger,
            busy: busy == 'revoke',
            onTap: locked ? null : () => _confirmRevoke(context, request),
          ),
        AppButton(
          icon: AppIcons.trash,
          label: 'Delete',
          style: AppButtonStyle.danger,
          busy: busy == 'delete',
          onTap: locked ? null : () => _confirmDelete(context, request),
        ),
      ],
    );
  }

  RequestActions get _actions => RequestActions(
    context,
    onBusy: (busy) => _busy.value = busy,
    onDeleted: _back,
  );

  Future<void> _confirmRevoke(BuildContext context, DataRequest req) =>
      _actions.revoke(req);
  Future<void> _confirmDelete(BuildContext context, DataRequest req) =>
      _actions.delete(req);
}
