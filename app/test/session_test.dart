import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:revoked_app/core/network/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A session must end when the server rejects it, and survive when the network
/// merely fails. Treating those the same signed people out for being offline.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('a rejected session notifies once, and only when signed in', () async {
    var notified = 0;
    final client = ApiClient(
      httpClient: _Stub((_) => http.Response('{}', 401)),
      secureStorage: const FlutterSecureStorage(),
    )..onUnauthorized = () => notified++;

    // Signed out: a 401 is just a failed request, not an expiry.
    await expectLater(client.get('/api/x'), throwsA(isA<ApiException>()));
    expect(notified, 0);

    await client.saveAuthState('token', {'id': '1'});
    await expectLater(client.get('/api/x'), throwsA(isA<ApiException>()));
    expect(notified, 1);
  });

  test(
    'a stalled server times out rather than hanging',
    () async {
      final client = ApiClient(
        httpClient: _Stub((_) async {
          await Future<void>.delayed(const Duration(seconds: 60));
          return http.Response('{}', 200);
        }),
        secureStorage: const FlutterSecureStorage(),
      );

      await expectLater(
        client.get('/api/x'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'request_timeout'),
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('logout clears the token and every handshake', () async {
    SharedPreferences.setMockInitialValues({
      'handshake_link_abc': 'tok',
      'handshake_request_def': 'tok',
      'server_base_url': 'https://example.com',
    });
    final client = ApiClient(
      httpClient: _Stub((_) => http.Response('{}', 200)),
      secureStorage: const FlutterSecureStorage(),
    );
    await client.saveAuthState('token', {'id': '1'});

    await client.clearAuthState();

    final prefs = await SharedPreferences.getInstance();
    expect(client.isAuthenticated, isFalse);
    expect(prefs.getKeys().where((k) => k.startsWith('handshake_')), isEmpty);
    // Unrelated settings survive.
    expect(prefs.getString('server_base_url'), 'https://example.com');
  });
}

class _Stub extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest) responder;
  _Stub(dynamic fn) : responder = ((r) async => await fn(r));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = await responder(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(r.body)),
      r.statusCode,
    );
  }
}
