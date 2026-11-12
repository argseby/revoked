import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/sign_in_consent.dart';
import 'package:revoked_app/core/models/sign_in_request.dart';
import 'package:revoked_app/core/services/device_unlock.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/connections/view/sign_in_approval_screen.dart';

class _Unlock implements DeviceUnlock {
  @override
  Future<bool> confirm(String reason) async => true;
}

/// Someone signing in to a service again sees that they did before, what the
/// service already gets from them, and what it asks for the first time.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic>? returning;

  Map<String, dynamic> consentJson() => {
    'returning': ?returning,
    'ticket': 'tkt0123456789',
    'client': 'https://club.example',
    'account': {'email': 'ada@home.test'},
    'scopes': [
      {'scope': 'profile', 'value': 'Ada Lovelace'},
      {'scope': 'email', 'value': 'ada@home.test'},
    ],
    'nameOptions': [
      {'kind': 'identity', 'id': 'id1', 'value': 'Ada Lovelace'},
      {
        'kind': 'record',
        'id': 'n1',
        'value': 'Ada at the club',
        'key': 'name_club_example',
        'label': 'Name on club.example',
        if (returning != null) 'shared': true,
        if (returning != null) 'madeFor': true,
      },
    ],
    if (returning != null) 'nameSelected': {'kind': 'record', 'id': 'n1'},
    'links': [
      {
        'key': 'club_badge',
        'options': [
          {
            'id': 'a1',
            'key': 'club_badge',
            'label': 'club_badge',
            'preview': 'Gold',
            if (returning != null) 'shared': true,
            if (returning != null) 'madeFor': true,
          },
        ],
      },
    ],
  };

  Future<http.Response> server(http.Request request) async {
    final body = request.url.path == '/oidc/authorize/app'
        ? consentJson()
        : {'items': <Object>[]};
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(httpClient: MockClient(server), unlock: _Unlock());
    returning = null;
  });

  final request = SignInRequest.fromQuery({
    'client_id': 'https://club.example',
    'redirect_uri': 'https://club.example/callback',
    'response_type': 'code',
    'scope': 'openid profile email',
    'state': 'st-1',
    'nonce': 'n-1',
    'code_challenge': 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    'code_challenge_method': 'S256',
    'claims': '{"userinfo":{"revoked_links":{"values":["club_badge"]}}}',
  })!;

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: SignInApprovalScreen(request: request),
      ),
    );
    await tester.pumpAndSettle();
    // These interaction tests exercise the alternatives after opening them.
    final entryEditors = find.text('Choose or add an entry');
    for (var i = 0; i < entryEditors.evaluate().length; i++) {
      await tester.ensureVisible(entryEditors.at(i));
      await tester.tap(entryEditors.at(i));
      await tester.pumpAndSettle();
    }
  }

  test('a return is read with what the service already has', () {
    final c = SignInConsent.fromJson({
      ...consentJson(),
      'returning': {
        'firstAt': '2026-10-01 09:00:00.000Z',
        'lastAt': '2026-11-02 10:00:00.000Z',
        'scopes': ['profile'],
        'name': {'kind': 'record', 'id': 'n1'},
        'links': {'club_badge': 'b1'},
      },
    });
    final back = c.returning!;
    expect(back.lastAt, '2026-11-02 10:00:00.000Z');
    expect(back.name, 'record:n1');
    expect(back.links, {'club_badge': 'b1'});
    expect(c.isNewScope('profile'), isFalse);
    expect(c.isNewScope('email'), isTrue);

    final first = SignInConsent.fromJson(consentJson());
    expect(first.returning, isNull);
    expect(first.isNewScope('email'), isFalse);
    expect(first.links.single.shared, isNull);
  });

  testWidgets('a first sign-in shows no return', (tester) async {
    await show(tester);
    expect(
      find.textContaining('signed in to club.example before'),
      findsNothing,
    );
    expect(find.text('Shared now'), findsNothing);
    expect(find.text('Made at your last sign-in'), findsNothing);
    expect(find.text('New'), findsNothing);
  });

  testWidgets('a return says so, and marks what is shared and what is new', (
    tester,
  ) async {
    returning = {
      'firstAt': '2026-10-01 09:00:00.000Z',
      'lastAt': '2026-11-02 10:00:00.000Z',
      'scopes': ['profile'],
      'name': {'kind': 'record', 'id': 'n1'},
      'links': {'club_badge': 'b1'},
    };
    await show(tester);

    expect(
      find.text("You've signed in to club.example before"),
      findsOneWidget,
    );
    expect(find.textContaining('It keeps the same ID for you'), findsOneWidget);
    // The name and the badge are both still shared, unchanged.
    expect(find.text('Shared now'), findsNWidgets(2));
    expect(find.text('Made at your last sign-in'), findsNWidgets(2));
    expect(find.textContaining('Already shared · unchanged'), findsNWidgets(2));
    // Only the email address was never granted before.
    expect(find.text('New'), findsOneWidget);
  });
}
