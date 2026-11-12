import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';

void main() {
  var opened = 0;
  var chosen = 0;

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1000, 800),
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    opened = 0;
    chosen = 0;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              child: AppListRow(
                icon: Icons.description,
                title: 'Passport',
                onTap: () => opened++,
                contextActions: () => [
                  AppSheetAction(
                    icon: Icons.copy,
                    label: 'Copy value',
                    onTap: () => chosen++,
                  ),
                  AppSheetAction(
                    icon: Icons.edit,
                    label: 'Edit',
                    enabled: false,
                    onTap: () => chosen++,
                  ),
                  AppSheetAction(
                    icon: Icons.delete,
                    label: 'Delete',
                    destructive: true,
                    onTap: () => chosen++,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> rightClick(WidgetTester tester) async {
    final mouse = await tester.startGesture(
      tester.getCenter(find.text('Passport')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.up();
    await tester.pumpAndSettle();
  }

  testWidgets('normal tap still opens the item', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Passport'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('Copy value'), findsNothing);
  });

  testWidgets(
    'right click opens a menu without navigating and runs one action',
    (tester) async {
      await pump(tester);
      await rightClick(tester);
      expect(opened, 0);
      expect(find.byType(PopupMenuItem<AppSheetAction>), findsWidgets);
      await tester.tap(find.text('Copy value'));
      await tester.pumpAndSettle();
      expect(chosen, 1);
      expect(opened, 0);
      expect(find.text('Copy value'), findsNothing);
    },
  );

  testWidgets('disabled desktop action cannot run', (tester) async {
    await pump(tester);
    await rightClick(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(chosen, 0);
    expect(find.text('Copy value'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Copy value'), findsNothing);
  });

  testWidgets('Shift F10 opens options for the focused row', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Copy value'), findsOneWidget);
    expect(opened, 0);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'long press on ${platform.name} in ${brightness.name} opens options without navigation',
        (tester) async {
          await pump(
            tester,
            size: const Size(320, 640),
            scale: 1.75,
            brightness: brightness,
          );
          await tester.longPress(find.text('Passport'));
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(opened, 0);
          await tester.tap(find.text('Copy value'));
          await tester.pumpAndSettle();
          expect(chosen, 1);
          expect(find.byType(BottomSheet), findsNothing);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant({platform}),
      );
    }
  }
}
