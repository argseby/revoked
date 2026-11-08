import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/services/domain_verification_service.dart';

/// An attestation offer is made by a server, not one of its identities, so its
/// check is the domain's DNS pin against the server's root key alone. Before,
/// offers were asked about an identity with no signature and always came back
/// "Identity not verified".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const pem = 'root-public-key';
  final crypto = CryptoService();
  final fingerprint = crypto.sha256Hex(pem);

  DomainVerificationService service({required String pinned}) =>
      DomainVerificationService(
        crypto: crypto,
        httpClient: MockClient((request) async {
          if (request.url.host.contains('dns')) {
            return http.Response(
              jsonEncode({
                'Answer': [
                  {'data': '"v=revoked1; k=sha256/$pinned"'},
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'publicKey': pem, 'fingerprint': fingerprint}),
            200,
          );
        }),
      );

  test('a server whose domain pins its root key is verified', () async {
    final verdict = await service(pinned: fingerprint).verifyServer(
      claimedDomain: 'example.com',
      expectedRootFingerprint: fingerprint,
    );
    expect(verdict.state, TrustState.verified);
    expect(verdict.rootFingerprint, fingerprint);
  });

  test('a domain pinning another key is spoofed', () async {
    final verdict = await service(
      pinned: 'b' * 64,
    ).verifyServer(claimedDomain: 'example.com');
    expect(verdict.state, TrustState.spoofed);
  });

  test(
    'an offer naming another root key than the domain pins is spoofed',
    () async {
      final verdict = await service(pinned: fingerprint).verifyServer(
        claimedDomain: 'example.com',
        expectedRootFingerprint: 'c' * 64,
      );
      expect(verdict.state, TrustState.spoofed);
    },
  );
}
