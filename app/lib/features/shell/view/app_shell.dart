import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/state/sheet_tracker.dart';
import 'package:revoked_app/core/state/shell_slots.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_badge.dart';
import 'package:revoked_app/core/widgets/app_bar_title.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_search_field.dart';
import 'package:revoked_app/core/widgets/app_focus_ring.dart';
import 'package:revoked_app/core/widgets/app_key_hint.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/core/widgets/feature_notice.dart';
import 'package:revoked_app/features/shell/view/account_menu.dart';
import 'package:revoked_app/features/shell/view/link_search_sheet.dart';
import 'package:revoked_app/features/shell/utils/new_actions.dart';
import 'package:revoked_app/features/shell/view/new_picker.dart';

/// One of the shell's places, keyed by its root in `AppRoutes.allDestinations`.
class _Destination {
  final String route;
  final IconData icon;
  final String label;

  /// Built on the vault: shares give its records out, requests fill it. The
  /// sidebar hangs these under it; the narrower bars stay flat.
  final bool underVault;

  const _Destination(
    this.route,
    this.icon,
    this.label, {
    this.underVault = false,
  });
}

const _places = [
  _Destination(AppRoutes.overview, AppIcons.dashboard, 'Overview'),
  _Destination(AppRoutes.vault, AppIcons.safe, 'Vault'),
  _Destination(AppRoutes.shared, AppIcons.share, 'Shares'),
  _Destination(AppRoutes.requests, AppIcons.inboxFill, 'Requests'),
  _Destination(AppRoutes.attestations, AppIcons.attestation, 'Attestations'),
  _Destination(AppRoutes.contacts, AppIcons.person, 'Contacts'),
];

/// The places the person has on, in their fixed order: a feature turned off
/// takes its tab away and the rest close up without changing places.
List<_Destination> _shownDestinations() => [
  for (final root in AppRoutes.destinations)
    _places.firstWhere((d) => d.route == root),
];

/// How many of the shown destinations a phone's bottom bar holds; the rest sit
/// behind More. A sixth tab leaves under 64 pixels each on a small phone,
/// where longer labels break mid-word.
const _phoneBarDestinations = 4;

