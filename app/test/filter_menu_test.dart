import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    await tester.tapAt(const Offset(5, 890));
    await tester.pumpAndSettle();

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
    await tester.tap(_panelRow('Oldest first'));
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

  testWidgets('the tabs, the search and its button keep the same edges', (
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
      expect(button.right, lessThanOrEqualTo(field.right), reason: '$size');
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
    Navigator.of(tester.element(find.text('Sort'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Links for Bank'), findsOneWidget);
    // Short labels on a phone.
    expect(find.text('Bank'), findsWidgets);
    expect(find.text('Person: Bank'), findsNothing);
  });
}
