import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_filter_chips.dart';

/// The status chips above Links and Requests: one selection shared with the
/// Status section of Filter and sort.
void main() {
  Future<Set<String>> Function() pump(
    WidgetTester tester, {
    required Map<String, int> counts,
    Set<String> selected = const {},
  }) {
    var value = selected;
    Future<Set<String>> build() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => AppStatusChips<String>(
                selected: value,
                onChanged: (v) => setState(() => value = v),
                options: [
                  for (final e in counts.entries)
                    AppFilterOption(value: e.key, label: e.key, count: e.value),
                ],
              ),
            ),
          ),
        ),
      );
      return value;
    }

    return () async {
      await build();
      await tester.pumpAndSettle();
      return value;
    };
  }

  testWidgets('chips count each status and All sums them', (tester) async {
    final read = pump(tester, counts: {'Active': 6, 'Paused': 1, 'Closed': 0});
    await read();
    expect(find.text('All 7'), findsOneWidget);
    expect(find.text('Active 6'), findsOneWidget);
    expect(find.text('Paused 1'), findsOneWidget);
    // A status that holds nothing has no chip.
    expect(find.textContaining('Closed'), findsNothing);
  });

  testWidgets('a chip picks one status and All clears it', (tester) async {
    final read = pump(tester, counts: {'Active': 6, 'Paused': 1});
    await read();
    await tester.tap(find.text('Paused 1'));
    await tester.pumpAndSettle();
    expect(await read(), {'Paused'});
    await tester.tap(find.text('All 7'));
    await tester.pumpAndSettle();
    expect(await read(), isEmpty);
  });

  testWidgets('one status alone shows no chips', (tester) async {
    final read = pump(tester, counts: {'Active': 4, 'Paused': 0});
    await read();
    expect(find.textContaining('All'), findsNothing);
    expect(
      const AppStatusChips<String>(
        options: [AppFilterOption(value: 'a', label: 'a', count: 4)],
        selected: {},
        onChanged: _ignore,
      ).orNull,
      isNull,
    );
  });

  testWidgets('a ticked status with nothing in it keeps its chip', (
    tester,
  ) async {
    final read = pump(
      tester,
      counts: {'Active': 4, 'Closed': 0},
      selected: {'Closed'},
    );
    await read();
    expect(find.text('Closed 0'), findsOneWidget);
    expect(find.text('All 4'), findsOneWidget);
  });
}

void _ignore(Set<String> _) {}
