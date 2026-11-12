import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:revoked_app/core/state/local.dart';
import 'package:revoked_app/core/widgets/app_filter_menu.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/shares/view/shares_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Link _link(String id, String label, String status) => Link.fromJson({
  'id': id,
  'slug': 's-$id',
  'label': label,
  'status': status,
  'created': '2026-01-0${id.length}',
});

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1200, 900),
  String? recipient,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  await Stores.init(
    httpClient: MockClient((_) async => http.Response('{}', 404)),
  );
  runInAction(
    () => Stores.shares.shares = ObservableList.of([
      _link('a', 'Landlord', 'active'),
      _link('bb', 'Bank', 'paused'),
      _link('ccc', 'Landlord', 'paused'),
    ]),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: Scaffold(body: SharesScreen(recipient: recipient)),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _rows(String label) =>
    find.descendant(of: find.byType(SharesScreen), matching: find.text(label));

Finder _panelRow(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell));

void main() {
  testWidgets('ticking a status narrows the list and shows a chip', (
    tester,
  ) async {
    await _pump(tester);
    expect(_rows('Bank'), findsOneWidget);
    expect(_rows('Landlord'), findsNWidgets(2));

    await tester.tap(find.text('Filter and sort'));
    await tester.pumpAndSettle();
    await tester.tap(_panelRow('Active').first);
    await tester.pumpAndSettle();
    // The popover stays open while boxes are ticked.
    expect(find.text('Sort'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Changes apply as you choose.'), findsNothing);

    expect(_rows('Bank'), findsNothing);
    expect(_rows('Landlord'), findsOneWidget);
    expect(find.text('Status: Active'), findsOneWidget);

    // The chip's × lets everything through again.
    await tester.tap(find.bySemanticsLabel('Remove Status: Active'));
    await tester.pumpAndSettle();
    expect(find.text('Status: Active'), findsNothing);
    expect(_rows('Bank'), findsOneWidget);
  });

  testWidgets('a sort other than the first shows as a chip; Reset undoes all', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Filter and sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oldest first').last);
    await tester.pumpAndSettle();
    await tester.tap(_panelRow('Paused').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Filter and sort · 2 active'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 890));
    await tester.pumpAndSettle();
    expect(find.text('Oldest first'), findsNothing);
    expect(find.text('Status: Paused'), findsNothing);
    expect(_rows('Landlord'), findsNWidgets(2));
  });

  testWidgets('quick status filters always show the matching removable chip', (
    tester,
  ) async {
    await _pump(tester);
    for (final (quick, active) in [
      ('Active 1', 'Status: Active'),
      ('Paused 2', 'Status: Paused'),
    ]) {
      await tester.tap(find.text(quick));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Remove $active'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(active)).dy,
        greaterThan(tester.getBottomLeft(find.byType(TextField)).dy),
      );
      await tester.tap(find.bySemanticsLabel('Remove $active'));
      await tester.pumpAndSettle();
      expect(find.text(active), findsNothing);
      expect(_rows('Landlord'), findsNWidgets(2));
    }
  });

  testWidgets('All clears every filter while retaining search and sort', (
    tester,
  ) async {
    final status = Local<Set<String>>({'active'});
    final verified = Local(true);
    final order = Local('oldest');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(
          body: AppListToolbar(
            query: 'bank',
            onQueryChanged: (_) {},
            totalCount: 3,
            quickSections: const ['Status', 'Trust'],
            sections: () => [
              AppChecklistSection(
                title: 'Status',
                selected: status.value,
                onToggle: (id, on) => status.value = on
                    ? {...status.value, id}
                    : ({...status.value}..remove(id)),
                items: const [
                  AppChecklistItem(id: 'active', label: 'Active', count: 1),
                  AppChecklistItem(id: 'paused', label: 'Paused', count: 2),
                ],
              ),
              AppChecklistSection(
                title: 'Trust',
                selected: {if (verified.value) 'verified'},
                onToggle: (_, on) => verified.value = on,
                items: const [
                  AppChecklistItem(id: 'verified', label: 'Verified', count: 1),
                ],
              ),
            ],
            onClearFilters: () {
              status.value = {};
              verified.value = false;
            },
            sortOptions: const [
              AppSortOption('newest', 'Newest first'),
              AppSortOption('oldest', 'Oldest first'),
            ],
            sort: () => order.value,
            onSort: (value) => order.value = value,
            defaultSort: 'newest',
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Remove Status: Active'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove Trust: Verified'), findsOneWidget);
    await tester.tap(find.text('All 3'));
    await tester.pumpAndSettle();
    expect(status.value, isEmpty);
    expect(verified.value, isFalse);
    expect(order.value, 'oldest');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'bank',
    );
    expect(find.bySemanticsLabel('Remove Status: Active'), findsNothing);
    expect(find.bySemanticsLabel('Remove Trust: Verified'), findsNothing);
    expect(find.bySemanticsLabel('Remove Oldest first'), findsOneWidget);
  });

  testWidgets('selected person stays removable when search finds no matches', (
    tester,
  ) async {
    await _pump(tester, recipient: 'landlord');
    await tester.enterText(find.byType(TextField), 'nothing matches this');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Remove Person: Landlord'), findsOneWidget);
    expect(find.text('All 0'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Remove Person: Landlord'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Remove Person: Landlord'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'nothing matches this',
    );
  });

  testWidgets('the recipient route parameter ticks that person', (
    tester,
  ) async {
    await _pump(tester, recipient: 'landlord');
    expect(find.text('Links for Landlord'), findsOneWidget);
    expect(find.text('Person: Landlord'), findsOneWidget);
    expect(_rows('Bank'), findsNothing);
  });

  testWidgets('the search narrows the list it sits above', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'bank');
    await tester.pumpAndSettle();
    expect(_rows('Bank'), findsOneWidget);
    expect(_rows('Landlord'), findsNothing);

    // Esc clears it.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_rows('Landlord'), findsNWidgets(2));
  });

  testWidgets('search and filter controls line up below the tabs', (
    tester,
  ) async {
    for (final size in const [
      Size(400, 900),
      Size(800, 900),
      Size(1200, 900),
    ]) {
      await _pump(tester, size: size);
      final tabs = tester.getRect(find.text('Sent'));
      final field = tester.getRect(find.byType(TextField));
      final button = tester.getRect(find.byTooltip('Filter and sort'));
      expect(field.top, greaterThan(tabs.bottom), reason: '$size');
      expect(button.left, greaterThan(field.right), reason: '$size');
      expect(button.top, greaterThanOrEqualTo(field.top), reason: '$size');
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('a phone gets the panel as a sheet, the button as an icon', (
    tester,
  ) async {
    await _pump(tester, size: const Size(400, 900));
    expect(find.text('Filter and sort'), findsNothing);
    await tester.tap(find.byTooltip('Filter and sort'));
    await tester.pumpAndSettle();
    expect(find.text('Filter and sort'), findsOneWidget);
    await tester.tap(_panelRow('Bank').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Links for Bank'), findsOneWidget);
    // Short labels on a phone.
    expect(find.text('Bank'), findsWidgets);
    expect(find.text('Person: Bank'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 640), const Size(800, 700)]) {
      testWidgets('long filters stay usable at $size in ${brightness.name}', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final selected = Local<Set<String>>({'1'});
        final order = Local('newest');
        final query = Local('');
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.75)),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Observer(
                  builder: (_) => AppListToolbar(
                    query: query.value,
                    onQueryChanged: (value) => query.value = value,
                    onClearFilters: () => selected.value = {},
                    sortOptions: const [
                      AppSortOption('newest', 'Newest first'),
                      AppSortOption('oldest', 'Oldest first'),
                    ],
                    sort: () => order.value,
                    defaultSort: 'newest',
                    onSort: (value) => order.value = value,
                    sections: () => [
                      AppChecklistSection(
                        title: 'People',
                        selected: selected.value,
                        items: [
                          for (var i = 0; i < 24; i++)
                            AppChecklistItem(
                              id: '$i',
                              label: 'Person $i',
                              count: i,
                            ),
                        ],
                        onToggle: (id, on) => selected.value = on
                            ? {...selected.value, id}
                            : ({...selected.value}..remove(id)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Filter and sort · 1 active'));
        await tester.pumpAndSettle();
        final search = find.widgetWithText(TextField, 'Find people');
        await tester.ensureVisible(search);
        await tester.enterText(search, 'Person 23');
        await tester.pumpAndSettle();
        // A selection remains reachable when the option search changes.
        expect(find.text('Person 1'), findsWidgets);
        expect(
          find.byWidgetPredicate((w) => w is Text && w.data == 'Person 23'),
          findsOneWidget,
        );
        expect(find.text('Person 2'), findsNothing);
        await tester.tap(find.text('Reset'));
        await tester.pumpAndSettle();
        expect(selected.value, isEmpty);
        expect(tester.widget<TextField>(search).controller!.text, isEmpty);
        expect(find.text('Person 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Changes apply as you choose.'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
