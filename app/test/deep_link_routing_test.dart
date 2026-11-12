import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/router/resume_location.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/auth/view/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A revoked:// link is how a share or request reaches anyone, and it arrives
/// on the first frame — before the stored session has been checked. The splash
/// gate must not swallow where it was going.
void main() {
  test('public links map to routes that need no session', () {
    for (final raw in [
      'revoked://r/abc123',
      'revoked://s/def456',
      'revoked://i/ghi789',
    ]) {
      final location = DeepLinks.locationFor(Uri.parse(raw));
      expect(location, isNotNull, reason: '$raw produced no location');
      expect(
        location!.startsWith('/r/') ||
            location.startsWith('/s/') ||
            location.startsWith('/i/') ||
            location.startsWith('/request/') ||
            location.startsWith('/share/'),
        isTrue,
        reason:
            '$raw -> $location is not one of the public prefixes the '
            'router exempts from the splash gate',
      );
    }
  });

  test('an unknown scheme resolves to nothing', () {
    expect(
      DeepLinks.locationFor(Uri.parse('https://example.com/r/abc')),
      isNull,
    );
  });

  platformLinkTests();
}

/// Flutter hands the platform's link to the router as it stands, scheme and
/// all, unless the app opts out. No route matches that, so the person saw
/// "no routes for location: revoked://signin?…" instead of the sign-in.
void platformLinkTests() {
  Future<GoRouter> startSignedOut(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init();
    final auth = AuthStore(ApiClient());
    await auth.initialize();
    final router = AppRouter.create(auth);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> arrive(WidgetTester tester, GoRouter router, String link) async {
    router.routeInformationProvider.didPushRouteInformation(
      RouteInformation(uri: Uri.parse(link)),
    );
    await tester.pumpAndSettle();
  }

  const signIn =
      'revoked://signin?client_id=https%3A%2F%2Fgame.example'
      '&redirect_uri=https%3A%2F%2Fgame.example%2Fcallback&response_type=code'
      '&scope=openid&state=s&nonce=n'
      '&code_challenge=rs3hAuEIBF0w2mkDu1mwLADsVrrONwdCAel4Gvthsw8'
      '&code_challenge_method=S256&revoked_return=background';

  testWidgets('a sign-in link from the platform waits for the sign-in', (
    tester,
  ) async {
    final router = await startSignedOut(tester);
    await arrive(tester, router, signIn);

    expect(find.textContaining('no routes for location'), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    final held = ResumeLocation.take();
    expect(held, startsWith('/signin?'));
    expect(held, contains('revoked_return=background'));
  });

  testWidgets('Android\'s form of the link, with a slash, works the same', (
    tester,
  ) async {
    final router = await startSignedOut(tester);
    await arrive(tester, router, signIn.replaceFirst('signin?', 'signin/?'));

    expect(find.textContaining('no routes for location'), findsNothing);
    expect(ResumeLocation.take(), startsWith('/signin?'));
  });

  testWidgets('a share link from the platform opens the share', (tester) async {
    final router = await startSignedOut(tester);
    await arrive(tester, router, 'revoked://s/api.revoked.link/abc123');

    expect(find.textContaining('no routes for location'), findsNothing);
    final uri = router.routerDelegate.currentConfiguration.uri;
    expect(uri.path, '/s/abc123');
    expect(uri.queryParameters['o'], 'api.revoked.link');
  });

  testWidgets('a link nothing understands is not an error page', (
    tester,
  ) async {
    final router = await startSignedOut(tester);
    await arrive(tester, router, 'revoked://nonsense');

    expect(find.textContaining('no routes for location'), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
