import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
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

/// One button leads in: the server's page offers a saved passkey and a new
/// account side by side, so the app asks nothing first. The button names the
/// browser, since a browser appearing unannounced is where people gave up; a
/// link can be copied for another browser, and a computer offers the phone.
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

  testWidgets('the welcome screen is the name and one button', (tester) async {
    signups = {'open': true, 'verifyEmail': true};
    await show(tester, const LoginScreen());
    expect(find.text('Revoked'), findsOneWidget);
    expect(find.text('Continue in browser'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
    expect(find.text('Sign in'), findsNothing);
    // The button says where it goes; no diagram has to.
    expect(find.byType(RoundTrip), findsNothing);
    expect(launched, isEmpty);
  });

  testWidgets('Copy link hands over the page without opening it', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    signups = {'open': true, 'verifyEmail': true};
    await show(tester, const LoginScreen());
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    final link = Uri.parse(copied!);
    expect(link.path, '/passkey');
    expect(link.queryParameters['mode'], 'signin');
    expect(link.queryParameters['challenge'], isNotEmpty);
    expect(launched, isEmpty);
    expect(find.text('Waiting for the browser'), findsOneWidget);
  });

  testWidgets('a closed server says so, and still has the one button', (
    tester,
  ) async {
    signups = {'open': false, 'verifyEmail': false};
    await show(tester, const LoginScreen());
    expect(find.text('Registration is closed on this server'), findsOneWidget);
    expect(find.text('Continue in browser'), findsOneWidget);
    expect(find.text('Use a phone'), findsNothing);
  });

  testWidgets('Continue opens the browser at once', (tester) async {
    signups = {'open': true, 'verifyEmail': true};
    await show(tester, const LoginScreen());
    // A phone has no phone to move to.
    expect(find.text('Use a phone'), findsNothing);
    await tester.tap(find.text('Continue in browser'));
    await tester.pumpAndSettle();
    expect(launched.single.queryParameters['mode'], 'signin');
    expect(find.text('Waiting for the browser'), findsOneWidget);

    await tester.tap(find.text('Open browser again'));
    await tester.pumpAndSettle();
    expect(launched, hasLength(2));

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Continue in browser'), findsOneWidget);
  });

  testWidgets('on a computer, the phone is offered, not required', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    signups = {'open': true, 'verifyEmail': true};
    await show(tester, const LoginScreen());
    await tester.tap(find.text('Use a phone'));
    await tester.pumpAndSettle();
    expect(find.text('Set up on a phone'), findsOneWidget);
    final qr = tester.widget<AppQrCode>(find.byType(AppQrCode));
    expect(qr.data, endsWith('/app'));
    expect(launched, isEmpty);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Continue in browser'), findsOneWidget);

    await tester.tap(find.text('Use a phone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue on this computer'));
    await tester.pumpAndSettle();
    expect(launched.single.queryParameters['mode'], 'signin');
    expect(find.text('Waiting for the browser'), findsOneWidget);
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
