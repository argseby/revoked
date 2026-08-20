import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/auth/view/login_screen.dart';
import 'package:revoked_app/features/shell/view/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fresh install has no session, so initialize() completes with
/// isAuthenticated still false. The router's refresh notifier used to watch
/// only that flag - false to false fires no reaction - so a signed-out start
/// sat on "Restoring your session" forever. The gate must open on
/// isInitialized, not on a login that never happened.
///
/// The keychain read is gated so the session check genuinely concludes AFTER
/// the first frame - the exact timing that froze the router.
class _GatedStorage implements FlutterSecureStorage {
  final Completer<void> gate = Completer<void>();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #read) {
      return gate.future.then((_) => null); // then: no stored session
    }
    if (invocation.memberName == #write || invocation.memberName == #delete) {
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a signed-out start reaches the login screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(); // the screens read the singletons

    final storage = _GatedStorage();
    final auth = AuthStore(ApiClient(secureStorage: storage));
    unawaited(auth.initialize());

    final router = AppRouter.create(auth);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    // First frame: the keychain has not answered, the session is unknown.
    expect(auth.isInitialized, isFalse);
    expect(find.byType(SplashScreen), findsOneWidget);

    // The keychain answers: no session. isAuthenticated stays false - the
    // router must wake on isInitialized alone.
    storage.gate.complete();
    await tester.pumpAndSettle();

    expect(auth.isInitialized, isTrue);
    expect(
      find.byType(SplashScreen),
      findsNothing,
      reason: 'the splash must release once the session check concluded',
    );
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
