import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_collection_header.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/settings/view/settings_pages.dart';
import 'package:revoked_app/features/settings/view/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'items': <Object>[],
            'totalItems': 0,
            'enabled': false,
            'required': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  for (final brightness in Brightness.values) {
    for (final compact in [true, false]) {
      final size = compact ? const Size(320, 740) : const Size(1280, 1000);
      final scale = compact ? 1.75 : 1.0;
      final layout =
          '${brightness.name}, ${compact ? 'small phone with large text' : 'desktop'}';

      Future<void> pumpPage(WidgetTester tester, Widget page) async {
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
            home: Scaffold(body: page),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('settings destinations fit $layout', (tester) async {
        await pumpPage(tester, const SettingsScreen());
        expect(find.text('Your settings'), findsOneWidget);
        final cards = find.descendant(
          of: find.byType(AppCollectionGrid),
          matching: find.byType(Card),
        );
        final heights = tester
            .widgetList(cards)
            .map((card) => tester.getSize(find.byWidget(card)).height)
            .toSet();
        expect(
          heights.length,
          1,
          reason:
              'Every settings destination has the same height across categories.',
        );
        expect(tester.takeException(), isNull);
      });

      for (final page in SettingsPage.values) {
        testWidgets('${page.slug} fits $layout', (tester) async {
          await pumpPage(tester, SettingsPageScreen(page: page));
          expect(find.text(page.description), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
