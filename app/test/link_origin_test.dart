import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/testing.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Links carry the server they live on, because every instance is self-hosted
/// and a slug only means something to the server that minted it. The embedded
/// origin routes the fetch and must never route the session token with it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeepLinks with origins', () {
    test('builders embed the origin as a path segment', () {
      expect(
        DeepLinks.share('abc', origin: 'api.revoked.link'),
        'revoked://s/api.revoked.link/abc',
      );
      expect(
        DeepLinks.request('abc', origin: 'localhost:3000'),
        'revoked://r/localhost:3000/abc',
      );
      expect(DeepLinks.share('abc'), 'revoked://s/abc');
    });

    test('two segments parse as origin + slug, one as legacy slug', () {
      final withOrigin = DeepLinks.parse(
        Uri.parse('revoked://s/api.revoked.link/abc'),
      );
      expect(withOrigin, isNotNull);
      expect(withOrigin!.origin, 'api.revoked.link');
      expect(withOrigin.slug, 'abc');

      final withPort = DeepLinks.parse(
        Uri.parse('revoked://r/localhost:3000/xyz'),
      );
      expect(withPort!.origin, 'localhost:3000');
      expect(withPort.slug, 'xyz');

      final legacy = DeepLinks.parse(Uri.parse('revoked://s/abc'));
      expect(legacy!.origin, isNull);
      expect(legacy.slug, 'abc');
    });

    test('locationFor carries the origin as a query parameter', () {
      expect(
        DeepLinks.locationFor(Uri.parse('revoked://s/api.revoked.link/abc')),
        '/s/abc?o=api.revoked.link',
      );
      expect(DeepLinks.locationFor(Uri.parse('revoked://s/abc')), '/s/abc');
    });

    test(
      'a malformed origin makes the link unrecognizable, not half-trusted',
      () {
        expect(
          DeepLinks.parse(Uri.parse('revoked://s/user@evil.example/abc')),
          isNull,
        );
      },
    );
  });

  group('foreign-origin fetches', () {
    late List<http.Request> seen;
    late ApiClient api;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      seen = [];
      api = ApiClient(
        httpClient: MockClient((request) async {
          seen.add(request);
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );
      await api.setBaseUrl('https://my.server.example');
    });

    test('a foreign fetch never carries the session token', () async {
      // The token is a credential for my.server.example and nothing else; a
      // link is exactly the vector an attacker would use to exfiltrate it.
      await api.saveAuthState('secret-token', const {'id': 'u1'});

      await api.getFromOrigin('other.example', '/api/public/links/abc');

      expect(
        seen.single.url.toString(),
        'https://other.example/api/public/links/abc',
      );
      expect(seen.single.headers, isNot(contains('Authorization')));
    });

    test('the same call against the own origin keeps the token', () async {
      await api.saveAuthState('secret-token', const {'id': 'u1'});

      await api.getFromOrigin('my.server.example', '/api/public/links/abc');

      expect(
        seen.single.url.toString(),
        'https://my.server.example/api/public/links/abc',
      );
      expect(seen.single.headers['Authorization'], contains('secret-token'));
    });

    test('a foreign origin is forced onto https, loopback excepted', () {
      expect(ApiClient.publicBaseFor('other.example'), 'https://other.example');
      expect(
        ApiClient.publicBaseFor('localhost:3000'),
        'http://localhost:3000',
      );
      expect(ApiClient.publicBaseFor('evil.example/path'), isNull);
    });

    test('a foreign 401 does not end the local session', () async {
      var sessionEnded = false;
      final rejecting = ApiClient(
        httpClient: MockClient(
          (request) async => http.Response('{"status":401}', 401),
        ),
      );
      await rejecting.setBaseUrl('https://my.server.example');
      await rejecting.saveAuthState('secret-token', const {'id': 'u1'});
      rejecting.onUnauthorized = () => sessionEnded = true;

      await expectLater(
        rejecting.getFromOrigin('other.example', '/api/public/links/abc'),
        throwsA(isA<ApiException>()),
      );
      expect(
        sessionEnded,
        isFalse,
        reason: 'a stranger\'s 401 must not log the user out locally',
      );
    });
  });
}
