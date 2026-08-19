import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/identity_controls.dart';
import 'package:revoked_app/features/notifications/view/notifications_sheet.dart';
import 'package:revoked_app/features/shell/view/link_search_sheet.dart';

class AppShell extends StatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // Notifications power the top-bar bell, which is visible on every screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Stores.notifications.load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith(AppRoutes.vault)) {
      _selectedIndex = 0;
    } else if (location.startsWith(AppRoutes.requestData) ||
        location.startsWith(AppRoutes.requestSheet)) {
      _selectedIndex = 2; // per-request data/sheet opened from Inbox
    } else if (location.startsWith(AppRoutes.data) ||
        location.startsWith(AppRoutes.shares)) {
      _selectedIndex = 1; // Connections (shares folded in)
    } else if (location.startsWith(AppRoutes.inbox)) {
      _selectedIndex = 2;
    } else if (location.startsWith(AppRoutes.settings)) {
      _selectedIndex = 3;
    }
  }

  void _onSelected(int index) {
    switch (index) {
      case 0:
        context.go(AppRoutes.vault);
      case 1:
        context.go(AppRoutes.data);
      case 2:
        context.go(AppRoutes.inbox);
      case 3:
        context.go(AppRoutes.settings);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Slim single-line bar: organization · search · notifications · account.
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: const Row(children: [WorkspaceChip()]),
        actions: const [
          _SearchButton(),
          AppSpacing.gapXs,
          _NotificationBell(),
          AppSpacing.gapXs,
          AccountButton(),
          SizedBox(width: AppSpacing.lg),
        ],
      ),
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onSelected,
        destinations: const [
          NavigationDestination(icon: Icon(AppIcons.safe), label: 'Vault'),
          NavigationDestination(icon: Icon(AppIcons.share), label: 'Share'),
          NavigationDestination(
            icon: Icon(AppIcons.inboxFill),
            label: 'Request',
          ),
          NavigationDestination(
            icon: Icon(AppIcons.personGear),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

/// Top-bar notifications bell with an unread dot. Lives in the global header so
/// every screen (not just Request) can reach notifications.
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
              tooltip: 'Notifications',
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

/// Top-bar search button. Opens the link drawer where a `revoked://` share or
/// request link can be pasted, then opened or verified (DNS + link security).
/// Replaces the always-visible field so the bar stays slim.
class _SearchButton extends StatelessWidget {
  const _SearchButton();

  @override
  Widget build(BuildContext context) {
    return AppButton(
      icon: AppIcons.search,
      style: AppButtonStyle.accent,
      tooltip: 'Open a link',
      onTap: () => openLinkSearchSheet(context),
    );
  }
}
