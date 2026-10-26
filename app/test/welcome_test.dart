import 'dart:convert';

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
import 'package:revoked_app/features/auth/view/login_screen.dart';
import 'package:revoked_app/features/onboarding/view/workspace_onboarding_screen.dart';

/// People wanting to start said sign-up was unclear: they did not know how
/// long it takes, and after pressing "Create account" were asked again
/// whether to create or sign in. The welcome screen now lays out every step
/// before anything opens, counting what this server actually asks.
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

  testWidgets('every step and the time are said before anything opens', (
    tester,
  ) async {
    signups = {'open': true, 'verifyEmail': true};
    await show(tester, const LoginScreen());
    expect(find.text('Creating an account · about 2 minutes'), findsOneWidget);
    for (final step in [
      'Your email',
      'The code we email you',
      'A passkey: your fingerprint, face or device PIN',
      'Your name',
    ]) {
      expect(find.text(step), findsOneWidget, reason: step);
    }
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
  });

  testWidgets('a server that mails no code has one step fewer', (tester) async {
    signups = {'open': true, 'verifyEmail': false};
    await show(tester, const LoginScreen());
    expect(find.text('The code we email you'), findsNothing);
    expect(find.text('Creating an account · about a minute'), findsOneWidget);
  });

  testWidgets('a server without the policy is counted the long way', (
    tester,
  ) async {
    signups = null;
    await show(tester, const LoginScreen());
    expect(find.text('The code we email you'), findsOneWidget);
  });

  testWidgets('a closed server offers only signing in', (tester) async {
    signups = {'open': false, 'verifyEmail': false};
    await show(tester, const LoginScreen());
    expect(find.text('This server takes no new accounts'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('creating opens the page on creating, and reopens it there', (
    tester,
  ) async {
    signups = {'open': true, 'verifyEmail': true};
    await show(tester, const LoginScreen());
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(launched.single.queryParameters['mode'], 'signup');
    expect(find.text('Continue in your browser'), findsOneWidget);

    // It used to reopen the page on signing in.
    await tester.tap(find.text('Open the page again'));
    await tester.pumpAndSettle();
    expect(launched.last.queryParameters['mode'], 'signup');
  });

  testWidgets('right after sign-up, the name is the last counted step', (
    tester,
  ) async {
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
    expect(find.text('Step 4 of 4 · last step'), findsOneWidget);
    expect(find.text('What should people see?'), findsOneWidget);
    // The workspace is named, not asked for.
    expect(find.text('Personal'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Personal'), findsNothing);

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Personal'), findsOneWidget);
  });
}
