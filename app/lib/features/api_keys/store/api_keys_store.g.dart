// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_keys_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$ApiKeysStore on _ApiKeysStore, Store {
  late final _$isLoadingAtom = Atom(
    name: '_ApiKeysStore.isLoading',
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
    name: '_ApiKeysStore.errorMessage',
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

  late final _$lastCreatedPlainTokenAtom = Atom(
    name: '_ApiKeysStore.lastCreatedPlainToken',
    context: context,
  );

  @override
  String? get lastCreatedPlainToken {
    _$lastCreatedPlainTokenAtom.reportRead();
    return super.lastCreatedPlainToken;
  }

  @override
  set lastCreatedPlainToken(String? value) {
    _$lastCreatedPlainTokenAtom.reportWrite(
      value,
      super.lastCreatedPlainToken,
      () {
        super.lastCreatedPlainToken = value;
      },
    );
  }

  late final _$loadApiKeysAsyncAction = AsyncAction(
    '_ApiKeysStore.loadApiKeys',
    context: context,
  );

  @override
  Future<void> loadApiKeys() {
    return _$loadApiKeysAsyncAction.run(() => super.loadApiKeys());
  }

  late final _$createApiKeyAsyncAction = AsyncAction(
    '_ApiKeysStore.createApiKey',
    context: context,
  );

  @override
  Future<bool> createApiKey({
    required String label,
    required String user,
    required String workspace,
    required List<String> scopes,
    String? expiresAt,
  }) {
    return _$createApiKeyAsyncAction.run(
      () => super.createApiKey(
        label: label,
        user: user,
        workspace: workspace,
        scopes: scopes,
        expiresAt: expiresAt,
      ),
    );
  }

  late final _$deleteApiKeyAsyncAction = AsyncAction(
    '_ApiKeysStore.deleteApiKey',
    context: context,
  );

  @override
  Future<void> deleteApiKey(String id) {
    return _$deleteApiKeyAsyncAction.run(() => super.deleteApiKey(id));
  }

  late final _$_ApiKeysStoreActionController = ActionController(
    name: '_ApiKeysStore',
    context: context,
  );

  @override
  void clearLastToken() {
    final _$actionInfo = _$_ApiKeysStoreActionController.startAction(
      name: '_ApiKeysStore.clearLastToken',
    );
    try {
      return super.clearLastToken();
    } finally {
      _$_ApiKeysStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
isLoading: ${isLoading},
errorMessage: ${errorMessage},
lastCreatedPlainToken: ${lastCreatedPlainToken}
    ''';
  }
}
