import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/widgets/data_table/table_store.dart';

/// The filter drawer sits over the list it filters. Every control in it has to
/// move the list underneath immediately — closing the drawer to see the result
/// is the bug this pins. Searching by name is not here: that is the shell's
/// one search panel, over every kind at once.
void main() {
  late ObservableList<String> source;
  late TableStore<String> table;

  setUp(() {
    source = ObservableList<String>.of(['alpha', 'beta', 'gamma']);
    table = TableStore<String>(
      getSourceItems: () => source,
      fieldGetters: {'name': (s) => s},
      defaultSort: 'name_asc',
    );
  });

  Future<int> mount(WidgetTester tester, List<String> seen) async {
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Observer(
          builder: (_) {
            builds++;
            seen
              ..clear()
              ..addAll(table.filteredItems);
            return Text('${table.filteredItems.length}');
          },
        ),
      ),
    );
    return builds;
  }

  testWidgets('adding and filling a filter updates the list', (tester) async {
    final seen = <String>[];
    await mount(tester, seen);

    table.addFilter('name');
    await tester.pump();
    expect(seen.length, 3, reason: 'an empty filter matches everything');

    table.updateFilter(table.filters.first.id, value: 'gam');
    await tester.pump();
    expect(seen, ['gamma']);
  });

  testWidgets('changing the sort updates the list', (tester) async {
    final seen = <String>[];
    await mount(tester, seen);
    expect(seen, ['alpha', 'beta', 'gamma']);

    table.setSort('name_desc');
    await tester.pump();

    expect(seen, ['gamma', 'beta', 'alpha']);
  });

  testWidgets('clearing filters restores the full list', (tester) async {
    final seen = <String>[];
    await mount(tester, seen);
    table.addFilter('name');
    table.updateFilter(table.filters.first.id, value: 'zzz');
    await tester.pump();
    expect(seen, isEmpty);

    table.clearFilters();
    await tester.pump();

    expect(seen, ['alpha', 'beta', 'gamma']);
  });
}
