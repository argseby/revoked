import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/widgets/data_table/filter_bar.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/status_colors.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/api_preview.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_dialog.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_entity_card.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/app_screen_header.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_toast.dart';
import 'package:revoked_app/features/requests/store/requests_store.dart';
import 'package:revoked_app/features/requests/view/request_create_sheet.dart';
import 'package:revoked_app/core/widgets/share_sheet.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late final TableStore<DataRequest> _table;

  @override
  void initState() {
    super.initState();
    _table = TableStore<DataRequest>(
      getSourceItems: () => Stores.requests.requests.toList(),
      fieldGetters: {
        'label': (r) => r.label,
        'slug': (r) => r.slug,
        'status': (r) => r.status,
        'created': (r) => r.created ?? '',
      },
      defaultSort: 'created_desc',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ShellSlots.setFilter(_filterButton);
      Stores.requests.loadRequests();
    });
  }

  @override
  void dispose() {
    ShellSlots.clearFilter(_filterButton);
    super.dispose();
  }

  Widget _filterButton(BuildContext context) {
    return FilterButton<DataRequest>(
      controller: _table,
      columns: const [
        DataTableColumn(value: 'label', label: 'Label'),
        DataTableColumn(value: 'slug', label: 'Slug'),
        DataTableColumn(value: 'status', label: 'Status'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final reqStore = Stores.requests;

    final outerPad = AppSpacing.screenH(context);
    final scrollbarMargin = AppSpacing.scrollbarMargin(context);
    final innerPad = outerPad - scrollbarMargin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: outerPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.md),
              Observer(
                builder: (_) {
                  final count = reqStore.requests.length;
                  return AppScreenHeader(
                    title: 'Request',
                    badgeLabel: '$count ${count == 1 ? 'request' : 'requests'}',
                  );
                },
              ),
            ],
          ),
        ),

        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: scrollbarMargin),
            child: Observer(
              builder: (_) {
                if (reqStore.isLoading && reqStore.requests.isEmpty) {
                  return const Center(child: AppSpinner(large: true));
                }

                if (reqStore.errorMessage != null) {
                  return AppLoadError(
                    title: 'Failed to load inbox',
                    message: reqStore.errorMessage!,
                    onRetry: reqStore.loadRequests,
                  );
                }

                final filtered = _table.filteredItems;

                if (filtered.isEmpty) {
                  return AppEmptyState(
                    icon: AppIcons.inboxFill,
                    title: reqStore.requests.isEmpty
                        ? 'No requests yet'
                        : 'Nothing here',
                    subtitle: reqStore.requests.isEmpty
                        ? 'Tap + to create a data request and start collecting peer data.'
                        : 'Try selecting a different filter.',
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.only(
                    left: innerPad,
                    right: innerPad,
                    bottom: AppSpacing.huge,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final req = filtered[index];
                    return _InboxCard(
                      request: req,
                      onEdit: () => openRequestCreateSheet(
                        context: context,
                        store: reqStore,
                        authStore: Stores.auth,
                        editRequest: req,
                      ),
                      onRevoke: () async {
                        final confirmed = await showAppDialog(
                          context: context,
                          title: 'Revoke request?',
                          message:
                              'The link stops working immediately and collects '
                              'no further responses. Data already collected is '
                              'kept.',
                          content: ApiPreview(
                            spec: RequestsStore.updateRequestSpec(
                              req.id,
                              const {'status': 'revoked'},
                            ),
                            title: 'API request · revoke',
                          ),
                          confirmLabel: 'Revoke',
                          destructive: true,
                        );
                        if (!confirmed || !context.mounted) return;
                        final ok = await reqStore.updateRequest(req.id, {
                          'status': 'revoked',
                        });
                        if (!context.mounted) return;
                        if (ok) {
                          AppToast.success(context, 'Request revoked');
                        } else {
                          AppToast.error(
                            context,
                            'Failed to revoke',
                            subtitle: reqStore.errorMessage,
                          );
                        }
                      },
                      onDelete: () async {
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
                        if (confirmed != true) return;
                        final ok = await reqStore.deleteRequest(req.id);
                        if (!context.mounted) return;
                        if (ok) {
                          AppToast.success(context, 'Request deleted');
                        } else {
                          AppToast.error(
                            context,
                            'Failed to delete',
                            subtitle: reqStore.errorMessage,
                          );
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _InboxCard extends StatefulWidget {
  final DataRequest request;
  final VoidCallback onEdit;
  final VoidCallback onRevoke;
  final VoidCallback onDelete;

  const _InboxCard({
    required this.request,
    required this.onEdit,
    required this.onRevoke,
    required this.onDelete,
  });

  @override
  State<_InboxCard> createState() => _InboxCardState();
}

class _InboxCardState extends State<_InboxCard> {
  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final isClosed = req.status == 'revoked' || req.status == 'expired';

    return AppEntityCard(
      icon: AppIcons.inboxFill,
      title: req.label,
      subtitle: req.slug,
      subtitleMono: true,
      date: AppEntityCard.formatDate(req.created),
      tags: _tags(context, req),
      actions: _requestActions(context, req, isClosed),
    );
  }

  List<Widget> _tags(BuildContext context, DataRequest req) {
    final theme = Theme.of(context);
    final out = <Widget>[
      AppBadge(
        label: StatusColors.displayLabel(req.status),
        accent: StatusColors.foreground(theme, req.status),
      ),
      AppBadge(
        icon: AppIcons.collection,
        label: req.maxResponses > 0
            ? '${req.responseCount}/${req.maxResponses} responses'
            : '${req.responseCount} responses',
      ),
    ];
    if (req.hasPassword) {
      out.add(const AppBadge(icon: AppIcons.lock, label: 'Password'));
    }
    if (req.requireHandshake) {
      out.add(const AppBadge(icon: AppIcons.shieldCheck, label: 'Handshake'));
    }
    if (req.identifier.isNotEmpty) {
      out.add(const AppBadge(icon: AppIcons.tag, label: 'Identifier'));
    }
    if (req.expiresAt != null) {
      out.add(
        AppBadge(icon: AppIcons.clock, label: _formatExpiry(req.expiresAt!)),
      );
    }
    return out;
  }

  List<AppSheetAction> _requestActions(
    BuildContext context,
    DataRequest req,
    bool isClosed,
  ) {
    return [
      AppSheetAction(
        icon: AppIcons.cardList,
        label: 'View responses',
        primary: true,
        onTap: () => context.go('${AppRoutes.requestData}?requestId=${req.id}'),
      ),
      AppSheetAction(
        icon: AppIcons.table,
        label: 'View as sheet',
        onTap: () =>
            context.go('${AppRoutes.requestSheet}?requestId=${req.id}'),
      ),
      AppSheetAction(
        icon: AppIcons.share,
        label: 'Share',
        onTap: () => showShareSheet(
          context: context,
          slug: req.slug,
          title: req.label,
          isRequest: true,
        ),
      ),
      AppSheetAction(
        icon: AppIcons.pencil,
        label: 'Edit',
        onTap: widget.onEdit,
      ),
      if (!isClosed)
        AppSheetAction(
          icon: AppIcons.xCircle,
          label: 'Revoke',
          destructive: true,
          onTap: widget.onRevoke,
        ),
      AppSheetAction(
        icon: AppIcons.trash,
        label: 'Delete',
        destructive: true,
        onTap: widget.onDelete,
      ),
    ];
  }

  String _formatExpiry(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return 'Exp ${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'Expires';
    }
  }
}

// Per-request submission data now lives on the aggregated Data screen
// (opened via the "View data" button), not as an inline inbox preview.
