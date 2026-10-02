import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_filter_chips.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_search_field.dart';
import 'package:revoked_app/core/widgets/app_spinner.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';
import 'package:revoked_app/features/requests/view/request_groups.dart';

/// Which requests the chips above the list let through.
enum _RequestFilter { all, open, closed }

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
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
      if (mounted) {
        ShellSlots.title.claim(_title);
      }
      Stores.requests.loadRequests();
    });
  }

  @override
  void dispose() {
    ShellSlots.title.release(_title);
    super.dispose();
  }

  /// The top bar carries the search; its hint carries the count.
  Widget _title(BuildContext context) {
    final count = Stores.requests.requests.length;
    return AppSearchField<DataRequest>(
      controller: _table,
      hint: 'Search $count ${count == 1 ? 'request' : 'requests'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final reqStore = Stores.requests;

    return Observer(
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

        if (reqStore.requests.isEmpty) {
          return AppEmptyState(
            icon: AppIcons.inboxFill,
            title: 'No requests yet',
            subtitle:
                'Tap + to create a data request and start collecting peer data.',
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
          emptyMessage: nothingShown ? 'No requests match your filters.' : null,
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
          : AppStatusBadge(request.status),
      onTap: onTap,
    );
  }
}
