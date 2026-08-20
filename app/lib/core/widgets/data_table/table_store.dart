import 'package:mobx/mobx.dart';

part 'table_store.g.dart';

class DataTableColumn {
  final String value;
  final String label;

  const DataTableColumn({required this.value, required this.label});
}

class DataTableFilter {
  final String id;
  final String column;
  final String operator; // 'contains' | 'equals' | 'starts_with' | 'ends_with'
  final String value;

  DataTableFilter({
    required this.id,
    required this.column,
    required this.operator,
    required this.value,
  });

  DataTableFilter copyWith({
    String? id,
    String? column,
    String? operator,
    String? value,
  }) {
    return DataTableFilter(
      id: id ?? this.id,
      column: column ?? this.column,
      operator: operator ?? this.operator,
      value: value ?? this.value,
    );
  }
}

/// One entry in the sort dropdown: the key [TableStore.sortBy] holds, and how
/// it reads to the user.
class DataTableSortOption {
  final String key;
  final String label;

  const DataTableSortOption(this.key, this.label);
}

/// Every sort a table with [columns] offers: each column both ways, then
/// newest/oldest. Built here so the dropdown and `sortBy` cannot drift.
List<DataTableSortOption> sortOptionsFor(List<DataTableColumn> columns) => [
  const DataTableSortOption('created_desc', 'Newest first'),
  const DataTableSortOption('created_asc', 'Oldest first'),
  for (final c in columns) ...[
    DataTableSortOption('${c.value}_asc', '${c.label} (A–Z)'),
    DataTableSortOption('${c.value}_desc', '${c.label} (Z–A)'),
  ],
];

/// Search, filter and sort over an in-memory list.
///
/// Page-scoped: the page that needs a table creates one and disposes it there,
/// per the store rules — this is never a singleton.
// ignore: library_private_types_in_public_api
class TableStore<T> = _TableStore<T> with _$TableStore;

abstract class _TableStore<T> with Store {
  final List<T> Function() getSourceItems;
  final Map<String, Comparable Function(T)> fieldGetters;
  final String defaultSort;

  _TableStore({
    required this.getSourceItems,
    required this.fieldGetters,
    this.defaultSort = 'created_desc',
  }) : sortBy = defaultSort;

  final ObservableList<DataTableFilter> filters =
      ObservableList<DataTableFilter>();

  @observable
  String sortBy;

  @observable
  String searchQuery = '';

  @action
  void addFilter(String defaultColumn) {
    filters.add(
      DataTableFilter(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        column: defaultColumn,
        operator: 'contains',
        value: '',
      ),
    );
  }

  @action
  void removeFilter(String id) {
    filters.removeWhere((f) => f.id == id);
  }

  @action
  void updateFilter(
    String id, {
    String? column,
    String? operator,
    String? value,
  }) {
    final index = filters.indexWhere((f) => f.id == id);
    if (index != -1) {
      filters[index] = filters[index].copyWith(
        column: column,
        operator: operator,
        value: value,
      );
    }
  }

  @action
  void clearFilters() {
    filters.clear();
  }

  @action
  void setSort(String sort) {
    sortBy = sort;
  }

  /// What the filter drawer reports while it covers the list it is filtering.
  String get matchSummary {
    final total = getSourceItems().length;
    final shown = filteredItems.length;
    if (shown == total) return '$total ${total == 1 ? 'item' : 'items'}';
    return 'Showing $shown of $total';
  }

  List<T> get filteredItems {
    final source = getSourceItems();
    if (source.isEmpty) return [];

    List<T> result = List.from(source);

    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result.where((item) {
        return fieldGetters.values.any((getter) {
          try {
            return getter(item).toString().toLowerCase().contains(query);
          } catch (_) {
            return false;
          }
        });
      }).toList();
    }

    for (final f in filters) {
      if (f.value.isEmpty) continue;
      final target = f.value.toLowerCase();
      final getter = fieldGetters[f.column];
      if (getter == null) continue;

      result = result.where((item) {
        try {
          final val = getter(item).toString().toLowerCase();
          switch (f.operator) {
            case 'equals':
              return val == target;
            case 'contains':
              return val.contains(target);
            case 'starts_with':
              return val.startsWith(target);
            case 'ends_with':
              return val.endsWith(target);
            default:
              return true;
          }
        } catch (_) {
          return false;
        }
      }).toList();
    }

    if (sortBy.isNotEmpty) {
      final parts = sortBy.split('_');
      if (parts.length >= 2) {
        final col = parts.sublist(0, parts.length - 1).join('_');
        final dir = parts.last;
        final getter = fieldGetters[col];
        if (getter != null) {
          result.sort((a, b) {
            final valA = getter(a);
            final valB = getter(b);
            int comp;
            if (valA is String && valB is String) {
              comp = valA.toLowerCase().compareTo(valB.toLowerCase());
            } else {
              comp = valA.compareTo(valB);
            }
            return dir == 'asc' ? comp : -comp;
          });
        }
      }
    }

    return result;
  }

  /// Page-scoped stores are disposed by the page that created them.
  void dispose() {}
}
