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
import 'package:revoked_app/features/notifications/view/notifications_sheet.dart';
import 'package:revoked_app/features/shell/view/account_menu.dart';
import 'package:revoked_app/features/shell/view/link_search_sheet.dart';
import 'package:revoked_app/features/shell/view/new_picker.dart';

/// One of the shell's places, in the order of `AppRoutes.destinations`.
class _Destination {
  final IconData icon;
  final String label;

  const _Destination(this.icon, this.label);
}

const _destinations = [
  _Destination(AppIcons.dashboard, 'Overview'),
  _Destination(AppIcons.safe, 'Vault'),
  _Destination(AppIcons.share, 'Shared'),
  _Destination(AppIcons.inboxFill, 'Requests'),
  _Destination(AppIcons.attestation, 'Attestations'),
];

/// The frame around every signed-in screen.
///
/// The same destinations at every width: a bottom bar on a phone, a
/// rail on a mid-sized window and a sidebar on a wide one. One "New" button
/// opens the picker for everything that can be created; search and the
/// account menu are reachable from every layout.
class AppShell extends StatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// The destination last shown, so the bottom bar still has one to sit on
  /// while Settings is open.
  int _lastDestination = 0;

  @override
  void initState() {
    super.initState();
    // Notifications power the bell, which is visible on every screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Stores.notifications.load();
      Stores.notifications.startPolling();
    });
  }

  @override
  void dispose() {
    Stores.notifications.stopPolling();
    super.dispose();
  }

  void _go(int index) => context.go(AppRoutes.destinations[index]);

  void _openNew(int? destination) =>
      openNewPicker(context, destination: destination);

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

  /// The screen's own title, or the destination's name while it has none.
  Widget _title(int? destination) {
    final fallback = destination == null
        ? 'Settings'
        : _destinations[destination].label;
    return Observer(
      builder: (context) =>
          ShellSlots.title.builder?.call(context) ??
          AppBarTitle(title: fallback),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destination = AppRoutes.destinationOf(
      GoRouterState.of(context).uri.path,
    );
    if (destination != null) _lastDestination = destination;
    final width = MediaQuery.sizeOf(context).width;
    if (width < AppSpacing.narrowWidth) return _narrow(destination);
    return _wide(destination, sidebar: width >= AppSpacing.wideWidth);
  }

  Widget _narrow(int? destination) {
    return Scaffold(
      floatingActionButtonLocation: .endFloat,
      // Yields while any sheet is up, so it never overlaps a sheet's actions.
      floatingActionButton: Observer(
        builder: (_) {
          if (SheetTracker.anyOpen || destination == null) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            heroTag: 'shell-new',
            tooltip: 'Create something new',
            onPressed: () => _openNew(destination),
            icon: const Icon(AppIcons.plus),
            label: const Text('New'),
          );
        },
      ),
      appBar: AppBar(
        leadingWidth: AppSpacing.lg + AppButton.normalExtent + AppSpacing.xs,
        leading: const Padding(
          padding: EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.xs),
          child: Center(child: AccountMenu()),
        ),
        titleSpacing: AppSpacing.xs,
        title: _title(destination),
        actions: [
          _slot(ShellSlots.action),
          AppButton(
            icon: AppIcons.search,
            style: AppButtonStyle.accent,
            tooltip: 'Search or paste a link',
            onTap: () => openLinkSearchSheet(context),
          ),
          const _NotificationBell(),
          AppSpacing.gapXs,
        ],
      ),
      body: widget.child,
      bottomNavigationBar: _bottomBar(destination),
    );
  }

  Widget _bottomBar(int? destination) {
    final bar = NavigationBar(
      selectedIndex: destination ?? _lastDestination,
      onDestinationSelected: _go,
      destinations: [
        for (final d in _destinations)
          NavigationDestination(icon: Icon(d.icon), label: d.label),
      ],
    );
    if (destination != null) return bar;
    // On Settings none of the four is current, so none looks it.
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

  Widget _wide(int? destination, {required bool sidebar}) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sidebar)
            _Sidebar(destination: destination, onSelect: _go)
          else
            NavigationRail(
              selectedIndex: destination,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: AccountMenu(),
              ),
              destinations: [
                for (final d in _destinations)
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
                title: _title(destination),
                actions: [
                  _slot(ShellSlots.action),
                  if (!sidebar)
                    AppButton(
                      icon: AppIcons.search,
                      style: AppButtonStyle.accent,
                      tooltip: 'Search or paste a link',
                      onTap: () => openLinkSearchSheet(context),
                    ),
                  if (!sidebar) const _NotificationBell(),
                  // The one primary action, rightmost on every wide layout.
                  if (destination != null)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.xs),
                      child: AppButton(
                        icon: AppIcons.plus,
                        label: 'New',
                        tooltip: 'Create something new (N)',
                        onTap: () => _openNew(destination),
                      ),
                    ),
                  SizedBox(width: AppSpacing.screenH(context)),
                ],
              ),
              body: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

/// The wide layout's navigation: the workspace and account on top, search,
/// the four destinations, and notifications and settings at the bottom.
class _Sidebar extends StatelessWidget {
  final int? destination;
  final ValueChanged<int> onSelect;

  const _Sidebar({required this.destination, required this.onSelect});

  static const double width = 256;

  @override
  Widget build(BuildContext context) {
    final onSettings = GoRouterState.of(
      context,
    ).uri.path.startsWith(AppRoutes.settings);
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
              const _SearchField(),
              AppSpacing.gapMd,
              Semantics(
                container: true,
                explicitChildNodes: true,
                label: 'Main navigation',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _destinations.length; i++)
                      _SidebarItem(
                        icon: _destinations[i].icon,
                        label: _destinations[i].label,
                        selected: destination == i,
                        onTap: () => onSelect(i),
                      ),
                  ],
                ),
              ),
              const Spacer(),
              Observer(
                builder: (context) {
                  final unread = Stores.notifications.unreadCount;
                  return _SidebarItem(
                    icon: AppIcons.bell,
                    label: 'Notifications',
                    semanticsLabel: unread > 0
                        ? 'Notifications, $unread unread'
                        : 'Notifications',
                    trailing: unread > 0
                        ? AppBadge(
                            label: '$unread',
                            variant: AppBadgeVariant.primary,
                          )
                        : null,
                    onTap: () => openNotificationsSheet(context),
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

/// Opens the search and link drawer. `/` opens it too.
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
              style: AppButtonStyle.accent,
              tooltip: unread > 0
                  ? 'Notifications, $unread unread'
                  : 'Notifications',
              onTap: () => openNotificationsSheet(context),
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
