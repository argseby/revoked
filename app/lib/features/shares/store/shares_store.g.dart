// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shares_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$SharesStore on _SharesStore, Store {
  late final _$sharesAtom = Atom(name: '_SharesStore.shares', context: context);

  @override
  ObservableList<Link> get shares {
    _$sharesAtom.reportRead();
    return super.shares;
  }

  @override
  set shares(ObservableList<Link> value) {
    _$sharesAtom.reportWrite(value, super.shares, () {
      super.shares = value;
    });
  }

  late final _$isLoadingAtom = Atom(
    name: '_SharesStore.isLoading',
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
    name: '_SharesStore.errorMessage',
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

  late final _$loadSharesAsyncAction = AsyncAction(
    '_SharesStore.loadShares',
    context: context,
  );

  @override
  Future<void> loadShares() {
    return _$loadSharesAsyncAction.run(() => super.loadShares());
  }

  late final _$createShareAsyncAction = AsyncAction(
    '_SharesStore.createShare',
    context: context,
  );

  @override
  Future<bool> createShare({
    required String slug,
    required String label,
    required String user,
    required String workspace,
    required List<String> sections,
    required List<String> records,
    String status = 'active',
    String? identityId,
    String? password,
    DateTime? expiresAt,
    int? maxViews,
    bool requireHandshake = false,
  }) {
    return _$createShareAsyncAction.run(
      () => super.createShare(
        slug: slug,
        label: label,
        user: user,
        workspace: workspace,
        sections: sections,
        records: records,
        status: status,
        identityId: identityId,
        password: password,
        expiresAt: expiresAt,
        maxViews: maxViews,
        requireHandshake: requireHandshake,
      ),
    );
  }

  late final _$updateShareAsyncAction = AsyncAction(
    '_SharesStore.updateShare',
    context: context,
  );

  @override
  Future<bool> updateShare(String id, Map<String, dynamic> updates) {
    return _$updateShareAsyncAction.run(() => super.updateShare(id, updates));
  }

  late final _$deleteShareAsyncAction = AsyncAction(
    '_SharesStore.deleteShare',
    context: context,
  );

  @override
  Future<bool> deleteShare(String id) {
    return _$deleteShareAsyncAction.run(() => super.deleteShare(id));
  }

  late final _$_SharesStoreActionController = ActionController(
    name: '_SharesStore',
    context: context,
  );

  @override
  void clearError() {
    final _$actionInfo = _$_SharesStoreActionController.startAction(
      name: '_SharesStore.clearError',
    );
    try {
      return super.clearError();
    } finally {
      _$_SharesStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
shares: ${shares},
isLoading: ${isLoading},
errorMessage: ${errorMessage}
    ''';
  }
}
