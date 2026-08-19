// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'requests_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$RequestsStore on _RequestsStore, Store {
  late final _$isLoadingAtom = Atom(
    name: '_RequestsStore.isLoading',
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
    name: '_RequestsStore.errorMessage',
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

  late final _$loadRequestsAsyncAction = AsyncAction(
    '_RequestsStore.loadRequests',
    context: context,
  );

  @override
  Future<void> loadRequests() {
    return _$loadRequestsAsyncAction.run(() => super.loadRequests());
  }

  late final _$loadResponsesAsyncAction = AsyncAction(
    '_RequestsStore.loadResponses',
    context: context,
  );

  @override
  Future<List<Map<String, dynamic>>> loadResponses(String requestId) {
    return _$loadResponsesAsyncAction.run(() => super.loadResponses(requestId));
  }

  late final _$createRequestAsyncAction = AsyncAction(
    '_RequestsStore.createRequest',
    context: context,
  );

  @override
  Future<bool> createRequest({
    required String slug,
    required String label,
    required String identityId,
    required String user,
    required String workspace,
    String? templateId,
    String? password,
    DateTime? expiresAt,
    int? maxResponses,
    String? identifier,
    String? callbackUrl,
    bool requireHandshake = false,
    String identityScope = 'any',
    bool allowExtraFields = false,
  }) {
    return _$createRequestAsyncAction.run(
      () => super.createRequest(
        slug: slug,
        label: label,
        identityId: identityId,
        user: user,
        workspace: workspace,
        templateId: templateId,
        password: password,
        expiresAt: expiresAt,
        maxResponses: maxResponses,
        identifier: identifier,
        callbackUrl: callbackUrl,
        requireHandshake: requireHandshake,
        identityScope: identityScope,
        allowExtraFields: allowExtraFields,
      ),
    );
  }

  late final _$updateRequestAsyncAction = AsyncAction(
    '_RequestsStore.updateRequest',
    context: context,
  );

  @override
  Future<bool> updateRequest(String id, Map<String, dynamic> body) {
    return _$updateRequestAsyncAction.run(() => super.updateRequest(id, body));
  }

  late final _$deleteRequestAsyncAction = AsyncAction(
    '_RequestsStore.deleteRequest',
    context: context,
  );

  @override
  Future<bool> deleteRequest(String id) {
    return _$deleteRequestAsyncAction.run(() => super.deleteRequest(id));
  }

  late final _$_RequestsStoreActionController = ActionController(
    name: '_RequestsStore',
    context: context,
  );

  @override
  void clearError() {
    final _$actionInfo = _$_RequestsStoreActionController.startAction(
      name: '_RequestsStore.clearError',
    );
    try {
      return super.clearError();
    } finally {
      _$_RequestsStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
isLoading: ${isLoading},
errorMessage: ${errorMessage}
    ''';
  }
}
