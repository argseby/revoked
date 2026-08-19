// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$ThemeStore on _ThemeStore, Store {
  late final _$modeAtom = Atom(name: '_ThemeStore.mode', context: context);

  @override
  ThemeMode get mode {
    _$modeAtom.reportRead();
    return super.mode;
  }

  @override
  set mode(ThemeMode value) {
    _$modeAtom.reportWrite(value, super.mode, () {
      super.mode = value;
    });
  }

  late final _$loadAsyncAction = AsyncAction(
    '_ThemeStore.load',
    context: context,
  );

  @override
  Future<void> load() {
    return _$loadAsyncAction.run(() => super.load());
  }

  late final _$setModeAsyncAction = AsyncAction(
    '_ThemeStore.setMode',
    context: context,
  );

  @override
  Future<void> setMode(ThemeMode next) {
    return _$setModeAsyncAction.run(() => super.setMode(next));
  }

  @override
  String toString() {
    return '''
mode: ${mode}
    ''';
  }
}
