import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/widgets/trust_panel.dart' show TrustCheckState;

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/workspace.dart';
import 'package:revoked_app/core/models/workspace_member.dart';
import 'package:revoked_app/core/network/api_client.dart';

part 'settings_store.g.dart';

/// The account's workspaces and memberships.
// ignore: library_private_types_in_public_api
class SettingsStore = _SettingsStore with _$SettingsStore;

abstract class _SettingsStore with Store {
  final ApiClient _api;

  _SettingsStore(this._api);

  final ObservableList<Workspace> workspaces = ObservableList<Workspace>();
  final ObservableList<WorkspaceMember> memberships =
      ObservableList<WorkspaceMember>();

  @observable
  bool isCheckingDomain = false;

  @observable
  TrustVerdict? domainVerdict;

  @observable
  String? domainError;

  @action
  void startDomainCheck() {
    isCheckingDomain = true;
    domainVerdict = null;
    domainError = null;
  }

  @action
  void finishDomainCheck({TrustVerdict? verdict, String? error}) {
    isCheckingDomain = false;
    domainVerdict = verdict;
    domainError = error;
  }

  /// Runs [checkDomain] unless it already ran or is running. Every screen
  /// that states an identity's domain claim calls this: without an answer
  /// the claim reads as unverified, which is wrong rather than unknown.
  void ensureDomainChecked() {
    if (domainVerdict != null || domainError != null || isCheckingDomain) {
      return;
    }
    checkDomain();
  }

  /// Whether this server's own DNS check vouches for [domain], the domain an
  /// identity was issued under.
  TrustCheckState claimStateFor(String domain) {
    final verdict = domainVerdict;
    if (verdict == null) {
      return isCheckingDomain || domainError == null
          ? TrustCheckState.checking
          : TrustCheckState.failed;
    }
    final same =
        verdict.domain.toLowerCase().replaceAll(RegExp(r'\.$'), '') ==
        domain.toLowerCase().replaceAll(RegExp(r'\.$'), '');
    return verdict.state == TrustState.verified && same
        ? TrustCheckState.verified
        : TrustCheckState.failed;
  }

  /// Runs the server-side DNS trust check (`/api/verify-peer` against this
  /// server's own advertised domain): whether its `_revoked` TXT record is
  /// published and pins its root key.
  Future<void> checkDomain() async {
    final store = this;
    store.startDomainCheck();
    try {
      final server = await _api.get('/api/server');
      final domain = (server is Map && server['domain'] is String)
          ? server['domain'] as String
          : '';
      if (domain.isEmpty) {
        store.finishDomainCheck(
          error:
              'This server has no domain to check. Ask whoever runs it to set one.',
        );
        return;
      }
      final res = await _api.post('/api/verify-peer', body: {'domain': domain});
      store.finishDomainCheck(
        verdict: _verdictFrom(res as Map<String, dynamic>),
      );
    } catch (e) {
      store.finishDomainCheck(error: e.toString());
    }
  }

  TrustVerdict _verdictFrom(Map<String, dynamic> r) {
    final domain = r['domain'] as String? ?? '';
    final reason = r['reason'] as String? ?? '';
    switch (r['state'] as String? ?? 'unverified') {
      case 'verified':
        return TrustVerdict.verified(
          domain: domain,
          rootFingerprint: r['rootFingerprint'] as String? ?? '',
          identityFingerprint: r['identityFingerprint'] as String? ?? '',
        );
      case 'spoofed':
        return TrustVerdict.spoofed(domain: domain, reason: reason);
      case 'dnsMissing':
        return TrustVerdict.dnsMissing(domain: domain, reason: reason);
      default:
        return TrustVerdict.unverified(domain: domain, reason: reason);
    }
  }

  final ObservableTextController workspaceName = ObservableTextController();
  final ObservableTextController workspaceSlug = ObservableTextController();
  final ObservableTextController identityName = ObservableTextController();

  @observable
  bool identityIsPrimary = false;

  @observable
  bool isSubmittingDrawer = false;

  @action
  void setIdentityPrimary(bool value) => identityIsPrimary = value;

  @action
  void setSubmitting(bool value) => isSubmittingDrawer = value;

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  @action
  Future<void> loadWorkspaces(String userId) async {
    isLoading = true;
    errorMessage = null;
    try {
      final members = await _getUserMemberships(userId);
      final spaces = <Workspace>[];
      for (final m in members) {
        try {
          spaces.add(await _getWorkspace(m.workspace));
        } catch (_) {}
      }
      memberships
        ..clear()
        ..addAll(members);
      workspaces
        ..clear()
        ..addAll(spaces);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  String? getRoleForWorkspace(String? workspaceId) {
    if (workspaceId == null) return null;
    try {
      return memberships.firstWhere((m) => m.workspace == workspaceId).role;
    } catch (_) {
      return null;
    }
  }

  @action
  Future<bool> switchWorkspace(String userId, String workspaceId) async {
    isLoading = true;
    errorMessage = null;
    try {
      final role = getRoleForWorkspace(workspaceId) ?? 'member';
      await _api.patch(
        '/api/collections/${AppConfig.usersCollection}/records/$userId',
        body: {'activeWorkspace': workspaceId, 'activeRole': role},
      );
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  /// Whether this account may delete [workspaceId], asked of the catalogue
  /// rather than by matching scope strings here — the server stores grants
  /// expanded, and naming them back is the catalogue's job.
  bool canManageWorkspace(
    String workspaceId,
    List<InvitePermission> catalogue,
  ) {
    final granted = memberships
        .where((m) => m.workspace == workspaceId)
        .expand((m) => m.permissions)
        .toList();
    if (granted.isEmpty) return false;
    for (final permission in catalogue) {
      if (permission.key == 'settings:manage') {
        return permission.isSatisfiedBy(granted);
      }
    }
    return false;
  }

  /// Deletes a workspace and everything in it. The server tears down the
  /// contents and clears the active context of anyone pointing at it, so the
  /// caller reloads rather than patching the list in place.
  @action
  Future<bool> deleteWorkspace(String userId, String workspaceId) async {
    isDeletingWorkspace = true;
    errorMessage = null;
    try {
      await _api.delete(
        '/api/collections/${AppConfig.workspacesCollection}/records/$workspaceId',
      );
      await loadWorkspaces(userId);
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isDeletingWorkspace = false;
    }
  }

  @observable
  bool isDeletingWorkspace = false;

  @action
  Future<bool> createWorkspace({
    required String name,
    required String slug,
    required String userId,
  }) async {
    isLoading = true;
    errorMessage = null;
    try {
      final data = await _api.post(
        '/api/collections/${AppConfig.workspacesCollection}/records',
        body: {'name': name, 'slug': slug},
      );
      workspaces.add(Workspace.fromJson(data as Map<String, dynamic>));
      await loadWorkspaces(userId);
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  Future<List<WorkspaceMember>> _getUserMemberships(String userId) async {
    final data = await _api.get(
      '/api/collections/${AppConfig.workspaceMembersCollection}/records',
      queryParams: {'filter': 'user = "$userId"', 'sort': '-created'},
    );
    final items = (data['items'] as List<dynamic>?) ?? [];
    return items
        .map((e) => WorkspaceMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Workspace> _getWorkspace(String id) async {
    final data = await _api.get(
      '/api/collections/${AppConfig.workspacesCollection}/records/$id',
    );
    return Workspace.fromJson(data as Map<String, dynamic>);
  }
}
