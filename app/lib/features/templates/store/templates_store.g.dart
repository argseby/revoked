// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'templates_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$TemplatesStore on _TemplatesStore, Store {
  late final _$isLoadingAtom = Atom(
    name: '_TemplatesStore.isLoading',
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
    name: '_TemplatesStore.errorMessage',
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

  late final _$loadTemplatesAsyncAction = AsyncAction(
    '_TemplatesStore.loadTemplates',
    context: context,
  );

  @override
  Future<void> loadTemplates(String workspaceId) {
    return _$loadTemplatesAsyncAction.run(
      () => super.loadTemplates(workspaceId),
    );
  }

  late final _$createTemplateAsyncAction = AsyncAction(
    '_TemplatesStore.createTemplate',
    context: context,
  );

  @override
  Future<bool> createTemplate({
    required String name,
    required Map<String, dynamic> schema,
    required String workspaceId,
  }) {
    return _$createTemplateAsyncAction.run(
      () => super.createTemplate(
        name: name,
        schema: schema,
        workspaceId: workspaceId,
      ),
    );
  }

  late final _$updateTemplateAsyncAction = AsyncAction(
    '_TemplatesStore.updateTemplate',
    context: context,
  );

  @override
  Future<bool> updateTemplate(
    String id, {
    required String name,
    required Map<String, dynamic> schema,
  }) {
    return _$updateTemplateAsyncAction.run(
      () => super.updateTemplate(id, name: name, schema: schema),
    );
  }

  late final _$deleteTemplateAsyncAction = AsyncAction(
    '_TemplatesStore.deleteTemplate',
    context: context,
  );

  @override
  Future<bool> deleteTemplate(String id) {
    return _$deleteTemplateAsyncAction.run(() => super.deleteTemplate(id));
  }

  late final _$_TemplatesStoreActionController = ActionController(
    name: '_TemplatesStore',
    context: context,
  );

  @override
  void clearError() {
    final _$actionInfo = _$_TemplatesStoreActionController.startAction(
      name: '_TemplatesStore.clearError',
    );
    try {
      return super.clearError();
    } finally {
      _$_TemplatesStoreActionController.endAction(_$actionInfo);
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
