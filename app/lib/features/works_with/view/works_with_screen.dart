import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/app_colors.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/models/works_with.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_card.dart';
import 'package:revoked_app/core/widgets/app_divider.dart';
import 'package:revoked_app/core/widgets/app_empty_state.dart';
import 'package:revoked_app/core/widgets/app_filter_chips.dart';
import 'package:revoked_app/core/widgets/app_filter_menu.dart';
import 'package:revoked_app/core/widgets/app_list_group.dart';
import 'package:revoked_app/core/widgets/app_list_page.dart';
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
      filters: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(intro).muted.small,
          AppSpacing.gapMd,
          _doesChips(searched),
        ],
      ),
      emptyMessage: shown.isEmpty
          ? 'No service matches the search or filters.'
          : null,
      groups: [
        if (mine.isNotEmpty)
          _ServiceGroup(
            title: 'Connected',
            // A connected service is the one most often opened, so it takes
            // the full width.
            maxColumns: 1,
            children: [
              for (final s in mine)
                _ServiceCard(s, connected: true, onTap: () => _open(s)),
            ],
          ),
        if (rest.isNotEmpty)
          _ServiceGroup(
            title: mine.isEmpty ? 'Listed' : 'Other listed services',
            children: [
              for (final s in rest) _ServiceCard(s, onTap: () => _open(s)),
            ],
          ),
        _ListingNote(onTap: _openRepo),
      ],
    );
  }

  /// "What it does" as chips above the list, the filter reached for most.
  /// They show and change the same selection as that section of Filter and
  /// sort; with several ticked there, no chip is the selected one.
  Widget _doesChips(List<WorksWithService> searched) {
    final on = _on(_Section.does);
    return AppFilterChips<String>(
      selected: switch (on.length) {
        0 => '',
        1 => on.first,
        _ => '\u0000',
      },
      onSelected: (key) => _selected.value = {
        ..._selected.value,
        _Section.does: {if (key.isNotEmpty) key},
      },
      options: [
        AppFilterOption(value: '', label: 'All', count: searched.length),
        for (final k in ServiceKind.values)
          AppFilterOption(
            value: k.key,
            label: k.label,
            count: searched.where((s) => s.does.contains(k)).length,
          ),
      ],
    );
  }

  void _open(WorksWithService s) =>
      context.go(AppRoutes.worksWithServiceFor(s.slug));

  Future<void> _openRepo() async {
    await launchUrl(
      Uri.parse(AppConfig.worksWithRepoUrl),
      mode: LaunchMode.externalApplication,
    );
  }
}

/// A titled grid of service cards: two beside each other where the page is
/// wide enough, one on a phone. Cards in a row share the taller one's height,
/// so the access lines at their feet line up.
class _ServiceGroup extends StatelessWidget {
  final String title;
  final int maxColumns;
  final List<Widget> children;

  const _ServiceGroup({
    required this.title,
    required this.children,
    this.maxColumns = 2,
  });

  /// Below this a card is too narrow for its address on one line.
  static const double _twoColumnWidth = 640;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppListHeader(
            title: title,
            trailing: AppText('${children.length}').small.muted,
          ),
          LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth >= _twoColumnWidth ? maxColumns : 1;
              return Column(
                children: [
                  for (var i = 0; i < children.length; i += columns) ...[
                    if (i > 0) AppSpacing.gapMd,
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var j = i; j < i + columns; j++) ...[
                            if (j > i) AppSpacing.gapMd,
                            Expanded(
                              child: j < children.length
                                  ? children[j]
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One listed service: what it is, where it lives, what it does, and at its
/// foot the most of the vault it may ask for.
class _ServiceCard extends StatelessWidget {
  final WorksWithService service;
  final bool connected;
  final VoidCallback onTap;

  const _ServiceCard(
    this.service, {
    this.connected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = service;
    final scheme = Theme.of(context).colorScheme;
    final description = s.description.text;
    final (accessIcon, accessColor) = switch (s.access) {
      ServiceAccess.linksOnly => (AppIcons.lock, scheme.success),
      ServiceAccess.ownSection => (AppIcons.folder, scheme.onSurfaceVariant),
      ServiceAccess.readsVault => (AppIcons.eye, scheme.warning),
    };
    return Semantics(
      button: true,
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: AppRadius.allMd,
                  ),
                  child: Icon(
                    _iconFor(s),
                    size: 20,
                    color: s.unavailable
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                  ),
                ),
                AppSpacing.gapMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          s.unavailable
                              ? AppText(s.name).bold.muted
                              : AppText(s.name).bold,
                          if (connected)
                            AppBadge(
                              icon: AppIcons.plug,
                              label: 'Connected',
                              accent: scheme.success,
                            ),
                          WorksWithMark(s),
                          if (s.builtByRevoked)
                            const AppBadge(
                              label: 'Built by Revoked',
                              variant: AppBadgeVariant.outline,
                            ),
                        ],
                      ),
                      AppText(
                        s.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).small.mono.muted,
                    ],
                  ),
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              AppSpacing.gapMd,
              AppText(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ).small.muted,
            ],
            AppSpacing.gapMd,
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: [
                for (final k in s.does)
                  AppBadge(label: k.label, variant: AppBadgeVariant.sunken),
                for (final c in s.categories)
                  AppBadge(label: c.label, variant: AppBadgeVariant.outline),
              ],
            ),
            const Spacer(),
            AppSpacing.gapMd,
            const AppDivider(),
            AppSpacing.gapMd,
            Row(
              children: [
                Icon(accessIcon, size: 14, color: accessColor),
                AppSpacing.gapXs,
                Expanded(
                  child: Text(
                    s.access.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accessColor,
                      fontSize: AppTextSize.small,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Under the list: how a service comes to be on it, and that one which is
/// not works exactly as well.
class _ListingNote extends StatelessWidget {
  final VoidCallback onTap;

  const _ListingNote({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppDivider(),
        AppSpacing.gapMd,
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: const Text(
                'Services are added and changed through a reviewed pull '
                'request. A service that is not listed works exactly as well.',
              ).small.muted,
            ),
            AppButton(
              icon: AppIcons.boxArrowUpRight,
              label: 'How services are listed',
              style: AppButtonStyle.accent,
              size: AppButtonSize.small,
              onTap: onTap,
            ),
          ],
        ),
      ],
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
