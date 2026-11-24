import 'package:material_ui/material_ui.dart';
import 'package:revoked_app/core/state/tree_folds_store.dart';
import 'package:revoked_app/features/requests/view/request_actions.dart';
import 'package:revoked_app/core/models/bookmark.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/features/shell/utils/new_actions.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/request_proposal.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/refresh_on_entry.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/audience_tag.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_tree_row.dart';
import 'package:revoked_app/core/models/connection.dart';
import 'package:revoked_app/core/widgets/app_load_error.dart';
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:revoked_app/core/widgets/app_status_badge.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';
import 'package:revoked_app/features/requests/view/request_groups.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/features/requests/view/request_create_sheet.dart';
import 'package:revoked_app/core/widgets/app_tabs.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_filter_menu.dart';
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

  /// The groups the Filter lets through; none ticked lets all through.
  final Local<Set<RequestGroup>> _groups = Local(const {});

  /// Who sees a request, as the Filter's "Visible to" ticks it (`private`,
  /// `workspace`, `group:<id>`); none ticked lets all through.
  final Local<Set<String>> _audiences = Local(const {});

  static bool _open(String id) => Stores.folds.isOpen(TreeFold.requests, id);

  static void _toggle(String id) {
    Stores.folds.toggle(TreeFold.requests, id);
    if (_open(id)) _loadAnswers(id);
  }

  /// A request left open shows its answers again on the way back.
  static void _loadAnswers(String id) {
    if (!Stores.requests.responsesByRequest.containsKey(id)) {
      Stores.requests.loadResponses(id);
    }
  }

  static Audience _audienceOf(DataRequest r) =>
      Audience(r.audienceKind, r.audienceGroups);

  static const _groupTitles = {
    RequestGroup.fresh: 'New responses',
    RequestGroup.open: 'Open',
    RequestGroup.closed: 'Closed',
  };

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
      searchFields: const ['label', 'slug'],
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
    Stores.requests.loadIfDue().then((_) {
      final ids = {for (final r in Stores.requests.requests) r.id};
      Stores.folds
          .opened(TreeFold.requests)
          .where(ids.contains)
          .forEach(_loadAnswers);
    });
    Stores.bookmarks.loadIfDue();
    // Requests are grouped under their template's and tool's names.
    final workspace = Stores.auth.activeWorkspace ?? '';
    if (workspace.isNotEmpty && Stores.templates.templates.isEmpty) {
      Stores.templates.loadTemplates(workspace);
    }
    Stores.connections.loadSummariesIfDue();
  }

  @override
  Widget build(BuildContext context) {
    // The same two tabs as Shares: what this account asked for, and what
    // others ask of it. Answers to a request are on that request's page;
    // shares others gave are under Shares › Received.
    return AppTabs(
      title: 'Your requests',
      action: const PageActionButton(AppRoutes.requests),
      initialIndex: widget.initialTab,
      tabs: [
        AppTab(
          label: 'Sent',
          icon: AppIcons.send,
          view: _yourRequests(context),
        ),
        AppTab(
          label: 'To answer',
          icon: AppIcons.askFor,
          view: const BookmarksTab(
            kind: BookmarkKind.request,
            showHeader: false,
          ),
        ),
      ],
    );
  }

  /// Search, a Filter by where a request stands, and a Sort.
  AppListToolbar _toolbar(Map<RequestGroup, int> counts) => AppListToolbar(
    key: const ValueKey('requests-toolbar'),
    totalCount: _table.filteredItems.length,
    query: _table.query,
    onQueryChanged: _table.setQuery,
    searchHint: 'Search requests',
    onClearFilters: () {
      _groups.value = const {};
      _audiences.value = const {};
    },
    sections: () => [
      AppChecklistSection(
        title: 'Status',
        selected: {for (final g in _groups.value) g.name},
        onToggle: (id, on) {
          final g = RequestGroup.values.byName(id);
          _groups.value = on
              ? {..._groups.value, g}
              : ({..._groups.value}..remove(g));
        },
        items: [
          for (final g in RequestGroup.values)
            AppChecklistItem(
              id: g.name,
              label: _groupTitles[g]!,
              count: counts[g],
            ),
        ],
      ),
      ?audienceFilterSection(
        items: [
          for (final r in [
            ...Stores.requests.requests,
            ...Stores.requests.sharedRequests,
          ])
            [_audienceOf(r)],
        ],
        selected: _audiences.value,
        onToggle: (id, on) => _audiences.value = on
            ? {..._audiences.value, id}
            : ({..._audiences.value}..remove(id)),
      ),
    ],
    sort: () => _table.sortBy,
    onSort: _table.setSort,
    defaultSort: _table.defaultSort,
    sortOptions: const [
      AppSortOption('created_desc', 'Newest first'),
      AppSortOption('created_asc', 'Oldest first'),
      AppSortOption('label_asc', 'Name A–Z'),
      AppSortOption('status_asc', 'Status'),
    ],
  );

  Widget _yourRequests(BuildContext context) {
    final reqStore = Stores.requests;

    return AppLoadFade(
      loading: () =>
          reqStore.loadState.isFirstLoad && reqStore.requests.isEmpty,
      skeleton: AppPageBody(
        children: [
          AppListSkeleton(
            embedded: true,
            group: 'Open',
            rows: [
              AppSkeletonRow(
                'Tenant details',
                '4 fields · 2 responses',
                icon: AppIcons.inboxFill,
                badge: '2 new',
              ),
              AppSkeletonRow(
                'New starters',
                '6 fields',
                icon: AppIcons.inboxFill,
              ),
              AppSkeletonRow(
                'Club members',
                '3 fields · 8 responses',
                icon: AppIcons.inboxFill,
              ),
            ],
          ),
        ],
      ),
      builder: (_) {
        // Nothing to list has nothing to search, so no Search and filter.
        Widget bare(Widget child) => AppPageBody(children: [child]);
        if (reqStore.requests.isEmpty &&
            reqStore.sharedRequests.isEmpty &&
            reqStore.loadState.error != null) {
          return bare(
            AppLoadError(
              title: 'Requests could not be loaded',
              message: reqStore.loadState.error!,
              onRetry: reqStore.loadRequests,
            ),
          );
        }

        if (reqStore.requests.isEmpty && reqStore.sharedRequests.isEmpty) {
          return bare(
            AppEmptyState(
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
              learnMoreLabel: 'How requests work',
              learnMoreUrl: '${AppConfig.docsUrl}/guide/requests/',
            ),
          );
        }

        final now = DateTime.now();
        final notifications = Stores.notifications;
        final audiences = _audiences.value;
        final searched = _table.filteredItems
            .where((r) => audienceMatches(audiences, [_audienceOf(r)]))
            .toList();
        final sharedShown = reqStore.sharedRequests
            .where((r) => audienceMatches(audiences, [_audienceOf(r)]))
            .toList();
        final picked = _groups.value;
        final byGroup = {
          for (final g in RequestGroup.values) g: <DataRequest>[],
        };
        final counts = {for (final g in RequestGroup.values) g: 0};
        final unread = <String, int>{};
        for (final r in searched) {
          final n = notifications.unreadResponses(r.id);
          unread[r.id] = n;
          final g = requestGroup(r, n);
          counts[g] = counts[g]! + 1;
          if (picked.isEmpty || picked.contains(g)) byGroup[g]!.add(r);
        }
        final nothingShown =
            byGroup.values.every((l) => l.isEmpty) &&
            (sharedShown.isEmpty || picked.isNotEmpty);
        List<Widget> rowsOf(
          Iterable<DataRequest> requests, {
          required bool status,
          int depth = 0,
        }) => [
          for (final r in requests) ...[
            _RequestRow(
              request: r,
              unread: unread[r.id] ?? 0,
              now: now,
              depth: depth,
              showStatus: status,
              expanded: _open(r.id),
              onToggle: () => _toggle(r.id),
              onTap: () => context.go(AppRoutes.requestDetailFor(r.id)),
            ),
            if (_open(r.id)) ..._answerRows(context, r, depth + 1),
          ],
        ];

        // Open requests by who created them, then by the template they ask
        // with; new answers stay on top and closed requests folded below.
        final byCreator = <_Creator, Map<String, List<DataRequest>>>{};
        for (final r in byGroup[RequestGroup.open]!) {
          (byCreator[_Creator.of(r)] ??= {})
              .putIfAbsent(r.templateId, () => [])
              .add(r);
        }
        final creators = byCreator.keys.toList()..sort();
        Widget creatorGroup(_Creator c) {
          final templates = byCreator[c]!.entries.toList()
            ..sort((a, b) {
              if (a.key.isEmpty != b.key.isEmpty) return a.key.isEmpty ? 1 : -1;
              return _templateName(a.key)
                  .toLowerCase()
                  .compareTo(_templateName(b.key).toLowerCase());
            });
          return AppListGroup(
            key: ValueKey('requests-by-${c.id}'),
            title: c.name,
            noun: 'requests',
            count: templates.fold<int>(0, (n, t) => n + t.value.length),
            // Only untemplated requests need no template row above them.
            children: templates.length == 1 && templates.single.key.isEmpty
                ? rowsOf(templates.single.value, status: false)
                : [
                    for (final MapEntry(key: template, value: requests)
                        in templates)
                      ...() {
                        final id = '${c.id}/$template';
                        final open = Stores.folds.isOpen(
                          TreeFold.requestTemplates,
                          id,
                        );
                        return [
                          AppTreeRow(
                            key: ValueKey('request-template-$id'),
                            icon: template.isEmpty
                                ? AppIcons.cardList
                                : AppIcons.folder,
                            title: template.isEmpty
                                ? 'No template'
                                : _templateName(template),
                            subtitle:
                                '${requests.length} ${requests.length == 1 ? 'request' : 'requests'}',
                            expanded: open,
                            onToggle: () => Stores.folds.toggle(
                              TreeFold.requestTemplates,
                              id,
                            ),
                          ),
                          if (open)
                            ...rowsOf(requests, status: false, depth: 1),
                        ];
                      }(),
                  ],
          );
        }

        // The groups are the filter: each says how many it holds, and the
        // closed ones stay folded until asked for.
        Widget group(RequestGroup g, String title, {bool collapsed = false}) {
          final requests = byGroup[g]!;
          if (requests.isEmpty) return const SizedBox.shrink();
          return AppListGroup(
            key: ValueKey((g, collapsed)),
            title: title,
            noun: 'requests',
            previewCount: g == RequestGroup.fresh ? 0 : 5,
            collapsed: collapsed,
            // Only the closed group mixes statuses worth telling apart.
            children: rowsOf(requests, status: g == RequestGroup.closed),
          );
        }

        return AppListPage(
          toolbar: _toolbar(counts),
          inlineToolbar: true,
          banners: [
            if (reqStore.loadState.error != null)
              AppRefreshFailed(onRetry: reqStore.loadRequests),
          ],
          emptyMessage: nothingShown
              ? 'No requests match the search or filters.'
              : null,
          groups: [
            group(RequestGroup.fresh, 'New responses'),
            for (final c in creators) creatorGroup(c),
            group(
              RequestGroup.closed,
              'Closed',
              collapsed: !picked.contains(RequestGroup.closed),
            ),
            // Requests other members opened to this person, apart from their
            // own and outside the groups, which are about their own requests.
            if (sharedShown.isNotEmpty && picked.isEmpty)
              AppListGroup(
                title: 'Shared by members',
                noun: 'requests',
                previewCount: 5,
                children: [
                  for (final r in sharedShown)
                    _RequestRow(
                      request: r,
                      unread: 0,
                      now: now,
                      onTap: () => context.go(AppRoutes.requestDetailFor(r.id)),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  String _templateName(String id) {
    for (final t in Stores.templates.templates) {
      if (t.id == id) return t.name.isEmpty ? 'Unnamed template' : t.name;
    }
    return 'Template';
  }

  /// A request's answers, one per responder, under its row. Field names only:
  /// the values open on the request's own pages.
  List<Widget> _answerRows(BuildContext context, DataRequest r, int depth) {
    final responses = Stores.requests.responsesByRequest[r.id];
    if (responses == null) {
      return [AppTreeRow(depth: depth, icon: AppIcons.info, title: 'Loading…')];
    }
    if (responses.isEmpty) {
      return [
        AppTreeRow(
          depth: depth,
          icon: AppIcons.info,
          title: 'No responses yet',
        ),
      ];
    }
    final closed = isRequestClosed(r);
    return [
      for (final a in responses)
        () {
          final sender = (a['senderName'] as String?)?.trim() ?? '';
          final identifier = (a['identifier'] as String?)?.trim() ?? '';
          final data = a['data'];
          final fields = data is Map
              ? [for (final k in data.keys) k.toString()]
              : const <String>[];
          final revoked = a['status'] == 'revoked' || closed;
          return AppTreeRow(
            key: ValueKey('request-answer-${a['id'] ?? a['slug']}'),
            depth: depth,
            icon: ((a['identity'] as String?) ?? '').isNotEmpty
                ? AppIcons.shieldCheck
                : AppIcons.person,
            title: sender.isNotEmpty
                ? sender
                : identifier.isNotEmpty
                ? identifier
                : 'Anonymous',
            subtitle: fields.isEmpty
                ? 'No fields'
                : '${fields.length} ${fields.length == 1 ? 'field' : 'fields'}'
                      ' · ${fields.take(3).join(', ')}'
                      '${fields.length > 3 ? ' +${fields.length - 3} more' : ''}',
            trailing: StatusLabel(revoked ? 'revoked' : 'active'),
            onTap: () => context.go(AppRoutes.requestSheetFor(r.id)),
          );
        }(),
    ];
  }
}

/// Who created a request, which is the group it sits in: the app or one
/// connected tool.
class _Creator implements Comparable<_Creator> {
  final String id;
  final String name;
  final int rank;

  const _Creator(this.id, this.name, this.rank);

  static _Creator of(DataRequest r) {
    if (r.connection.isEmpty) return const _Creator('own', 'Own requests', 0);
    final tool = Stores.connections.connections
        .where((c) => c.id == r.connection)
        .firstOrNull;
    final name = tool == null || tool.name.isEmpty
        ? Connection.shortIdOf(r.connection)
        : tool.name;
    return _Creator('tool:${r.connection}', name, 1);
  }

  @override
  bool operator ==(Object other) => other is _Creator && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  int compareTo(_Creator other) => rank != other.rank
      ? rank.compareTo(other.rank)
      : name.toLowerCase().compareTo(other.name.toLowerCase());
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

  final int depth;

  /// Whether its answers show below it; null when they are not listed here.
  final bool? expanded;
  final VoidCallback? onToggle;

  const _RequestRow({
    required this.request,
    required this.unread,
    required this.now,
    required this.onTap,
    this.showStatus = true,
    this.depth = 0,
    this.expanded,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return AppTreeRow(
      key: ValueKey('request-${request.id}'),
      depth: depth,
      expanded: expanded,
      onToggle: onToggle,
      icon: AppIcons.inboxFill,
      title: request.label.trim().isEmpty ? 'Unnamed request' : request.label,
      accent: unread > 0 ? Theme.of(context).colorScheme.primary : null,
      subtitle: requestSummary(request, unread, now),
      audience: AudienceTag(
        Audience(request.audienceKind, request.audienceGroups),
      ),
      trailing: unread > 0
          ? AppBadge(
              label: '$unread new',
              accent: Theme.of(context).colorScheme.primary,
            )
          : showStatus
          ? StatusLabel(request.status)
          : null,
      onTap: onTap,
      contextActions: () => requestContextActions(context, request),
    );
  }
}
