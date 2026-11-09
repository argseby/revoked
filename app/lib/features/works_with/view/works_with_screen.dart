import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/models/works_with.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_filter_menu.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/features/works_with/view/works_with_chip.dart';

/// Works with Revoked: the services and tools built on Revoked, as reviewed
/// in the repository. A tool that is not listed works exactly as well; the
/// list only helps to find them.
class WorksWithScreen extends StatefulWidget {
  const WorksWithScreen({super.key});

  @override
  State<WorksWithScreen> createState() => _WorksWithScreenState();
}

/// The filter sections, keyed so a selection can say which section it is in.
enum _Section { does, category, access, runsOn, language, mark }

class _WorksWithScreenState extends State<WorksWithScreen> {
  final _query = Local<String>('');
  final _sort = Local<String>(_defaultSort);
  final _selected = Local<Map<_Section, Set<String>>>(const {});

  static const _defaultSort = 'name_asc';
  static const intro =
      'Services and tools built on Revoked. Each listing is reviewed before '
      'it appears here, and a service is identified by its address.';

  @override
  void initState() {
    super.initState();
    Stores.worksWith.refreshIfDue();
    // Which listed services are already connected, to mark and list them
    // first. Read from the stores the Connected tools page fills.
    Stores.connections.load();
    Stores.signIns.loadIfDue();
  }

  Set<String> _on(_Section s) => _selected.value[s] ?? const {};

  void _toggle(_Section s, String id, bool on) {
    final next = {..._on(s)};
    on ? next.add(id) : next.remove(id);
    _selected.value = {..._selected.value, s: next};
  }

  /// Origins of the tools and sign-in services this account has connected.
  Set<String> get _connected => {
    for (final c in Stores.connections.connections)
      ?ToolClient.origin(c.clientId),
    for (final s in Stores.signIns.services) ?ToolClient.origin(s.clientId),
  };

  bool _matchesQuery(WorksWithService s) {
    final q = _query.value.trim().toLowerCase();
    if (q.isEmpty) return true;
    final text = s.searchText;
    return q.split(RegExp(r'\s+')).every(text.contains);
  }

  /// Within a section a service passes if it has any ticked value; across
  /// sections it must pass each one.
  bool _passes(WorksWithService s) {
    bool any(_Section section, Iterable<String> values) {
      final on = _on(section);
      return on.isEmpty || values.any(on.contains);
    }

    return any(_Section.does, s.does.map((k) => k.key)) &&
        any(_Section.category, s.categories.map((c) => c.key)) &&
        any(_Section.access, [s.access.name]) &&
        any(_Section.runsOn, [
          if (s.worksWithAnyServer) 'any',
          if (s.selfHostable) 'self_hostable',
          if (s.source.isNotEmpty) 'open_source',
        ]) &&
        any(_Section.language, s.languages) &&
        any(_Section.mark, [
          if (s.verified) 'verified',
          if (s.builtByRevoked) 'revoked',
        ]);
  }

