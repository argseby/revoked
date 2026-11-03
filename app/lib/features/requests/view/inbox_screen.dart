import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/request_proposal.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
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
import 'package:revoked_app/core/widgets/data_table/table_store.dart';
import 'package:revoked_app/features/requests/view/request_groups.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/features/requests/view/request_create_sheet.dart';
import 'package:revoked_app/core/widgets/app_tabs.dart';
import 'package:revoked_app/features/bookmarks/view/bookmarks_tab.dart';

/// Which requests the chips above the list let through.
enum _RequestFilter { all, open, closed }

class InboxScreen extends StatefulWidget {
  /// 1 opens on Received, the links other people gave you.
  final int initialTab;

  /// A tool's proposal for a new request; opens the form filled in.
  final RequestProposal? proposal;

  const InboxScreen({super.key, this.initialTab = 0, this.proposal});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> with RefreshOnEntry {
  late final TableStore<DataRequest> _table;
  final Local<_RequestFilter> _filter = Local(_RequestFilter.all);

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
    // Your requests, and what others gave you (saved links). Answers to a
    // request are on that request's page.
    return AppTabs(
      initialIndex: widget.initialTab,
      tabs: [
        AppTab(
          label: 'Your requests',
          icon: AppIcons.send,
          description: 'Requests sent to others, with their responses.',
          view: _yourRequests(context),
        ),
        const AppTab(
          label: 'Received',
          icon: AppIcons.inboxFill,
          description: 'Requests and links received from others.',
          view: BookmarksTab(),
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
        filters: ['All', 'Open', 'Closed'],
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
              onTap: () => context.go(AppRoutes.templates),
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
        final open = matches.where((r) => !isRequestClosed(r)).length;
        final filter = _filter.value;

        bool shows(DataRequest r) => switch (filter) {
          _RequestFilter.all => true,
          _RequestFilter.open => !isRequestClosed(r),
          _RequestFilter.closed => isRequestClosed(r),
        };

        Widget group(RequestGroup g, String title, {bool collapsed = false}) {
          final requests = byGroup[g]!.where(shows).toList();
          if (requests.isEmpty) return const SizedBox.shrink();
          return AppListGroup(
            // A new filter starts the group over, so picking "Closed" opens
            // the group it would otherwise keep folded.
            key: ValueKey('$g-$filter'),
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
                  onTap: () => context.go(AppRoutes.requestDetailFor(r.id)),
                ),
            ],
          );
        }

        final nothingShown = !matches.any(shows);

        return AppListPage(
          banners: [
            if (reqStore.loadState.error != null)
              AppRefreshFailed(onRetry: reqStore.loadRequests),
          ],
          filters: AppFilterChips<_RequestFilter>(
            selected: filter,
            onSelected: (f) => _filter.value = f,
            options: [
              AppFilterOption(
                value: _RequestFilter.all,
                label: 'All',
                count: matches.length,
              ),
              AppFilterOption(
                value: _RequestFilter.open,
                label: 'Open',
                count: open,
              ),
              AppFilterOption(
                value: _RequestFilter.closed,
                label: 'Closed',
                count: matches.length - open,
              ),
            ],
          ),
          emptyMessage: nothingShown ? 'No requests match the filters.' : null,
          groups: [
            group(RequestGroup.fresh, 'New responses'),
            group(RequestGroup.open, 'Open'),
            group(
              RequestGroup.closed,
              'Closed',
              collapsed: filter != _RequestFilter.closed,
            ),
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

  const _RequestRow({
    required this.request,
    required this.unread,
    required this.now,
    required this.onTap,
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
          : StatusLabel(request.status),
      onTap: onTap,
    );
  }
}
