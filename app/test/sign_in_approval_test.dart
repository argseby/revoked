import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/sign_in_consent.dart';
import 'package:revoked_app/core/models/sign_in_request.dart';
import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/services/device_unlock.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/utils/pkce.dart';
import 'package:revoked_app/features/connections/sign_in_approval.dart';
import 'package:revoked_app/features/connections/view/sign_in_approval_screen.dart';

class _Unlock implements DeviceUnlock {
  bool answer;
  final asked = <String>[];
  _Unlock(this.answer);

  @override
  Future<bool> confirm(String reason) async {
    asked.add(reason);
    return answer;
  }
}

/// A sign-in at a service is approved in the app: opening the link shows the
/// consent here and opens nothing in a browser, and an approval is signed
/// with the identity key on this device. Only the answer for the service is
/// opened in the browser, after the person decided.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final crypto = CryptoService();
  final identity = crypto.generateIdentity(commonName: 'Ada');
  const ticket = 'tkt0123456789';
  const approved = 'https://game.example/callback?code=c1&state=st-1';
  const denied = 'https://game.example/callback?error=access_denied&state=st-1';
  const refusal =
      'https://game.example/callback?error=login_required&state=st-1';

  final opened = <Map<String, dynamic>>[];
  // Answers the service took straight from the app.
  final delivered = <String>[];
  var serviceUp = true;
  final decisions = <Map<String, dynamic>>[];
  final launched = <String>[];
  var refuse = false;
  var keyOnDevice = true;
  // The system prompt, answered yes unless a test says otherwise.
  final prompt = _Unlock(true);

  Future<http.Response> server(http.Request request) async {
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
    if (request.url.host == 'game.example') {
      if (!serviceUp) throw http.ClientException('unreachable');
      expect(request.followRedirects, isFalse);
      expect(request.headers.containsKey('Authorization'), isFalse);
      delivered.add(request.url.toString());
      return http.Response('', 303, headers: {'location': '/start'});
    }
    switch (request.url.path) {
      case '/oidc/authorize/app':
        opened.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (refuse) return json({'redirect': refusal});
        return json({
          'ticket': ticket,
          'client': 'https://game.example',
          'account': {'email': 'ada@home.test'},
          'scopes': [
            {'scope': 'profile', 'value': 'Ada Lovelace'},
            {'scope': 'email', 'value': 'ada@home.test'},
          ],
          'links': [
            {
              'key': 'phone',
              'options': [
                {
                  'id': 'r1',
                  'key': 'phone',
                  'label': 'Phone',
                  'preview': '+49',
                },
              ],
            },
          ],
        });
      case '/oidc/authorize/consent':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        decisions.add(body);
        return json({'redirect': body['approve'] == true ? approved : denied});
      case '/api/collections/identities/records':
        return json({
          'items': [
            {
              'id': keyOnDevice ? 'id1' : 'elsewhere',
              'name': 'Ada',
              'certificate': identity.publicKeyPem,
              'fingerprint': 'cd' * 32,
              'user': 'u',
              'workspace': 'w',
              'isPrimary': true,
              'status': 'active',
            },
          ],
        });
      case '/api/challenges/request/evil':
        // A foreign server dressing an approval up as a challenge.
        return json({'nonce': '${SignInApproval.consentPrefix}$ticket'});
    }
    return json({'items': <Object>[]});
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'identity_priv_id1': identity.privateKeyPem,
    });
    await Stores.init(httpClient: MockClient(server), unlock: prompt);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            if (call.method == 'launch') {
              launched.add((call.arguments as Map)['url'] as String);
            }
            return true;
          },
        );
  });

  setUp(() {
    opened.clear();
    delivered.clear();
    serviceUp = true;
    decisions.clear();
    launched.clear();
    refuse = false;
    keyOnDevice = true;
    prompt.asked.clear();
    Stores.identities.identities.clear();
  });

  SignInRequest link({bool background = false}) => SignInRequest.fromQuery({
    'client_id': 'https://game.example',
    'redirect_uri': 'https://game.example/callback',
    'response_type': 'code',
    'scope': 'openid profile email',
    'state': 'st-1',
    'nonce': 'n-1',
    'code_challenge': 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    'code_challenge_method': 'S256',
    'claims': '{"userinfo":{"revoked_links":{"values":["phone"]}}}',
    if (background) 'revoked_return': 'background',
  })!;
  final request = link();

  Future<void> show(WidgetTester tester, [SignInRequest? r]) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: SignInApprovalScreen(request: r ?? request),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the request opens in the app, and nothing in a browser', (
    tester,
  ) async {
    await show(tester);

    expect(opened.single['params']['client_id'], 'https://game.example');
    expect(opened.single['params']['state'], 'st-1');
    expect(launched, isEmpty, reason: 'deciding happens here, not there');
    expect(find.text('Sign in to game.example'), findsOneWidget);
    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Your email address'), findsOneWidget);
    expect(find.text('Phone — +49'), findsOneWidget);
    expect(decisions, isEmpty);
  });

  testWidgets('an approval is signed with the key on this device', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Your email address'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    final sent = decisions.single;
    expect(sent['ticket'], ticket);
    expect(sent['approve'], isTrue);
    expect(sent['scopes'], ['profile']);
    expect(sent['links'], {'phone': 'r1'});
    expect(sent['identityId'], 'id1');
    expect(
      crypto.verifySignature(
        publicKeyPem: identity.publicKeyPem,
        message: '${SignInApproval.consentPrefix}$ticket',
        signatureBytes: base64.decode(sent['signature'] as String),
      ),
      isTrue,
    );
    expect(prompt.asked, ['Sign in to game.example']);
    expect(launched, [approved]);
    expect(find.text('You’re signed in to game.example'), findsOneWidget);
  });

  testWidgets('declining signs nothing and tells the service', (tester) async {
    await show(tester);
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();

    final sent = decisions.single;
    expect(sent['approve'], isFalse);
    expect(sent.containsKey('signature'), isFalse);
    expect(sent.containsKey('identityId'), isFalse);
    expect(prompt.asked, isEmpty, reason: 'declining needs no unlock');
    expect(launched, [denied]);
    expect(find.text('Sign-in declined'), findsOneWidget);
  });

  testWidgets('a refused request goes back to the service unasked', (
    tester,
  ) async {
    refuse = true;
    await show(tester);
    expect(decisions, isEmpty);
    expect(launched, [refusal]);
    expect(find.text('This sign-in can’t continue'), findsOneWidget);
  });

  testWidgets('a service that waits gets the answer from the app, and the '
      'person compares its code', (tester) async {
    final r = link(background: true);
    await show(tester, r);
    expect(opened.single['params'].containsKey('revoked_return'), isTrue);
    expect(find.text(Pkce.checkCode(r.challenge)), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(delivered, [approved]);
    expect(launched, isEmpty, reason: 'no browser in between');
    expect(find.textContaining('carries on from there'), findsOneWidget);
  });

  testWidgets('a waiting service declined hears it from the app too', (
    tester,
  ) async {
    await show(tester, link(background: true));
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(delivered, [denied]);
    expect(launched, isEmpty);
  });

  testWidgets('an unreachable waiting service gets the answer in the browser', (
    tester,
  ) async {
    serviceUp = false;
    await show(tester, link(background: true));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(delivered, isEmpty);
    expect(launched, [approved]);
  });

  testWidgets('an ordinary sign-in shows no check code', (tester) async {
    await show(tester);
    expect(find.text(Pkce.checkCode(request.challenge)), findsNothing);
  });

  Future<SignInConsent> consent() async =>
      (await Stores.signInApproval.open(request)).consent!;

  test(
    'without the person unlocking the device, nothing is approved',
    () async {
      final unlock = _Unlock(false);
      final approval = SignInApproval(
        Stores.api,
        Stores.crypto,
        Stores.identities,
        unlock,
      );
      await expectLater(
        approval.decide(await consent(), approve: true),
        throwsA(isA<SignInApprovalException>()),
      );
      expect(unlock.asked, ['Sign in to game.example']);
      expect(decisions, isEmpty);
    },
  );

  test('a device without an identity key cannot approve', () async {
    keyOnDevice = false;
    final unlock = _Unlock(true);
    final approval = SignInApproval(
      Stores.api,
      Stores.crypto,
      Stores.identities,
      unlock,
    );
    await expectLater(
      approval.decide(await consent(), approve: true),
      throwsA(isA<SignInApprovalException>()),
    );
    expect(unlock.asked, isEmpty, reason: 'no prompt for what cannot happen');
    expect(decisions, isEmpty);
  });

  test('a challenge that is really an approval is never signed', () async {
    await expectLater(
      Stores.handshake.prepare(
        scope: 'request',
        slug: 'evil',
        identityId: 'id1',
      ),
      throwsFormatException,
    );
  });
}
