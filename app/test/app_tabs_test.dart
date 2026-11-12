import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_tabs.dart';

void main() {
  Future<void> pumpTabs(
    WidgetTester tester, {
    double width = 400,
    double textScale = 1,
    int initialIndex = 0,
    bool threeTabs = false,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: AppTabs(
              title: 'Shares',
              initialIndex: initialIndex,
              tabs: [
                const AppTab(
                  label: 'Sent',
                  icon: Icons.north_east,
                  description: 'Links you shared with others.',
                  view: TextField(key: ValueKey('sent-query')),
                ),
                const AppTab(
                  label: 'Received',
                  icon: Icons.south_west,
                  description: 'Items others shared with you.',
                  view: Text('Received content'),
                ),
                if (threeTabs)
                  const AppTab(
                    label: 'Checked',
                    icon: Icons.verified,
                    description: 'Attestations from others, and their checks.',
                    view: Text('Checked content'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('context cards switch pages without losing the search', (
    tester,
  ) async {
    await pumpTabs(tester);
    expect(find.text('Links you shared with others.'), findsOneWidget);
    expect(find.text('Items others shared with you.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('sent-query')),
      'Insurance',
    );
    await tester.tap(find.text('Received'));
    await tester.pumpAndSettle();
    expect(find.text('Received content'), findsOneWidget);
    expect(find.byKey(const ValueKey('sent-query')), findsNothing);
    await tester.tap(find.text('Sent'));
    await tester.pumpAndSettle();
    expect(find.text('Insurance'), findsOneWidget);
  });

  testWidgets('a received deep link selects its context card', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTabs(tester, initialIndex: 1);
    expect(find.text('Received content'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Received')),
      matchesSemantics(
        label: 'Received\nItems others shared with you.',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    semantics.dispose();
  });

  for (final width in [320.0, 800.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('equal context cards fit $width in $brightness', (
        tester,
      ) async {
        await pumpTabs(
          tester,
          width: width,
          threeTabs: true,
          brightness: brightness,
        );
        final cards = find.byType(InkWell);
        expect(cards, findsNWidgets(3));
        final sizes = tester.widgetList<InkWell>(cards).map((widget) {
          return tester.getSize(find.byWidget(widget));
        }).toList();
        expect(sizes[1], sizes[0]);
        expect(sizes[2], sizes[0]);
        expect(tester.getRect(cards.last).right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('context descriptions fit with enlarged phone text', (
    tester,
  ) async {
    await pumpTabs(tester, width: 320, textScale: 2);
    expect(find.text('Items others shared with you.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
