// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'table_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$TableStore<T> on _TableStore<T>, Store {
  late final _$sortByAtom = Atom(name: '_TableStore.sortBy', context: context);

  @override
  String get sortBy {
    _$sortByAtom.reportRead();
    return super.sortBy;
  }

  @override
  set sortBy(String value) {
    _$sortByAtom.reportWrite(value, super.sortBy, () {
      super.sortBy = value;
    });
  }

  late final _$searchQueryAtom = Atom(
    name: '_TableStore.searchQuery',
    context: context,
  );

  @override
  String get searchQuery {
    _$searchQueryAtom.reportRead();
    return super.searchQuery;
  }

  @override
  set searchQuery(String value) {
    _$searchQueryAtom.reportWrite(value, super.searchQuery, () {
      super.searchQuery = value;
    });
  }

  late final _$_TableStoreActionController = ActionController(
    name: '_TableStore',
    context: context,
  );

  @override
  void addFilter(String defaultColumn) {
    final _$actionInfo = _$_TableStoreActionController.startAction(
      name: '_TableStore.addFilter',
    );
    try {
      return super.addFilter(defaultColumn);
    } finally {
      _$_TableStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void removeFilter(String id) {
    final _$actionInfo = _$_TableStoreActionController.startAction(
      name: '_TableStore.removeFilter',
    );
    try {
      return super.removeFilter(id);
    } finally {
      _$_TableStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void updateFilter(
    String id, {
    String? column,
    String? operator,
    String? value,
  }) {
    final _$actionInfo = _$_TableStoreActionController.startAction(
      name: '_TableStore.updateFilter',
    );
    try {
      return super.updateFilter(
        id,
        column: column,
        operator: operator,
        value: value,
      );
    } finally {
      _$_TableStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void clearFilters() {
    final _$actionInfo = _$_TableStoreActionController.startAction(
      name: '_TableStore.clearFilters',
    );
    try {
      return super.clearFilters();
    } finally {
      _$_TableStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setSort(String sort) {
    final _$actionInfo = _$_TableStoreActionController.startAction(
      name: '_TableStore.setSort',
    );
    try {
      return super.setSort(sort);
    } finally {
      _$_TableStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
sortBy: ${sortBy},
searchQuery: ${searchQuery}
    ''';
  }
}
