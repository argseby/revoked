// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$AuthStore on _AuthStore, Store {
  Computed<bool>? _$isAuthenticatedComputed;

  @override
  bool get isAuthenticated => (_$isAuthenticatedComputed ??= Computed<bool>(
    () => super.isAuthenticated,
    name: '_AuthStore.isAuthenticated',
  )).value;
  Computed<String>? _$userEmailComputed;

  @override
  String get userEmail => (_$userEmailComputed ??= Computed<String>(
    () => super.userEmail,
    name: '_AuthStore.userEmail',
  )).value;
  Computed<String>? _$userIdComputed;

  @override
  String get userId => (_$userIdComputed ??= Computed<String>(
    () => super.userId,
    name: '_AuthStore.userId',
  )).value;
  Computed<String?>? _$activeWorkspaceComputed;

  @override
  String? get activeWorkspace =>
      (_$activeWorkspaceComputed ??= Computed<String?>(
        () => super.activeWorkspace,
        name: '_AuthStore.activeWorkspace',
      )).value;

  late final _$currentUserAtom = Atom(
    name: '_AuthStore.currentUser',
    context: context,
  );

  @override
  User? get currentUser {
    _$currentUserAtom.reportRead();
    return super.currentUser;
  }

  @override
  set currentUser(User? value) {
    _$currentUserAtom.reportWrite(value, super.currentUser, () {
      super.currentUser = value;
    });
  }

  late final _$isLoadingAtom = Atom(
    name: '_AuthStore.isLoading',
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
    name: '_AuthStore.errorMessage',
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

  late final _$isInitializedAtom = Atom(
    name: '_AuthStore.isInitialized',
    context: context,
  );

  @override
  bool get isInitialized {
    _$isInitializedAtom.reportRead();
    return super.isInitialized;
  }

  @override
  set isInitialized(bool value) {
    _$isInitializedAtom.reportWrite(value, super.isInitialized, () {
      super.isInitialized = value;
    });
  }

  late final _$initializeAsyncAction = AsyncAction(
    '_AuthStore.initialize',
    context: context,
  );

  @override
  Future<void> initialize() {
    return _$initializeAsyncAction.run(() => super.initialize());
  }

  late final _$loginAsyncAction = AsyncAction(
    '_AuthStore.login',
    context: context,
  );

  @override
  Future<bool> login(String email, String password) {
    return _$loginAsyncAction.run(() => super.login(email, password));
  }

  late final _$registerAsyncAction = AsyncAction(
    '_AuthStore.register',
    context: context,
  );

  @override
  Future<bool> register(String email, String password, String passwordConfirm) {
    return _$registerAsyncAction.run(
      () => super.register(email, password, passwordConfirm),
    );
  }

  late final _$logoutAsyncAction = AsyncAction(
    '_AuthStore.logout',
    context: context,
  );

  @override
  Future<void> logout() {
    return _$logoutAsyncAction.run(() => super.logout());
  }

  late final _$handleSessionExpiredAsyncAction = AsyncAction(
    '_AuthStore.handleSessionExpired',
    context: context,
  );

  @override
  Future<void> handleSessionExpired() {
    return _$handleSessionExpiredAsyncAction.run(
      () => super.handleSessionExpired(),
    );
  }

  late final _$_AuthStoreActionController = ActionController(
    name: '_AuthStore',
    context: context,
  );

  @override
  void clearError() {
    final _$actionInfo = _$_AuthStoreActionController.startAction(
      name: '_AuthStore.clearError',
    );
    try {
      return super.clearError();
    } finally {
      _$_AuthStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
currentUser: ${currentUser},
isLoading: ${isLoading},
errorMessage: ${errorMessage},
isInitialized: ${isInitialized},
isAuthenticated: ${isAuthenticated},
userEmail: ${userEmail},
userId: ${userId},
activeWorkspace: ${activeWorkspace}
    ''';
  }
}
