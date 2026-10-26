import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';

import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/radius.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_avatar.dart';
import 'package:revoked_app/core/widgets/app_menu_button.dart';
import 'package:revoked_app/features/settings/view/settings_pages.dart';
import 'package:revoked_app/features/settings/view/settings_screen.dart';
import 'package:revoked_app/core/widgets/app_focus_ring.dart';

/// The workspace switcher and everything about the account, in one menu.
///
/// Settings is no longer a tab: its topics are reached from here, and the
/// full list sits behind "All settings". [expanded] draws the sidebar's
/// header (workspace name and email); otherwise it is an avatar for a top
/// bar or rail.
class AccountMenu extends StatefulWidget {
  final bool expanded;

  const AccountMenu({super.key, this.expanded = false});

  @override
  State<AccountMenu> createState() => _AccountMenuState();
}

class _AccountMenuState extends State<AccountMenu> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoaded());
  }

  void _ensureLoaded() {
    final auth = Stores.auth;
    final settings = Stores.settings;
    if (auth.isAuthenticated && settings.workspaces.isEmpty) {
      settings.loadWorkspaces(auth.userId);
    }
  }

  String _workspaceName(String? id) {
    if (id == null || id.isEmpty) return 'Personal';
    for (final w in Stores.settings.workspaces) {
      if (w.id == id) return w.name;
    }
    return 'Workspace';
  }

  Future<void> _switch(String wsId) async {
    final auth = Stores.auth;
    if (wsId == auth.activeWorkspace) return;
    await Stores.workspaceContext.switchTo(
      userId: auth.userId,
      workspaceId: wsId,
    );
  }

  List<AppMenuItem?> _items(BuildContext context, String? activeId) {
    final spaces = Stores.settings.workspaces;
    return [
      for (final w in spaces)
        AppMenuItem(
          label: w.name,
          checked: w.id == activeId,
          onSelected: () => _switch(w.id),
        ),
      AppMenuItem(
        label: 'Manage workspaces',
        icon: AppIcons.personWorkspace,
        onSelected: () => context.go(AppRoutes.settingsWorkspace),
      ),
      null,
      AppMenuItem(
        label: 'Identities',
        icon: AppIcons.personBoundingBox,
        onSelected: () => context.go(SettingsPage.identities.route),
      ),
      AppMenuItem(
        label: 'Sign-in and passkeys',
        icon: AppIcons.key,
        onSelected: () => context.go(SettingsPage.passkeys.route),
      ),
      AppMenuItem(
        label: 'Connected tools',
        icon: AppIcons.plug,
        onSelected: () => context.go(AppRoutes.connectedTools),
      ),
      AppMenuItem(
        label: 'API keys',
        icon: AppIcons.code,
        onSelected: () => context.go(AppRoutes.apiKeys),
      ),
      AppMenuItem(
        label: 'Appearance and accessibility',
        icon: AppIcons.brightnessAuto,
        onSelected: () => context.go(SettingsPage.appearance.route),
      ),
      AppMenuItem(
        label: 'All settings',
        icon: AppIcons.personGear,
        onSelected: () => context.go(AppRoutes.settings),
      ),
      null,
      AppMenuItem(
        label: 'Log out',
        icon: AppIcons.boxArrowLeft,
        onSelected: () => confirmLogout(context),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final activeId = Stores.auth.activeWorkspace;
        final workspace = _workspaceName(activeId);
        final email = Stores.auth.userEmail;
        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Signed in as').muted.small,
            AppSpacing.gapXxs,
            Text(
              email.isEmpty ? '—' : email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ).small,
          ],
        );
        final items = _items(context, activeId);
        const tooltip = 'Workspace and account';

        if (!widget.expanded) {
          return AppMenuButton.avatar(
            avatarSource: workspace,
            tooltip: tooltip,
            header: header,
            onOpen: _ensureLoaded,
            items: items,
          );
        }
        return AppMenuButton.custom(
          tooltip: tooltip,
          header: header,
          onOpen: _ensureLoaded,
          items: items,
          triggerBuilder: (context, toggle) => _ExpandedTrigger(
            workspace: workspace,
            email: email,
            onTap: toggle,
          ),
        );
      },
    );
  }
}

/// The sidebar header: which workspace is open and who is signed in.
class _ExpandedTrigger extends StatelessWidget {
  final String workspace;
  final String email;
  final VoidCallback onTap;

  const _ExpandedTrigger({
    required this.workspace,
    required this.email,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Workspace $workspace, account menu',
      excludeSemantics: true,
      child: AppFocusRing(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.allMd,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  AppAvatar(source: workspace),
                  AppSpacing.gapSm,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppText(
                          workspace,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ).bold,
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ).small.muted,
                      ],
                    ),
                  ),
                  Icon(
                    AppIcons.chevronDown,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
