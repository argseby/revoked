import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/design/text_styles.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_menu_button.dart';

/// Compact chip showing the active organization (workspace) with a quick
/// switcher. Switching updates the backend and refreshes the session so the
/// active workspace — used for new requests/records — changes immediately.
///
/// Self-loads the user's workspaces, so it can be dropped anywhere (the shell
/// top bar, the public request screen, …).
class WorkspaceChip extends StatefulWidget {
  const WorkspaceChip({super.key});

  @override
  State<WorkspaceChip> createState() => _WorkspaceChipState();
}

class _WorkspaceChipState extends State<WorkspaceChip> {
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

  String _name(String? id) {
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

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final activeId = Stores.auth.activeWorkspace;
        final spaces = Stores.settings.workspaces;
        return AppMenuButton(
          icon: AppIcons.personWorkspace,
          label: _name(activeId),
          tooltip: 'Switch organization',
          size: AppButtonSize.small,
          onOpen: _ensureLoaded,
          items: [
            for (final w in spaces)
              AppMenuItem(
                label: w.name,
                checked: w.id == activeId,
                onSelected: () => _switch(w.id),
              ),
            if (spaces.isNotEmpty) null,
            AppMenuItem(
              label: 'Manage organizations',
              icon: AppIcons.personGear,
              onSelected: () => context.go(AppRoutes.settings),
            ),
          ],
        );
      },
    );
  }
}

/// Account avatar with a menu: shows the signed-in email, links to Settings,
/// and signs out (to fill a request as a different account, sign out and back
/// in).
class AccountButton extends StatelessWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final email = Stores.auth.userEmail;
        return AppMenuButton.avatar(
          avatarSource: email,
          tooltip: 'Account',
          header: Column(
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
          ),
          items: [
            AppMenuItem(
              label: 'Account & settings',
              icon: AppIcons.personGear,
              onSelected: () => context.go(AppRoutes.settings),
            ),
            AppMenuItem(
              label: 'Sign out',
              icon: AppIcons.boxArrowLeft,
              onSelected: Stores.auth.logout,
            ),
          ],
        );
      },
    );
  }
}
