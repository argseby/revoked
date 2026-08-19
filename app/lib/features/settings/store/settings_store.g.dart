// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$SettingsStore on _SettingsStore, Store {
  late final _$isLoadingAtom = Atom(
    name: '_SettingsStore.isLoading',
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

  late final _$errorMessageAtom = Atom(
    name: '_SettingsStore.errorMessage',
    context: context,
  );

  @override
  String? get errorMessage {
    _$errorMessageAtom.reportRead();
    return super.errorMessage;
  }

  @override
  set errorMessage(String? value) {
    _$errorMessageAtom.reportWrite(value, super.errorMessage, () {
      super.errorMessage = value;
    });
  }

  late final _$loadWorkspacesAsyncAction = AsyncAction(
    '_SettingsStore.loadWorkspaces',
    context: context,
  );

  @override
  Future<void> loadWorkspaces(String userId) {
    return _$loadWorkspacesAsyncAction.run(() => super.loadWorkspaces(userId));
  }

  late final _$switchWorkspaceAsyncAction = AsyncAction(
    '_SettingsStore.switchWorkspace',
    context: context,
  );

  @override
  Future<bool> switchWorkspace(String userId, String workspaceId) {
    return _$switchWorkspaceAsyncAction.run(
      () => super.switchWorkspace(userId, workspaceId),
    );
  }

  late final _$createWorkspaceAsyncAction = AsyncAction(
    '_SettingsStore.createWorkspace',
    context: context,
  );

  @override
  Future<bool> createWorkspace({
    required String name,
    required String slug,
    required String userId,
  }) {
    return _$createWorkspaceAsyncAction.run(
      () => super.createWorkspace(name: name, slug: slug, userId: userId),
    );
  }

  @override
  String toString() {
    return '''
isLoading: ${isLoading},
errorMessage: ${errorMessage}
    ''';
  }
}
