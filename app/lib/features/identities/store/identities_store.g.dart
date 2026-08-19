// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'identities_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$IdentitiesStore on _IdentitiesStore, Store {
  Computed<Identity?>? _$primaryIdentityComputed;

  @override
  Identity? get primaryIdentity =>
      (_$primaryIdentityComputed ??= Computed<Identity?>(
        () => super.primaryIdentity,
        name: '_IdentitiesStore.primaryIdentity',
      )).value;

  late final _$isLoadingAtom = Atom(
    name: '_IdentitiesStore.isLoading',
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
    name: '_IdentitiesStore.errorMessage',
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

  late final _$loadIdentitiesAsyncAction = AsyncAction(
    '_IdentitiesStore.loadIdentities',
    context: context,
  );

  @override
  Future<void> loadIdentities() {
    return _$loadIdentitiesAsyncAction.run(() => super.loadIdentities());
  }

  late final _$createIdentityAsyncAction = AsyncAction(
    '_IdentitiesStore.createIdentity',
    context: context,
  );

  @override
  Future<bool> createIdentity({required String name, bool isPrimary = false}) {
    return _$createIdentityAsyncAction.run(
      () => super.createIdentity(name: name, isPrimary: isPrimary),
    );
  }

  late final _$updateIdentityAsyncAction = AsyncAction(
    '_IdentitiesStore.updateIdentity',
    context: context,
  );

  @override
  Future<bool> updateIdentity(String id, {String? name}) {
    return _$updateIdentityAsyncAction.run(
      () => super.updateIdentity(id, name: name),
    );
  }

  late final _$deleteIdentityAsyncAction = AsyncAction(
    '_IdentitiesStore.deleteIdentity',
    context: context,
  );

  @override
  Future<void> deleteIdentity(String id) {
    return _$deleteIdentityAsyncAction.run(() => super.deleteIdentity(id));
  }

  late final _$_IdentitiesStoreActionController = ActionController(
    name: '_IdentitiesStore',
    context: context,
  );

  @override
  void togglePrimary(String id) {
    final _$actionInfo = _$_IdentitiesStoreActionController.startAction(
      name: '_IdentitiesStore.togglePrimary',
    );
    try {
      return super.togglePrimary(id);
    } finally {
      _$_IdentitiesStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
isLoading: ${isLoading},
errorMessage: ${errorMessage},
primaryIdentity: ${primaryIdentity}
    ''';
  }
}
