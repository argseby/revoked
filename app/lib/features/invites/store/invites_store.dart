import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';

part 'invites_store.g.dart';

/// Workspace invites and the member roster.
// ignore: library_private_types_in_public_api
class InvitesStore = _InvitesStore with _$InvitesStore;

abstract class _InvitesStore with Store {
  final ApiClient _api;

  _InvitesStore(this._api);

  String get _basePath =>
      '/api/collections/${AppConfig.invitesCollection}/records';

  final ObservableList<Invite> invites = ObservableList<Invite>();
  final ObservableList<InvitePermission> catalogue =
      ObservableList<InvitePermission>();
  final ObservableList<WorkspaceMemberDetail> members =
      ObservableList<WorkspaceMemberDetail>();
  final ObservableList<InvitePermission> grantable =
      ObservableList<InvitePermission>();

  Future<void>? _catalogueRequest;

  @observable
  bool isLoading = false;

  @observable
  AppErrorMessage? error;

  /// The token of the invite just created. Shown once, then cleared — the
  /// server keeps only a hash, so it cannot be retrieved again.
  @observable
  String? lastCreatedToken;

  @observable
  bool canManageMembers = false;

  @observable
  bool isLoadingMembers = false;

  /// Set when the member listing itself failed, so the UI can say so instead
  /// of showing an empty list or spinning forever.
  @observable
  AppErrorMessage? membersError;

  @action
  Future<void> loadCatalogue() async {
    if (catalogue.isNotEmpty) return;
    // The emptiness check alone is not a guard: several screens ask for the
    // catalogue as they mount, and each of them cleared it before the first
    // response arrived. Share the in-flight request instead.
    final inFlight = _catalogueRequest;
    if (inFlight != null) return inFlight;
    final request = _fetchCatalogue();
    _catalogueRequest = request;
    try {
      await request;
    } finally {
      _catalogueRequest = null;
    }
  }

  Future<void> _fetchCatalogue() async {
    try {
      final data = await _api.get('/api/permissions');
      final items =
          ((data as Map<String, dynamic>)['permissions'] as List<dynamic>?) ??
          [];
      catalogue
        ..clear()
        ..addAll(
          items.map(
            (e) => InvitePermission.fromJson(e as Map<String, dynamic>),
          ),
        );
    } catch (e) {
      error = AppErrorMessage.fromException(e);
    }
  }

  @action
  Future<void> load(String workspaceId) async {
    isLoading = true;
    error = null;
    try {
      final data = await _api.get(
        _basePath,
        queryParams: {
          'filter': 'workspace = "$workspaceId"',
          'sort': '-created',
          'perPage': '100',
        },
      );
      final items = (data['items'] as List<dynamic>?) ?? [];
      invites
        ..clear()
        ..addAll(items.map((e) => Invite.fromJson(e as Map<String, dynamic>)));
    } catch (e) {
      error = AppErrorMessage.fromException(e);
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<void> loadMembers(String workspaceId) async {
    isLoadingMembers = true;
    membersError = null;
    try {
      final data = await _api.get('/api/workspaces/$workspaceId/members');
      final result = WorkspaceMembers.fromJson(data as Map<String, dynamic>);
      members
        ..clear()
        ..addAll(result.members);
      grantable
        ..clear()
        ..addAll(result.grantable);
      canManageMembers = result.canManage;
    } catch (e) {
      membersError = AppErrorMessage.fromException(e);
    } finally {
      isLoadingMembers = false;
    }
  }

  @action
  Future<bool> create({
    required String workspace,
    required String label,
    required List<String> permissions,
    String? email,
    String? expiresAt,
    int? maxUses,
  }) async {
    isLoading = true;
    error = null;
    lastCreatedToken = null;
    try {
      final response = await _api.postWithHeaders(
        _basePath,
        body: {
          'workspace': workspace,
          'label': label,
          'permissions': permissions,
          'status': 'active',
          if (email != null && email.isNotEmpty) 'email': email,
          if (expiresAt != null && expiresAt.isNotEmpty) 'expiresAt': expiresAt,
          if (maxUses != null && maxUses > 0) 'maxUses': maxUses,
        },
      );
      final token =
          response.headers['x-invite-token'] ??
          response.headers['X-Invite-Token'];
      final invite = Invite.fromJson(
        response.body as Map<String, dynamic>,
        plainToken: token,
      );
      invites.insert(0, invite);
      lastCreatedToken = invite.plainToken;
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    } finally {
      isLoading = false;
    }
  }

  /// Withdraws without deleting, so the record of who was offered access stays.
  @action
  Future<bool> revoke(String id) async {
    try {
      await _api.patch('$_basePath/$id', body: {'status': 'revoked'});
      final idx = invites.indexWhere((i) => i.id == id);
      if (idx != -1) {
        final old = invites[idx];
        invites[idx] = Invite(
          id: old.id,
          workspace: old.workspace,
          label: old.label,
          status: 'revoked',
          permissions: old.permissions,
          email: old.email,
          expiresAt: old.expiresAt,
          maxUses: old.maxUses,
          useCount: old.useCount,
          created: old.created,
        );
      }
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    }
  }

  @action
  Future<bool> delete(String id) async {
    try {
      await _api.delete('$_basePath/$id');
      invites.removeWhere((i) => i.id == id);
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    }
  }

  @action
  Future<bool> updateMemberPermissions(
    String workspaceId,
    String memberId,
    List<String> permissions,
  ) async {
    try {
      await _api.patch(
        '/api/collections/${AppConfig.workspaceMembersCollection}/records/$memberId',
        body: {'permissions': permissions},
      );
      await loadMembers(workspaceId);
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    }
  }

  @action
  Future<bool> removeMember(String workspaceId, String memberId) async {
    try {
      await _api.delete(
        '/api/collections/${AppConfig.workspaceMembersCollection}/records/$memberId',
      );
      await loadMembers(workspaceId);
      return true;
    } catch (e) {
      error = AppErrorMessage.fromException(e);
      return false;
    }
  }

  /// Read what a token grants, without spending it.
  Future<InvitePreview> preview(String token) async {
    final data = await _api.get('/api/public/invites/$token');
    return InvitePreview.fromJson(data as Map<String, dynamic>);
  }

  /// Spend the token and join the workspace. Requires a signed-in account.
  Future<String> accept(String token) async {
    final data = await _api.post('/api/public/invites/$token');
    return (data as Map<String, dynamic>)['workspace'] as String? ?? '';
  }

  @action
  void clearToken() => lastCreatedToken = null;

  @action
  void clearError() => error = null;
}