/// The frame around every signed-in screen.
///
/// The same destinations at every width: a bottom bar with More on a phone, a
/// rail on a mid-sized window and a sidebar on a wide one. One "New" button,
/// in the navigation or floating on a phone, opens the picker for everything
/// that can be created; search and the account menu are reachable from every
/// layout.
class AppShell extends StatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// The destination last shown, so the bottom bar still has one to sit on
  /// while Settings is open.
  String _lastRoot = AppRoutes.vault;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Notifications power the bell, which is visible on every screen.
      Stores.notifications.load();
      Stores.notifications.startPolling();
      // Which tabs show is the person's choice crossed with what the
      // workspace lets them do: the catalogue names the permission each
      // feature needs, and the roster says which of those they hold.
      Stores.features.loadIfDue();
      final ws = Stores.auth.activeWorkspace ?? '';
      if (ws.isNotEmpty && Stores.invites.members.isEmpty) {
        Stores.invites.loadMembers(ws);
      }
    });
  }

  @override
  void dispose() {
    Stores.notifications.stopPolling();
    super.dispose();
  }

  void _go(int index) => context.go(AppRoutes.destinations[index]);

  void _openNew(String? root) => openNewPicker(context, destination: root);

  void _openMore() {
    final shown = _shownDestinations();
    showAppOptionsSheet(
      context: context,
      title: 'More',
      actions: [
        AppSheetAction(
          icon: AppIcons.plus,
          label: 'Create something new',
          onTap: () => _openNew(AppRoutes.rootOf(_lastRoot)),
        ),
        for (var i = _phoneBarDestinations; i < shown.length; i++)
          AppSheetAction(
            icon: shown[i].icon,
            label: shown[i].label,
            onTap: () => _go(i),
          ),
        AppSheetAction(
          icon: AppIcons.personGear,
          label: 'Settings',
          onTap: () => context.go(AppRoutes.settings),
        ),
      ],
    );
  }

  /// A control the active screen registered, with the gap that belongs to it —
  /// an unclaimed slot takes no space at all.
  Widget _slot(ShellSlot slot) {
    return Observer(
      builder: (context) {
        final builder = slot.builder;
        if (builder == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(right: AppSpacing.xs),
          child: builder(context),
        );
      },
    );
  }

  /// The screen's own title, or the place's name while it has none.
  Widget _title(String? root) {
    final onNotifications = GoRouterState.of(
      context,
    ).uri.path.startsWith(AppRoutes.notifications);
    final fallback = root != null
        ? _places.firstWhere((d) => d.route == root).label
        : onNotifications
        ? 'Notifications'
        : 'Settings';
    return Observer(
      builder: (context) =>
          ShellSlots.title.builder?.call(context) ??
          AppBarTitle(title: fallback),
    );
  }

  /// The screen, with a word above it when it belongs to a feature the
  /// person has off: a link or an old bookmark still opens the page, and
  /// the notice is what keeps that from being a dead end.
  Widget _body(String path) {
    final feature = featureForLocation(path);
    if (feature == null) return widget.child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FeatureNotice(feature),
        Expanded(child: widget.child),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Which places show follows the feature store, so the frame is reactive.
    return Observer(builder: _build);
  }

  Widget _build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final root = AppRoutes.rootOf(path);
    final destination = AppRoutes.destinationOf(path);
    if (destination != null) _lastRoot = root!;
    final width = MediaQuery.sizeOf(context).width;
    if (width < AppSpacing.narrowWidth) {
      final isSubPage = path != (root ?? AppRoutes.settings);
      return _narrow(root, destination, path, isSubPage: isSubPage);
    }
    return _wide(
      root,
      destination,
      path,
      sidebar: width >= AppSpacing.wideWidth,
    );
  }

  /// A sub-page's back arrow is its way out, so it needs no avatar beside it,
  /// and leaves the title that room.
  Widget _narrow(
    String? root,
    int? destination,
    String path, {
    required bool isSubPage,
  }) {
    return Scaffold(
      floatingActionButtonLocation: .endFloat,
      // Yields while any sheet is up, so it never overlaps a sheet's actions,
      // and on a detail page, where it would sit on the page's own controls.
      floatingActionButton: Observer(
        builder: (_) {
          // A sub-page with an action of its own shows it, Settings pages
          // included, though Settings is no destination on a phone.
          final own = subPageActionFor(path);
          if (SheetTracker.anyOpen ||
              (own == null && (destination == null || isSubPage))) {
            return const SizedBox.shrink();
          }
          // The page's own action when it has one; the general New stays
          // under More.
          final action = pageActionFor(path);
          return FloatingActionButton.extended(
            heroTag: 'shell-new',
            tooltip: action?.label ?? 'Create something new',
            onPressed: () =>
                action == null ? _openNew(root) : action.start(context),
            icon: Icon(action?.icon ?? AppIcons.plus, size: 18),
            label: Text(action?.label ?? 'New'),
          );
        },
      ),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: isSubPage
            ? null
            : AppSpacing.lg + AppButton.normalExtent + AppSpacing.xs,
        leading: isSubPage
            ? null
            : const Padding(
                padding: EdgeInsets.only(
                  left: AppSpacing.lg,
                  right: AppSpacing.xs,
                ),
                child: Center(child: AccountMenu()),
              ),
        titleSpacing: isSubPage ? AppSpacing.lg : AppSpacing.xs,
        title: _title(root),
        actions: [
          _slot(ShellSlots.action),
          AppButton(
            icon: AppIcons.search,
            style: AppButtonStyle.ghost,
            tooltip: 'Search or paste a link',
            onTap: () => openLinkSearchSheet(context),
          ),
          AppSpacing.gapXs,
          const _NotificationBell(),
          AppSpacing.gapXs,
        ],
      ),
      body: _body(path),
      bottomNavigationBar: _bottomBar(destination),
    );
  }

  Widget _bottomBar(int? destination) {
    final shown = _shownDestinations();
    final onBar = shown.take(_phoneBarDestinations).toList();
    // A place past the bar, or one the person hid, shows More as current.
    final resting = destination ?? AppRoutes.destinationOf(_lastRoot) ?? 0;
    final bar = NavigationBar(
      selectedIndex: min(resting, onBar.length),
      onDestinationSelected: (i) => i == onBar.length ? _openMore() : _go(i),
      destinations: [
        for (final d in onBar)
          NavigationDestination(icon: Icon(d.icon), label: d.label),
        const NavigationDestination(
          icon: Icon(AppIcons.threeDots),
          label: 'More',
        ),
      ],
    );
    if (destination != null) return bar;
    // On Settings no tab is current, so none looks it.
    final scheme = Theme.of(context).colorScheme;
    final theme = NavigationBarTheme.of(context);
    return NavigationBarTheme(
      data: theme.copyWith(
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStatePropertyAll(
          IconThemeData(size: 24, color: scheme.onSurfaceVariant),
        ),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: AppTextSize.small,
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
      child: bar,
    );
  }

  Widget _wide(
    String? root,
    int? destination,
    String path, {
    required bool sidebar,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final shown = _shownDestinations();
    final width = MediaQuery.sizeOf(context).width;
    final roomForSearchField = width >= _searchFieldMinWindow;
    // A page's own "New …" belongs to its list. A detail page has its own
    // actions, and the navigation's New is always at hand; only Shares keeps
    // its list beside the open link on a wide window.
    final onList =
        path == root ||
        subPageActionFor(path) != null ||
        (sidebar && root == AppRoutes.shared);
    final pageAction = onList ? pageActionFor(path) : null;
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sidebar)
            _Sidebar(
              shown: shown,
              destination: destination,
              onSelect: _go,
              onNew: () => _openNew(root),
            )
          else
            NavigationRail(
              selectedIndex: destination,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              // A phone on its side is this wide but too short for every place.
              scrollable: true,
              leading: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  children: [
                    const AccountMenu(),
                    AppSpacing.gapSm,
                    // Outlined, so it never reads as the current place, which
                    // the rail marks with a solid fill.
                    AppButton(
                      icon: AppIcons.plus,
                      style: AppButtonStyle.accent,
                      tooltip: 'Create something new (N)',
                      onTap: () => _openNew(root),
                    ),
                  ],
                ),
              ),
              destinations: [
                for (final d in shown)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    label: Text(d.label),
                  ),
              ],
            ),
          VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
          Expanded(
            child: Scaffold(
              appBar: AppBar(
                titleSpacing: AppSpacing.screenH(context),
                title: _title(root),
                actions: [
                  _slot(ShellSlots.action),
                  if (!sidebar) const _NotificationBell(),
                  // The sidebar carries its own search, so it is not repeated.
                  // A mid-sized window keeps the bar's room for the title and
                  // the page's action, and searches from an icon.
                  if (!sidebar && !roomForSearchField)
                    AppButton(
                      icon: AppIcons.search,
                      style: AppButtonStyle.ghost,
                      tooltip: 'Search or paste a link',
                      onTap: () => openLinkSearchSheet(context),
                    ),
                  if (!sidebar && roomForSearchField)
                    Padding(
                      padding: EdgeInsets.only(left: AppSpacing.xs),
                      child: SizedBox(
                        // Shrinks on a narrow rail so the title keeps room.
                        width: (MediaQuery.sizeOf(context).width * 0.3).clamp(
                          160,
                          _searchTriggerWidth,
                        ),
                        child: _SearchField(),
                      ),
                    ),
                  if (pageAction case final action?)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.xs),
                      // Always labelled: an unlabelled "+" here read as the
                      // rail's own New, which creates anything.
                      child: AppButton(
                        icon: action.icon,
                        label: action.label,
                        tooltip: action.label,
                        size: AppButtonSize.small,
                        onTap: () => action.start(context),
                      ),
                    ),
                  SizedBox(width: AppSpacing.screenH(context)),
                ],
              ),
              body: _body(path),
            ),
          ),
        ],
      ),
    );
  }
}