  List<WorksWithService> _sorted(List<WorksWithService> list) {
    final out = [...list];
    if (_sort.value == 'reviewed_desc') {
      out.sort((a, b) => b.reviewed.compareTo(a.reviewed));
    } else {
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return out;
  }

  AppListToolbar _toolbar(List<WorksWithService> searched) {
    AppChecklistItem item(
      String id,
      String label,
      bool Function(WorksWithService) has,
    ) => AppChecklistItem(
      id: id,
      label: label,
      count: searched.where(has).length,
    );
    AppChecklistSection section(
      _Section s,
      String title,
      List<AppChecklistItem> items,
    ) => AppChecklistSection(
      title: title,
      selected: _on(s),
      onToggle: (id, on) => _toggle(s, id, on),
      items: items,
    );
    return AppListToolbar(
      key: const ValueKey('works-with-toolbar'),
      query: _query.value,
      onQueryChanged: (q) => _query.value = q,
      searchHint: 'Search services',
      onClearFilters: () => _selected.value = const {},
      sections: () => [
        section(_Section.does, 'What it does', [
          for (final k in ServiceKind.values)
            item(k.key, k.label, (s) => s.does.contains(k)),
        ]),
        section(_Section.category, 'Category', [
          for (final c in ServiceCategory.values)
            item(c.key, c.label, (s) => s.categories.contains(c)),
        ]),
        section(_Section.access, 'Access it may ask for', [
          for (final a in ServiceAccess.values)
            item(a.name, a.label, (s) => s.access == a),
        ]),
        section(_Section.runsOn, 'Runs on', [
          item('any', 'Any Revoked server', (s) => s.worksWithAnyServer),
          item('self_hostable', 'Self-hostable', (s) => s.selfHostable),
          item('open_source', 'Open source', (s) => s.source.isNotEmpty),
        ]),
        section(_Section.language, 'Language', [
          item('en', 'English', (s) => s.languages.contains('en')),
          item('de', 'Deutsch', (s) => s.languages.contains('de')),
        ]),
        section(_Section.mark, 'Listing', [
          item('verified', 'Verified only', (s) => s.verified),
          item('revoked', 'Built by Revoked', (s) => s.builtByRevoked),
        ]),
      ],
      sort: () => _sort.value,
      onSort: (v) => _sort.value = v,
      defaultSort: _defaultSort,
      sortOptions: const [
        AppSortOption('name_asc', 'Name A–Z'),
        AppSortOption('reviewed_desc', 'Recently reviewed'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Observer(builder: _build);

  Widget _build(BuildContext context) {
    final all = Stores.worksWith.services;
    if (all.isEmpty) {
      return AppListEmpty(
        toolbar: _toolbar(const []),
        child: AppEmptyState(
          icon: AppIcons.worksWith,
          title: 'No services listed',
          subtitle: intro,
          action: AppButton(
            icon: AppIcons.boxArrowUpRight,
            label: 'How services are listed',
            onTap: () => _openRepo(),
          ),
        ),
      );
    }
    final searched = all.where(_matchesQuery).toList();
    final shown = _sorted(searched.where(_passes).toList());
    final connected = _connected;
    final mine = [
      for (final s in shown)
        if (connected.contains(s.origin)) s,
    ];
    final rest = [
      for (final s in shown)
        if (!connected.contains(s.origin)) s,
    ];

    return AppListPage(
      toolbar: _toolbar(searched),
      filters: const Text(intro).muted.small,
      emptyMessage: shown.isEmpty
          ? 'No service matches the search or filters.'
          : null,
      groups: [
        if (mine.isNotEmpty)
          AppListGroup(
            title: 'Connected',
            children: [for (final s in mine) _row(context, s, connected: true)],
          ),
        if (rest.isNotEmpty)
          AppListGroup(
            title: mine.isEmpty ? 'Listed' : 'Other listed services',
            footer: Text.rich(
              TextSpan(
                text:
                    'Services are added and changed through a reviewed pull '
                    'request. ',
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: InkWell(
                      onTap: _openRepo,
                      child: Text(
                        'How services are listed',
                        style: TextStyle(
                          decoration: TextDecoration.underline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            children: [for (final s in rest) _row(context, s)],
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    WorksWithService s, {
    bool connected = false,
  }) {
    final description = s.description.text;
    return AppListRow(
      icon: _iconFor(s),
      title: s.name,
      subtitle: [
        s.host,
        s.does.map((k) => k.label).join(', '),
        if (description.isNotEmpty) description,
      ].join(' · '),
      trailing: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (connected)
            const AppBadge(icon: AppIcons.plug, label: 'Connected'),
          WorksWithMark(s),
        ],
      ),
      onTap: () => context.go(AppRoutes.worksWithServiceFor(s.slug)),
    );
  }

  Future<void> _openRepo() async {
    await launchUrl(
      Uri.parse(AppConfig.worksWithRepoUrl),
      mode: LaunchMode.externalApplication,
    );
  }
}

IconData _iconFor(WorksWithService s) =>
    switch (s.categories.isEmpty ? null : s.categories.first) {
      ServiceCategory.health => AppIcons.health,
      ServiceCategory.housing => AppIcons.home,
      ServiceCategory.work => AppIcons.work,
      ServiceCategory.finance => AppIcons.finance,
      ServiceCategory.games => AppIcons.games,
      ServiceCategory.developer => AppIcons.code,
      _ => AppIcons.worksWith,
    };
