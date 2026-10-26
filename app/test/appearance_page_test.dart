import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revoked_app/core/design/motion.dart';
import 'package:revoked_app/core/state/display_preferences.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/display_scope.dart';
import 'package:revoked_app/features/settings/view/appearance_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The page that makes the app readable for someone who needs it larger,
/// calmer or plainer. Each choice has to reach the whole app, not just the
/// page it was made on.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
  });

  setUp(() async {
    await DisplayPreferences.setDetailLevel(DetailLevel.essentials);
    await DisplayPreferences.setTextScale(1);
    await DisplayPreferences.setReduceMotion(false);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(child: AppearancePage()),
        ),
      ),
    );
  }

  testWidgets('full detail shows more in the preview', (tester) async {
    await pumpPage(tester);
    expect(find.text('example.org/s/k7m2p9'), findsNothing);
    await tester.tap(find.text('Full detail'));
    await tester.pump();
    expect(DisplayPreferences.detailLevel, DetailLevel.full);
    expect(find.text('example.org/s/k7m2p9'), findsOneWidget);
  });

  testWidgets('the theme is chosen here', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(Stores.theme.mode, ThemeMode.dark);
    await tester.tap(find.text('System'));
    await tester.pump();
  });

  testWidgets('reduce motion is a switch', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(DisplayPreferences.reduceMotion, isTrue);
  });

  group('across the app', () {
    late double scale;
    late Duration motion;

    Widget probe() => MaterialApp(
      builder: (context, child) => DisplayScope(child: child!),
      home: Builder(
        builder: (context) {
          scale = MediaQuery.textScalerOf(context).scale(10) / 10;
          motion = AppMotion.of(context);
          return const SizedBox();
        },
      ),
    );

    testWidgets('text size multiplies the device\'s', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(probe());
      expect(scale, closeTo(1.2, 0.001));

      await DisplayPreferences.setTextScale(1.5);
      await tester.pump();
      expect(scale, closeTo(1.8, 0.001));
    });

    testWidgets('reduce motion turns animation off everywhere', (tester) async {
      await tester.pumpWidget(probe());
      expect(motion, AppMotion.duration);
      await DisplayPreferences.setReduceMotion(true);
      await tester.pump();
      expect(motion, Duration.zero);
    });

    test('only the offered sizes are kept', () async {
      await DisplayPreferences.setTextScale(7);
      expect(DisplayPreferences.textScale, 1.0);
      await DisplayPreferences.setTextScale(1.75);
      await DisplayPreferences.load();
      expect(DisplayPreferences.textScale, 1.75);
    });
  });
}
