// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invites_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$InvitesStore on _InvitesStore, Store {
  late final _$isLoadingAtom = Atom(
    name: '_InvitesStore.isLoading',
    context: context,
  );

  @override
  bool get isLoading {
    _$isLoadingAtom.reportRead();
    return super.isLoading;
  }

  @override
  set isLoading(bool value) {
    _$isLoadingAtom.reportWrite(value, super.isLoading, () {
      super.isLoading = value;
    });
  }

  late final _$errorAtom = Atom(name: '_InvitesStore.error', context: context);

  @override
  AppErrorMessage? get error {
    _$errorAtom.reportRead();
    return super.error;
  }

  @override
  set error(AppErrorMessage? value) {
    _$errorAtom.reportWrite(value, super.error, () {
      super.error = value;
    });
  }

  late final _$lastCreatedTokenAtom = Atom(
    name: '_InvitesStore.lastCreatedToken',
    context: context,
  );

  @override
  String? get lastCreatedToken {
    _$lastCreatedTokenAtom.reportRead();
    return super.lastCreatedToken;
  }

  @override
  set lastCreatedToken(String? value) {
    _$lastCreatedTokenAtom.reportWrite(value, super.lastCreatedToken, () {
      super.lastCreatedToken = value;
    });
  }

  late final _$canManageMembersAtom = Atom(
    name: '_InvitesStore.canManageMembers',
    context: context,
  );

  @override
  bool get canManageMembers {
    _$canManageMembersAtom.reportRead();
    return super.canManageMembers;
  }

  @override
  set canManageMembers(bool value) {
    _$canManageMembersAtom.reportWrite(value, super.canManageMembers, () {
      super.canManageMembers = value;
    });
  }

  late final _$isLoadingMembersAtom = Atom(
    name: '_InvitesStore.isLoadingMembers',
    context: context,
  );

  @override
  bool get isLoadingMembers {
    _$isLoadingMembersAtom.reportRead();
    return super.isLoadingMembers;
  }

  @override
  set isLoadingMembers(bool value) {
    _$isLoadingMembersAtom.reportWrite(value, super.isLoadingMembers, () {
      super.isLoadingMembers = value;
    });
  }

  late final _$membersErrorAtom = Atom(
    name: '_InvitesStore.membersError',
    context: context,
  );

  @override
  AppErrorMessage? get membersError {
    _$membersErrorAtom.reportRead();
    return super.membersError;
  }

  @override
  set membersError(AppErrorMessage? value) {
    _$membersErrorAtom.reportWrite(value, super.membersError, () {
      super.membersError = value;
    });
  }

  late final _$loadCatalogueAsyncAction = AsyncAction(
    '_InvitesStore.loadCatalogue',
    context: context,
  );

  @override
  Future<void> loadCatalogue() {
    return _$loadCatalogueAsyncAction.run(() => super.loadCatalogue());
  }

  late final _$loadAsyncAction = AsyncAction(
    '_InvitesStore.load',
    context: context,
  );

  @override
  Future<void> load(String workspaceId) {
    return _$loadAsyncAction.run(() => super.load(workspaceId));
  }

  late final _$loadMembersAsyncAction = AsyncAction(
    '_InvitesStore.loadMembers',
    context: context,
  );

  @override
  Future<void> loadMembers(String workspaceId) {
    return _$loadMembersAsyncAction.run(() => super.loadMembers(workspaceId));
  }

  late final _$createAsyncAction = AsyncAction(
    '_InvitesStore.create',
    context: context,
  );

  @override
  Future<bool> create({
    required String workspace,
    required String label,
    required List<String> permissions,
    String? email,
    String? expiresAt,
    int? maxUses,
  }) {
    return _$createAsyncAction.run(
      () => super.create(
        workspace: workspace,
        label: label,
        permissions: permissions,
        email: email,
        expiresAt: expiresAt,
        maxUses: maxUses,
      ),
    );
  }

  late final _$revokeAsyncAction = AsyncAction(
    '_InvitesStore.revoke',
    context: context,
  );

  @override
  Future<bool> revoke(String id) {
    return _$revokeAsyncAction.run(() => super.revoke(id));
  }

  late final _$deleteAsyncAction = AsyncAction(
    '_InvitesStore.delete',
    context: context,
  );

  @override
  Future<bool> delete(String id) {
    return _$deleteAsyncAction.run(() => super.delete(id));
  }

  late final _$updateMemberPermissionsAsyncAction = AsyncAction(
    '_InvitesStore.updateMemberPermissions',
    context: context,
  );

  @override
  Future<bool> updateMemberPermissions(
    String workspaceId,
    String memberId,
    List<String> permissions,
  ) {
    return _$updateMemberPermissionsAsyncAction.run(
      () => super.updateMemberPermissions(workspaceId, memberId, permissions),
    );
  }

  late final _$removeMemberAsyncAction = AsyncAction(
    '_InvitesStore.removeMember',
    context: context,
  );

  @override
  Future<bool> removeMember(String workspaceId, String memberId) {
    return _$removeMemberAsyncAction.run(
      () => super.removeMember(workspaceId, memberId),
    );
  }

  late final _$_InvitesStoreActionController = ActionController(
    name: '_InvitesStore',
    context: context,
  );

  @override
  void clearToken() {
    final _$actionInfo = _$_InvitesStoreActionController.startAction(
      name: '_InvitesStore.clearToken',
    );
    try {
      return super.clearToken();
    } finally {
      _$_InvitesStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void clearError() {
    final _$actionInfo = _$_InvitesStoreActionController.startAction(
      name: '_InvitesStore.clearError',
    );
    try {
      return super.clearError();
    } finally {
      _$_InvitesStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
isLoading: ${isLoading},
error: ${error},
lastCreatedToken: ${lastCreatedToken},
canManageMembers: ${canManageMembers},
isLoadingMembers: ${isLoadingMembers},
membersError: ${membersError}
    ''';
  }
}
