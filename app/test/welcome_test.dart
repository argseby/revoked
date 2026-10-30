import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_qr_code.dart';
import 'package:revoked_app/features/auth/view/login_screen.dart';
import 'package:revoked_app/features/auth/view/round_trip.dart';
import 'package:revoked_app/features/onboarding/view/workspace_onboarding_screen.dart';

/// People gave up when "Create account" opened a browser they did not
/// expect. The app now says the browser opens, and comes back, before it
/// opens; on a computer it first offers to move to the phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object>? signups = {'open': true, 'verifyEmail': true};
  final launched = <Uri>[];

  Future<http.Response> server(http.Request request) async {
    if (request.url.path == '/api/server') {
      return http.Response(
        jsonEncode({'signups': ?signups}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{"items":[]}', 200);
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(httpClient: MockClient(server));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            if (call.method == 'launch') {
              launched.add(Uri.parse((call.arguments as Map)['url'] as String));
            }
            return true;
          },
        );
  });

  setUp(() async {
    launched.clear();
    await Stores.auth.cancelSignIn();
    Stores.auth.createdAccount = false;
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.build(Brightness.light), home: screen),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the welcome screen is the name and two buttons', (tester) async {
    signups = {'open': true, 'verifyEmail': true};
    await show(tester, const LoginScreen());
    expect(find.text('Revoked'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('I have an account'), findsOneWidget);
  });

  testWidgets('a closed server offers only signing in', (tester) async {
    signups = {'open': false, 'verifyEmail': false};
    await show(tester, const LoginScreen());
    expect(find.text('This server isn\'t taking new accounts'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('on a phone, the browser is announced before it opens', (
    tester,
  ) async {
    signups = {'open': true, 'verifyEmail': true};
    await show(tester, const LoginScreen());
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
    expect(find.text('Next: your browser'), findsOneWidget);
    expect(find.byType(RoundTrip), findsOneWidget);

    await tester.tap(find.text('Open browser'));
    await tester.pumpAndSettle();
    expect(launched.single.queryParameters['mode'], 'signup');
    expect(find.text('Continue in your browser'), findsOneWidget);

    // It used to reopen the page on signing in.
    await tester.tap(find.text('Open browser again'));
    await tester.pumpAndSettle();
    expect(launched.last.queryParameters['mode'], 'signup');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('on a computer, the phone is offered first', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    signups = {'open': true, 'verifyEmail': true};
    await show(tester, const LoginScreen());
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Better on your phone'), findsOneWidget);
    final qr = tester.widget<AppQrCode>(find.byType(AppQrCode));
    expect(qr.data, endsWith('/app'));

    await tester.tap(find.text('Continue on this computer'));
    await tester.pumpAndSettle();
    expect(find.text('Next: your browser'), findsOneWidget);
    expect(launched, isEmpty);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('right after sign-up, the name ends the trip', (tester) async {
    signups = {'open': true, 'verifyEmail': true};
    await show(tester, const LoginScreen());
    Stores.auth.createdAccount = true;
    runInAction(
      () => Stores.auth.currentUser = User.fromJson({
        'id': 'u1',
        'email': 'ada.lovelace@example.com',
      }),
    );
    await show(tester, const WorkspaceOnboardingScreen());
    expect(find.byType(RoundTrip), findsOneWidget);
    expect(find.text('Your name'), findsOneWidget);
    // The workspace is named, not asked for.
    expect(find.text('Personal'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Personal'), findsNothing);

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Personal'), findsOneWidget);
  });
}
