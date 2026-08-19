// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notifications_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$NotificationsStore on _NotificationsStore, Store {
  Computed<int>? _$unreadCountComputed;

  @override
  int get unreadCount => (_$unreadCountComputed ??= Computed<int>(
    () => super.unreadCount,
    name: '_NotificationsStore.unreadCount',
  )).value;

  late final _$isLoadingAtom = Atom(
    name: '_NotificationsStore.isLoading',
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
    name: '_NotificationsStore.errorMessage',
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

  late final _$loadAsyncAction = AsyncAction(
    '_NotificationsStore.load',
    context: context,
  );

  @override
  Future<void> load() {
    return _$loadAsyncAction.run(() => super.load());
  }

  late final _$markReadAsyncAction = AsyncAction(
    '_NotificationsStore.markRead',
    context: context,
  );

  @override
  Future<void> markRead(String id, {bool read = true}) {
    return _$markReadAsyncAction.run(() => super.markRead(id, read: read));
  }

  late final _$deleteAsyncAction = AsyncAction(
    '_NotificationsStore.delete',
    context: context,
  );

  @override
  Future<void> delete(String id) {
    return _$deleteAsyncAction.run(() => super.delete(id));
  }

  late final _$markAllReadAsyncAction = AsyncAction(
    '_NotificationsStore.markAllRead',
    context: context,
  );

  @override
  Future<void> markAllRead() {
    return _$markAllReadAsyncAction.run(() => super.markAllRead());
  }

  late final _$_NotificationsStoreActionController = ActionController(
    name: '_NotificationsStore',
    context: context,
  );

  @override
  void clearError() {
    final _$actionInfo = _$_NotificationsStoreActionController.startAction(
      name: '_NotificationsStore.clearError',
    );
    try {
      return super.clearError();
    } finally {
      _$_NotificationsStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
isLoading: ${isLoading},
errorMessage: ${errorMessage},
unreadCount: ${unreadCount}
    ''';
  }
}
