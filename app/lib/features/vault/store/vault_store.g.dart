// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$VaultStore on _VaultStore, Store {
  Computed<int>? _$recordCountComputed;

  @override
  int get recordCount => (_$recordCountComputed ??= Computed<int>(
    () => super.recordCount,
    name: '_VaultStore.recordCount',
  )).value;

  late final _$recordsAtom = Atom(
    name: '_VaultStore.records',
    context: context,
  );

  @override
  ObservableList<models.Record> get records {
    _$recordsAtom.reportRead();
    return super.records;
  }

  @override
  set records(ObservableList<models.Record> value) {
    _$recordsAtom.reportWrite(value, super.records, () {
      super.records = value;
    });
  }

  late final _$sectionsAtom = Atom(
    name: '_VaultStore.sections',
    context: context,
  );

  @override
  ObservableList<Section> get sections {
    _$sectionsAtom.reportRead();
    return super.sections;
  }

  @override
  set sections(ObservableList<Section> value) {
    _$sectionsAtom.reportWrite(value, super.sections, () {
      super.sections = value;
    });
  }

  late final _$isLoadingAtom = Atom(
    name: '_VaultStore.isLoading',
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
    name: '_VaultStore.errorMessage',
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

  late final _$loadRecordsAsyncAction = AsyncAction(
    '_VaultStore.loadRecords',
    context: context,
  );

  @override
  Future<void> loadRecords() {
    return _$loadRecordsAsyncAction.run(() => super.loadRecords());
  }

  late final _$createRecordAsyncAction = AsyncAction(
    '_VaultStore.createRecord',
    context: context,
  );

  @override
  Future<bool> createRecord({
    required String key,
    required String value,
    required String label,
    required String type,
    required String format,
    required String user,
    required String workspace,
  }) {
    return _$createRecordAsyncAction.run(
      () => super.createRecord(
        key: key,
        value: value,
        label: label,
        type: type,
        format: format,
        user: user,
        workspace: workspace,
      ),
    );
  }

  late final _$deleteRecordAsyncAction = AsyncAction(
    '_VaultStore.deleteRecord',
    context: context,
  );

  @override
  Future<bool> deleteRecord(String id) {
    return _$deleteRecordAsyncAction.run(() => super.deleteRecord(id));
  }

  late final _$updateRecordAsyncAction = AsyncAction(
    '_VaultStore.updateRecord',
    context: context,
  );

  @override
  Future<bool> updateRecord(String id, Map<String, dynamic> updates) {
    return _$updateRecordAsyncAction.run(() => super.updateRecord(id, updates));
  }

  late final _$createSectionAsyncAction = AsyncAction(
    '_VaultStore.createSection',
    context: context,
  );

  @override
  Future<bool> createSection({
    required String key,
    required String name,
    required List<String> recordIds,
    required String user,
    required String workspace,
  }) {
    return _$createSectionAsyncAction.run(
      () => super.createSection(
        key: key,
        name: name,
        recordIds: recordIds,
        user: user,
        workspace: workspace,
      ),
    );
  }

  late final _$updateSectionAsyncAction = AsyncAction(
    '_VaultStore.updateSection',
    context: context,
  );

  @override
  Future<bool> updateSection(String id, Map<String, dynamic> updates) {
    return _$updateSectionAsyncAction.run(
      () => super.updateSection(id, updates),
    );
  }

  late final _$deleteSectionAsyncAction = AsyncAction(
    '_VaultStore.deleteSection',
    context: context,
  );

  @override
  Future<bool> deleteSection(String id) {
    return _$deleteSectionAsyncAction.run(() => super.deleteSection(id));
  }

  late final _$createFromTemplateAsyncAction = AsyncAction(
    '_VaultStore.createFromTemplate',
    context: context,
  );

  @override
  Future<bool> createFromTemplate({
    required Template template,
    required String user,
    required String workspace,
  }) {
    return _$createFromTemplateAsyncAction.run(
      () => super.createFromTemplate(
        template: template,
        user: user,
        workspace: workspace,
      ),
    );
  }

  late final _$_VaultStoreActionController = ActionController(
    name: '_VaultStore',
    context: context,
  );

  @override
  void clearError() {
    final _$actionInfo = _$_VaultStoreActionController.startAction(
      name: '_VaultStore.clearError',
    );
    try {
      return super.clearError();
    } finally {
      _$_VaultStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
records: ${records},
sections: ${sections},
isLoading: ${isLoading},
errorMessage: ${errorMessage},
recordCount: ${recordCount}
    ''';
  }
}