/// The wide layout's navigation: the workspace and account on top, search,
/// the destinations, and notifications and settings at the bottom.
class _Sidebar extends StatelessWidget {
  final List<_Destination> shown;
  final int? destination;
  final ValueChanged<int> onSelect;
  final VoidCallback onNew;

  const _Sidebar({
    required this.shown,
    required this.destination,
    required this.onSelect,
    required this.onNew,
  });

  /// The places as a tree: what is built on the vault hangs under it on a
  /// hairline, and what is not (attestations belong to identities, not
  /// records) stands apart after a gap.
  List<Widget> _navigation(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget item(int i) => _SidebarItem(
      icon: shown[i].icon,
      label: shown[i].label,
      selected: destination == i,
      onTap: () => onSelect(i),
    );
    final children = <Widget>[];
    for (var i = 0; i < shown.length; i++) {
      if (shown[i].underVault) continue;
      if (i > 0 && shown[i - 1].underVault) {
        children.add(AppSpacing.gapMd);
      }
      children.add(item(i));
      final nested = <int>[];
      for (var j = i + 1; j < shown.length && shown[j].underVault; j++) {
        nested.add(j);
      }
      if (nested.isEmpty) continue;
      children.add(
        Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpacing.xl),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final j in nested) item(j)],
              ),
            ),
          ),
        ),
      );
    }
    return children;
  }

  static const double width = 256;

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final onSettings = path.startsWith(AppRoutes.settings);
    final onNotifications = path.startsWith(AppRoutes.notifications);
    return SizedBox(
      width: width,
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AccountMenu(expanded: true),
              AppSpacing.gapSm,
              AppButton(
                size: .small,
                style: .accent,
                icon: AppIcons.plus,
                label: 'New',
                tooltip: 'Create something new (N)',
                onTap: onNew,
              ),
              AppSpacing.gapXs,
              const _SearchField(),
              AppSpacing.gapMd,
              Semantics(
                container: true,
                explicitChildNodes: true,
                label: 'Main navigation',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _navigation(context),
                ),
              ),
              const Spacer(),
              Observer(
                builder: (context) {
                  final unread = Stores.notifications.unreadCount;
                  return _SidebarItem(
                    icon: AppIcons.bell,
                    label: 'Notifications',
                    selected: onNotifications,
                    semanticsLabel: unread > 0
                        ? 'Notifications, $unread unread'
                        : 'Notifications',
                    trailing: unread > 0
                        ? AppBadge(
                            label: '$unread',
                            variant: AppBadgeVariant.primary,
                          )
                        : null,
                    onTap: () => context.go(AppRoutes.notifications),
                  );
                },
              ),
              _SidebarItem(
                icon: AppIcons.personGear,
                label: 'Settings',
                selected: onSettings,
                onTap: () => context.go(AppRoutes.settings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The narrowest window whose rail layout keeps the search field in the top
/// bar; below it the field becomes an icon.
const double _searchFieldMinWindow = 900;

/// How much room the trigger takes in a top bar — enough for the hint, but
/// not so much that it crowds the bar on a mid-sized window.
const double _searchTriggerWidth = 240;

/// Opens the search and link drawer. `/` and Ctrl+K open it too.
class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    return AppSearchTrigger(
      hint: 'Search or paste link',
      onTap: () => openLinkSearchSheet(context),
      trailing: const AppKeyHint('/'),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? semanticsLabel;
  final bool selected;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticsLabel,
    this.selected = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    final text = AppText(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Semantics(
        button: true,
        selected: selected,
        label: semanticsLabel ?? label,
        excludeSemantics: true,
        child: AppFocusRing(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadius.allMd,
              child: Container(
                height: AppSpacing.minTarget,
                padding: const EdgeInsets.only(right: AppSpacing.md),
                decoration: BoxDecoration(
                  color: selected ? scheme.secondaryContainer : null,
                  borderRadius: AppRadius.allMd,
                ),
                child: Row(
                  children: [
                    // The current place is marked by more than a tint: an
                    // ink bar, the bold label and the darker icon.
                    Container(
                      width: 3,
                      height: AppSpacing.xl,
                      color: selected ? scheme.primary : Colors.transparent,
                    ),
                    const SizedBox(width: AppSpacing.md - 3),
                    Icon(icon, size: 20, color: foreground),
                    AppSpacing.gapMd,
                    Expanded(child: selected ? text.bold : text),
                    ?trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Top-bar notifications bell with an unread dot, on layouts without the
/// sidebar.
class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Observer(
      builder: (_) {
        final unread = Stores.notifications.unreadCount;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            AppButton(
              icon: AppIcons.bell,
              style: AppButtonStyle.ghost,
              tooltip: unread > 0
                  ? 'Notifications, $unread unread'
                  : 'Notifications',
              onTap: () => context.go(AppRoutes.notifications),
            ),
            if (unread > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
