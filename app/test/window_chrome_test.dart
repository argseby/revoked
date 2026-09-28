import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart' show runInAction;
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/window_chrome.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The window's buttons go in the app's root overlay, above every route: the
/// screens with no top bar of their own would otherwise leave a window nobody
/// can close. They need that overlay for two reasons — an icon-only button
/// carries a Tooltip, which has nowhere to render without one, and a second
/// Overlay stacked above the navigator tripped the framework's semantics
/// assertions on every resize.
void main() {
  testWidgets('the window controls reach the root overlay', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init();
    runInAction(() => Stores.window.ownsTitleBar = true);
    WindowTitleBar.attach();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: AppRouter.rootNavigatorKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    await tester.pump();

    // The bar reserves WindowControls.extent for a layer it cannot measure,
    // so the two must not drift apart — the bell would end up underneath.
    expect(
      tester.getSize(find.byType(WindowControls)).width,
      WindowControls.extent,
    );

    expect(find.byTooltip('Minimize'), findsOneWidget);
    expect(find.byTooltip('Maximize'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);

    // A route pushed afterwards must not cover them — the navigator inserts a
    // route relative to the route below it, not on top of everything.
    AppRouter.rootNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();
    // tap() fails the test if the route paints over the button, which a
    // findsOneWidget on its own would not catch.
    await tester.tap(find.byTooltip('Minimize'));
    await tester.pump();
  });
}
