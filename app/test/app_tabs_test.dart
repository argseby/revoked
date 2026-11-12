import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_tabs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Use the shipped font to check whether icon + label fit on one line.
    final font = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Geist-SemiBold.ttf'));
    await font.load();
  });

  Future<void> pumpTabs(
    WidgetTester tester, {
    double width = 400,
    double height = 900,
    double? paneHeight,
    double textScale = 1,
    int initialIndex = 0,
    bool threeTabs = false,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SizedBox(
              height: paneHeight,
              child: AppTabs(
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
                      description:
                          'Attestations from others, and their checks.',
                      view: Text('Checked content'),
                    ),
                ],
              ),
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
    expect(find.text('Links you shared with others.'), findsNothing);
    expect(find.text('Items others shared with you.'), findsNothing);
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
        label: 'Received',
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

  testWidgets('compact tabs fit with enlarged phone text', (tester) async {
    await pumpTabs(tester, width: 320, textScale: 2);
    expect(find.text('Items others shared with you.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone tabs use a single 48px row', (tester) async {
    await pumpTabs(tester, width: 320);
    final cards = find.byType(InkWell);
    for (final card in cards.evaluate()) {
      expect(tester.getSize(find.byWidget(card.widget)).height, 48);
    }
    expect(
      tester.getTopLeft(find.text('Sent')).dy,
      tester.getTopLeft(find.text('Received')).dy,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('roomy tabs show descriptions', (tester) async {
    await pumpTabs(tester, width: 800);
    expect(find.text('Links you shared with others.'), findsOneWidget);
    expect(find.text('Items others shared with you.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide landscape tabs hide descriptions', (tester) async {
    await pumpTabs(tester, width: 812, height: 375);
    expect(find.text('Items others shared with you.'), findsNothing);
    expect(tester.getSize(find.byType(InkWell).first).height, 48);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short pane hides descriptions in a tall window', (
    tester,
  ) async {
    await pumpTabs(tester, width: 800, paneHeight: 400);
    expect(find.text('Items others shared with you.'), findsNothing);
    expect(tester.getSize(find.byType(InkWell).first).height, 48);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resizing restores descriptions and preserves page state', (
    tester,
  ) async {
    await pumpTabs(tester);
    await tester.enterText(
      find.byKey(const ValueKey('sent-query')),
      'Insurance',
    );
    await pumpTabs(tester, width: 800);
    expect(find.text('Links you shared with others.'), findsOneWidget);
    expect(find.text('Insurance'), findsOneWidget);
    await pumpTabs(tester, width: 320);
    expect(find.text('Links you shared with others.'), findsNothing);
    expect(find.text('Insurance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
