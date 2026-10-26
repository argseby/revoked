import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Someone who reads at twice the size must still be able to use every main
/// screen on a phone: nothing may overflow, which in a test is an error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var storesReady = false;

  Future<GoRouter> boot(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    if (!storesReady) {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await Stores.init(
        httpClient: MockClient((_) async => http.Response('{}', 404)),
      );
      storesReady = true;
    }
    runInAction(() => Stores.auth.currentUser = null);
    final router = AppRouter.create(Stores.auth);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.build(Brightness.light),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    runInAction(
      () => Stores.auth.currentUser = User.fromJson({
        'id': 'u1',
        'email': 'ada.lovelace@example.com',
        'activeWorkspace': 'w1',
      }),
    );
    await tester.pumpAndSettle();
    return router;
  }

  const screens = [
    '/overview',
    '/vault',
    '/shared',
    '/requests',
    '/requests?tab=received',
    '/settings',
    '/settings/appearance',
  ];

  for (final size in const [Size(400, 820), Size(1280, 800)]) {
    testWidgets('every main screen fits at 200% text, ${size.width.toInt()} '
        'wide', (tester) async {
      final router = await boot(tester, size);
      for (final path in screens) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$path overflowed at 200% text',
        );
      }
    });
  }
}
