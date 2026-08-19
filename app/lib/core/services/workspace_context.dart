import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/stores.dart';

/// Moves the app from one workspace to another.
///
/// Every feature store holds rows scoped to a single workspace, and the API
/// filters by the caller's active workspace. Changing that server-side without
/// refreshing the stores leaves the vault, shares and requests showing the
/// previous workspace's data, so the switch is only complete once the stores
/// have been emptied and reloaded — which is why this lives in one place rather
/// than at each call site.
class WorkspaceContext {
  const WorkspaceContext();

  /// Switches the active workspace and reloads everything scoped to it.
  /// Returns false when the server refused the switch, leaving state untouched.
  Future<bool> switchTo({
    required String userId,
    required String workspaceId,
  }) async {
    final ok = await Stores.settings.switchWorkspace(userId, workspaceId);
    if (!ok) return false;

    // Refresh the session first: the reloads below authenticate against the
    // new active workspace, so a stale cached user would refetch the old one.
    await Stores.auth.initialize();
    await reload();
    return true;
  }

  /// Clears and refetches every workspace-scoped store. Also used after
  /// accepting an invite, which lands the account in a different workspace.
  Future<void> reload() async {
    _clear();

    final workspaceId = Stores.auth.activeWorkspace ?? '';
    await Future.wait([
      Stores.vault.loadRecords(),
      Stores.shares.loadShares(),
      Stores.requests.loadRequests(),
      Stores.identities.loadIdentities(),
      if (workspaceId.isNotEmpty) Stores.templates.loadTemplates(workspaceId),
      if (workspaceId.isNotEmpty) Stores.invites.load(workspaceId),
      if (workspaceId.isNotEmpty) Stores.invites.loadMembers(workspaceId),
    ]);
  }

  /// Empties the stores before refetching, so a failed reload shows nothing
  /// rather than the previous workspace's rows.
  void _clear() {
    runInAction(() {
      Stores.vault.records.clear();
      Stores.vault.sections.clear();
      Stores.shares.shares.clear();
      Stores.requests.requests.clear();
      Stores.requests.responsesByRequest.clear();
      Stores.templates.templates.clear();
      Stores.identities.identities.clear();
      Stores.invites.invites.clear();
      Stores.invites.members.clear();
    });
  }
}
