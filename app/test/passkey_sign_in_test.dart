import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/utils/pkce.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'signing in goes through the server page and comes back by code',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});

      final exchanges = <Map<String, dynamic>>[];
      final api = ApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/passkeys/token');
          exchanges.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'token': 'session-token',
              'record': {'id': 'u1', 'email': 'a@example.com'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final opened = <Uri>[];
      final auth = AuthStore(
        api,
        openBrowser: (page) async {
          opened.add(page);
          return true;
        },
      );

      // Nothing was asked yet: a link out of nowhere is not an answer.
      expect(
        await auth.completeSignIn(Uri.parse('revoked://auth?code=c&state=s')),
        isFalse,
      );

      expect(await auth.beginSignIn(), isTrue);
      expect(auth.isAwaitingBrowser, isTrue);
      final page = opened.single;
      expect(page.toString(), startsWith('${api.baseUrl}/passkey?'));
      expect(page.queryParameters['mode'], 'signin');
      final challenge = page.queryParameters['challenge']!;
      final state = page.queryParameters['state']!;

      // Someone else's state does not spend this sign-in.
      expect(
        await auth.completeSignIn(
          Uri.parse('revoked://auth?code=stolen&state=other'),
        ),
        isFalse,
      );
      expect(exchanges, isEmpty);
      expect(auth.isAuthenticated, isFalse);

      expect(
        await auth.completeSignIn(
          Uri.parse('revoked://auth?code=one-time&state=$state'),
        ),
        isTrue,
      );
      expect(exchanges.single['code'], 'one-time');
      // The verifier sent is the one the page's challenge was made from.
      expect(Pkce.challenge(exchanges.single['verifier'] as String), challenge);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.userEmail, 'a@example.com');
      expect(auth.isAwaitingBrowser, isFalse);

      // The same link again answers nothing.
      expect(
        await auth.completeSignIn(
          Uri.parse('revoked://auth?code=one-time&state=$state'),
        ),
        isFalse,
      );
      expect(exchanges, hasLength(1));
    },
  );

  test('creating an account opens the page on signup', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final opened = <Uri>[];
    final auth = AuthStore(
      ApiClient(httpClient: MockClient((_) async => http.Response('{}', 200))),
      openBrowser: (page) async {
        opened.add(page);
        return true;
      },
    );
    await auth.beginSignIn(signup: true);
    expect(opened.single.queryParameters['mode'], 'signup');
    await auth.cancelSignIn();
    expect(auth.isAwaitingBrowser, isFalse);
  });

  test('the challenge is the S256 of the verifier', () {
    // RFC 7636, appendix B.
    expect(
      Pkce.challenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });
}
