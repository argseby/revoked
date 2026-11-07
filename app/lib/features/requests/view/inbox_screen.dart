import 'package:flutter/material.dart';
import 'package:revoked_app/core/models/bookmark.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/router/return_to.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/request_proposal.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/refresh_on_entry.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';
import 'package:revoked_app/features/requests/view/request_groups.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/features/requests/view/request_create_sheet.dart';
import 'package:revoked_app/core/widgets/app_tabs.dart';
import 'package:revoked_app/features/bookmarks/view/bookmarks_tab.dart';

class InboxScreen extends StatefulWidget {
  /// 1 opens on To answer, the requests others sent this account.
  final int initialTab;

  /// A tool's proposal for a new request; opens the form filled in.
  final RequestProposal? proposal;

  const InboxScreen({super.key, this.initialTab = 0, this.proposal});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> with RefreshOnEntry {
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
      final proposal = widget.proposal;
      if (proposal == null || !mounted) return;
      // The proposal lives in the address only until it has filled in the
      // form, so returning to the tab does not open it again.
      context.go(AppRoutes.requests);
      openRequestCreateSheet(
        context: context,
        store: Stores.requests,
        authStore: Stores.auth,
        proposal: proposal,
      );
    });
  }

  @override
  void refresh() {
    Stores.requests.loadIfDue();
    Stores.bookmarks.loadIfDue();
  }

  @override
  Widget build(BuildContext context) {
    // The same two tabs as Shares: what this account asked for, and what
    // others ask of it. Answers to a request are on that request's page;
    // shares others gave are under Shares › Received.
    return AppTabs(
      initialIndex: widget.initialTab,
      tabs: [
        AppTab(
          label: 'Sent',
          icon: AppIcons.send,
          description: 'Requests sent to others, with their responses.',
          view: _yourRequests(context),
        ),
        const AppTab(
          label: 'To answer',
          icon: AppIcons.askFor,
          description: 'Requests others sent to this account.',
          view: BookmarksTab(kind: BookmarkKind.request),
        ),
      ],
    );
  }

  Widget _yourRequests(BuildContext context) {
    final reqStore = Stores.requests;

    return AppLoadFade(
      loading: () =>
          reqStore.loadState.isFirstLoad && reqStore.requests.isEmpty,
      skeleton: const AppListSkeleton(
        group: 'Open',
        rows: [
          AppSkeletonRow(
            'Tenant details',
            '4 fields · 2 responses',
            icon: AppIcons.inboxFill,
            badge: '2 new',
          ),
          AppSkeletonRow('New starters', '6 fields', icon: AppIcons.inboxFill),
          AppSkeletonRow(
            'Club members',
            '3 fields · 8 responses',
            icon: AppIcons.inboxFill,
          ),
        ],
      ),
      builder: (_) {
        if (reqStore.requests.isEmpty && reqStore.loadState.error != null) {
          return AppLoadError(
            title: 'Requests could not be loaded',
            message: reqStore.loadState.error!,
            onRetry: reqStore.loadRequests,
          );
        }

        if (reqStore.requests.isEmpty) {
          return AppEmptyState(
            icon: AppIcons.inboxFill,
            title: 'No requests',
            subtitle:
                'Requests collect details from others through a form. Answers '
                'stay current and can be withdrawn by the respondent.',
            example: const AppEmptyExample(
              title: 'Tenant details',
              detail: '4 fields',
              badge: '2 responses',
            ),
            steps: const [
              AppEmptyStep(
                'Fields',
                'Defined by a template: a name, an address or a file',
              ),
              AppEmptyStep(
                'Link',
                'Optionally restricted to verified identities',
              ),
              AppEmptyStep('Responses', 'Listed or shown as a spreadsheet'),
            ],
            action: AppButton(
              icon: AppIcons.plus,
              label: 'New request',
              onTap: () => openRequestCreateSheet(
                context: context,
                store: Stores.requests,
                authStore: Stores.auth,
              ),
            ),
            secondaryAction: AppButton(
              icon: AppIcons.fileText,
              label: 'Templates',
              style: AppButtonStyle.accent,
              onTap: () => goReturning(context, AppRoutes.templates),
            ),
            learnMoreLabel: 'How requests work',
            learnMoreUrl: '${AppConfig.docsUrl}/guide/requests/',
          );
        }

        final now = DateTime.now();
        final notifications = Stores.notifications;
        final matches = _table.filteredItems;
        final byGroup = {
          for (final g in RequestGroup.values) g: <DataRequest>[],
        };
        final unread = <String, int>{};
        for (final r in matches) {
          final n = notifications.unreadResponses(r.id);
          unread[r.id] = n;
          byGroup[requestGroup(r, n)]!.add(r);
        }
        // The groups are the filter: each says how many it holds, and the
        // closed ones stay folded until asked for.
        Widget group(RequestGroup g, String title, {bool collapsed = false}) {
          final requests = byGroup[g]!;
          if (requests.isEmpty) return const SizedBox.shrink();
          return AppListGroup(
            key: ValueKey(g),
            title: title,
            noun: 'requests',
            previewCount: g == RequestGroup.fresh ? 0 : 5,
            collapsed: collapsed,
            children: [
              for (final r in requests)
                _RequestRow(
                  request: r,
                  unread: unread[r.id] ?? 0,
                  now: now,
                  // Only the closed group mixes statuses worth telling apart.
                  showStatus: g == RequestGroup.closed,
                  onTap: () => context.go(AppRoutes.requestDetailFor(r.id)),
                ),
            ],
          );
        }

        return AppListPage(
          banners: [
            if (reqStore.loadState.error != null)
              AppRefreshFailed(onRetry: reqStore.loadRequests),
          ],
          emptyMessage: matches.isEmpty
              ? 'No requests match the search.'
              : null,
          groups: [
            group(RequestGroup.fresh, 'New responses'),
            group(RequestGroup.open, 'Open'),
            group(RequestGroup.closed, 'Closed', collapsed: true),
          ],
        );
      },
    );
  }
}

/// One request in the list: its name, what came in, and one badge. Its
/// settings and actions live on its detail page.
class _RequestRow extends StatelessWidget {
  final DataRequest request;
  final int unread;
  final DateTime now;
  final VoidCallback onTap;

  /// Off inside a group named for the status, which would only repeat it.
  final bool showStatus;

  const _RequestRow({
    required this.request,
    required this.unread,
    required this.now,
    required this.onTap,
    this.showStatus = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppListRow(
      icon: AppIcons.inboxFill,
      title: request.label,
      subtitle: requestSummary(request, unread, now),
      trailing: unread > 0
          ? AppBadge(
              label: '$unread new',
              accent: Theme.of(context).colorScheme.primary,
            )
          : showStatus
          ? StatusLabel(request.status)
          : null,
      onTap: onTap,
    );
  }
}
