import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/services/domain_verification_service.dart';

/// The domain check is the product's whole claim. Every way it can fail has to
/// end in a verdict the submit gate can act on — never in an exception that
/// escapes, and never in silence.
void main() {
  DomainVerificationService serviceReturning(_Responder responder) =>
      DomainVerificationService(
        httpClient: _Stub(responder),
        crypto: CryptoService(),
      );

  Future<TrustVerdict> run(DomainVerificationService s) => s.verify(
    claimedDomain: 'example.com',
    identityFingerprint: 'abc',
    parentSignatureHex: 'aa',
  );

  test('a captive portal answering HTML is not fatal', () async {
    final verdict = await run(
      serviceReturning((_) => http.Response('<html>login</html>', 200)),
    );
    expect(verdict.state, TrustState.dnsMissing);
    expect(verdict.reason, contains('captive portal'));
  });

  test(
    'a stalled resolver times out instead of hanging',
    () async {
      final verdict = await run(
        serviceReturning((_) async {
          await Future<void>.delayed(const Duration(seconds: 30));
          return http.Response('{}', 200);
        }),
      );
      expect(verdict.state, TrustState.dnsMissing);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test('it falls back to the second resolver', () async {
    var calls = 0;
    final verdict = await run(
      serviceReturning((uri) {
        calls++;
        if (uri.host == 'cloudflare-dns.com') throw const SocketishError();
        if (uri.host == 'dns.google') {
          return http.Response(
            jsonEncode({
              'Answer': [
                {'data': '"v=revoked1; k=sha256/${'a' * 64}"'},
              ],
            }),
            200,
          );
        }
        // /api/server for the domain
        return http.Response('nope', 500);
      }),
    );
    expect(calls, greaterThanOrEqualTo(2));
    // Got past DNS on the fallback, so the failure is the server fetch.
    expect(verdict.state, TrustState.unverified);
  });

  test('a server answering non-JSON is unverified, not a crash', () async {
    final verdict = await run(
      serviceReturning((uri) {
        if (uri.host case 'cloudflare-dns.com' || 'dns.google') {
          return http.Response(
            jsonEncode({
              'Answer': [
                {'data': '"v=revoked1; k=sha256/${'a' * 64}"'},
              ],
            }),
            200,
          );
        }
        return http.Response('<html>hi</html>', 200);
      }),
    );
    expect(verdict.state, TrustState.unverified);
  });
}

class SocketishError implements Exception {
  const SocketishError();
}

typedef _Responder = FutureOr<http.Response> Function(Uri uri);

class _Stub extends http.BaseClient {
  final _Responder responder;
  _Stub(this.responder);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = await responder(request.url);
    return http.StreamedResponse(
      Stream.value(utf8.encode(r.body)),
      r.statusCode,
    );
  }
}
