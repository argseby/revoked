import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/services/domain_verification_service.dart';

/// The responder waits on this chain before the form appears, so its shape
/// matters: the two network hops run together, the DoH resolvers race, and a
/// conclusive verdict is not re-walked within a session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  persistence();
  prewarming();
  resolverAgreement();
  survivesRestart();

  http.Client trackingClient(
    List<String> hits, {
    Duration delay = Duration.zero,
  }) {
    return MockClient((request) async {
      hits.add(request.url.host);
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (request.url.host.contains('dns')) {
        return http.Response(
          jsonEncode({
            'Answer': [
              {'data': '"v=revoked1; k=sha256/${'a' * 64}"'},
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({'publicKey': 'not-a-real-pem', 'assertion': ''}),
        200,
      );
    });
  }

  test('the DNS pin and the server assertion are fetched together', () async {
    final hits = <String>[];
    final service = DomainVerificationService(
      httpClient: trackingClient(hits, delay: const Duration(milliseconds: 80)),
      crypto: CryptoService(),
    );

    final started = DateTime.now();
    await service.verify(
      claimedDomain: 'example.com',
      identityFingerprint: 'abc',
      parentSignatureHex: 'aa',
    );
    final elapsed = DateTime.now().difference(started);

    // Serially this is >= 160ms; in parallel it stays near one hop.
    expect(
      elapsed.inMilliseconds,
      lessThan(160),
      reason: 'the two hops must not run one after the other',
    );
    expect(hits.any((h) => h.contains('dns')), isTrue);
    expect(hits.any((h) => h == 'example.com'), isTrue);
  });

  test('a conclusive verdict is reused instead of re-walked', () async {
    final hits = <String>[];
    final service = DomainVerificationService(
      httpClient: trackingClient(hits),
      crypto: CryptoService(),
    );

    Future<TrustVerdict> run() => service.verify(
      claimedDomain: 'example.com',
      identityFingerprint: 'abc',
      parentSignatureHex: 'aa',
    );

    final first = await run();
    final callsAfterFirst = hits.length;
    final second = await run();

    if (first.state == TrustState.verified ||
        first.state == TrustState.spoofed) {
      expect(
        hits.length,
        callsAfterFirst,
        reason: 'a conclusive verdict must not hit the network again',
      );
      expect(second.state, first.state);
    } else {
      // An inconclusive verdict is deliberately not cached: a transient
      // failure must not pin "unverified" for the whole session.
      expect(hits.length, greaterThan(callsAfterFirst));
    }
  });
}

/// The cache survives restarts so a returning viewer is not made to wait —
/// but it is a rendering hint, never the answer submitted on. These pin the
/// properties that keep it from vouching for a server that stopped
/// deserving it.
void persistence() {
  test('a stored verdict is offered on a fresh service instance', () async {
    SharedPreferences.setMockInitialValues({});
    final hits = <String>[];

    final first = DomainVerificationService(
      httpClient: MockClient((request) async {
        hits.add(request.url.host);
        return http.Response(jsonEncode({'Answer': []}), 200);
      }),
      crypto: CryptoService(),
    );
    // Nothing conclusive here, so nothing may be stored.
    await first.verify(
      claimedDomain: 'example.com',
      identityFingerprint: 'abc',
      parentSignatureHex: 'aa',
    );

    final second = DomainVerificationService(crypto: CryptoService());
    await second.loadCache();
    expect(
      second.cachedVerdict(
        claimedDomain: 'example.com',
        identityFingerprint: 'abc',
      ),
      isNull,
      reason: 'an inconclusive verdict must never be persisted',
    );
  });

  test('an expired entry is not offered', () async {
    final stale = DateTime.now().subtract(
      DomainVerificationService.cacheTtl + const Duration(minutes: 1),
    );
    SharedPreferences.setMockInitialValues({
      'trust_verdict_cache': jsonEncode({
        'example.com|abc': {
          'state': 'verified',
          'domain': 'example.com',
          'reason': 'r',
          'rootFingerprint': 'f' * 64,
          'identityFingerprint': 'abc',
          'checkedAt': stale.toIso8601String(),
        },
      }),
    });

    final service = DomainVerificationService(crypto: CryptoService());
    await service.loadCache();

    expect(
      service.cachedVerdict(
        claimedDomain: 'example.com',
        identityFingerprint: 'abc',
      ),
      isNull,
      reason: 'past the TTL a stored verdict must read as unknown',
    );
  });

  test('a tampered or partial entry degrades to no cache', () async {
    SharedPreferences.setMockInitialValues({
      'trust_verdict_cache': jsonEncode({
        // 'verified' with no root fingerprint is not a verdict this service
        // could have produced.
        'evil.example|abc': {
          'state': 'verified',
          'domain': 'evil.example',
          'checkedAt': DateTime.now().toIso8601String(),
        },
        'broken|x': {'state': 'nonsense'},
      }),
    });

    final service = DomainVerificationService(crypto: CryptoService());
    await service.loadCache();

    expect(
      service.cachedVerdict(
        claimedDomain: 'evil.example',
        identityFingerprint: 'abc',
      ),
      isNull,
    );
  });
}

/// The check cannot start until the probe returns a fingerprint, but neither
/// network hop depends on one — and the link already names the server. These
/// pin that the hops overlap the probe instead of queueing behind it.
void prewarming() {
  test('prewarm makes a later verify reuse the in-flight hops', () async {
    SharedPreferences.setMockInitialValues({});
    var hops = 0;
    final service = DomainVerificationService(
      httpClient: MockClient((request) async {
        hops++;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        if (request.url.host.contains('dns')) {
          return http.Response(jsonEncode({'Answer': []}), 200);
        }
        return http.Response(jsonEncode({'publicKey': 'x'}), 200);
      }),
      crypto: CryptoService(),
    );

    service.prewarm('example.com');
    // Long enough for the hops to be in flight, not to have finished.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final hopsAfterPrewarm = hops;

    await service.verify(
      claimedDomain: 'example.com',
      identityFingerprint: 'abc',
      parentSignatureHex: 'aa',
    );

    expect(
      hops,
      hopsAfterPrewarm,
      reason: 'verify must join the prewarmed hops, not start new ones',
    );
  });

  test('concurrent checks for one domain share a single round-trip', () async {
    SharedPreferences.setMockInitialValues({});
    var hops = 0;
    final service = DomainVerificationService(
      httpClient: MockClient((request) async {
        hops++;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        if (request.url.host.contains('dns')) {
          return http.Response(jsonEncode({'Answer': []}), 200);
        }
        return http.Response(jsonEncode({'publicKey': 'x'}), 200);
      }),
      crypto: CryptoService(),
    );

    await Future.wait([
      service.verify(
        claimedDomain: 'example.com',
        identityFingerprint: 'a',
        parentSignatureHex: 'aa',
      ),
      service.verify(
        claimedDomain: 'example.com',
        identityFingerprint: 'b',
        parentSignatureHex: 'bb',
      ),
    ]);

    // Two identities, one domain: the DoH racers plus one server fetch, not
    // double that.
    expect(hops, lessThanOrEqualTo(3));
  });
}

/// Racing the resolvers must not change the answer, only the wait. Public
/// resolvers propagate unevenly, so one of them answering "no record" while
/// another holds it is normal — and reporting that as unverified told people
/// their published record was missing.
void resolverAgreement() {
  http.Client resolvers({
    required String emptyHost,
    required String recordHost,
  }) {
    return MockClient((request) async {
      if (request.url.host == emptyHost) {
        // Answers first, and finds nothing.
        return http.Response(jsonEncode({'Answer': []}), 200);
      }
      if (request.url.host == recordHost) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return http.Response(
          jsonEncode({
            'Answer': [
              {'data': '"v=revoked1; k=sha256/${'a' * 64}"'},
            ],
          }),
          200,
        );
      }
      // The server assertion hop.
      return http.Response(jsonEncode({'publicKey': 'pem'}), 200);
    });
  }

  test('a record found by the slower resolver still counts', () async {
    SharedPreferences.setMockInitialValues({});
    final service = DomainVerificationService(
      httpClient: resolvers(
        emptyHost: 'dns.google',
        recordHost: 'cloudflare-dns.com',
      ),
      crypto: CryptoService(),
    );

    final verdict = await service.verify(
      claimedDomain: 'example.com',
      identityFingerprint: 'abc',
      parentSignatureHex: 'aa',
    );

    expect(
      verdict.state,
      isNot(TrustState.dnsMissing),
      reason: 'an empty answer from one resolver must not win the race',
    );
  });

  test('every resolver agreeing on empty is dnsMissing', () async {
    SharedPreferences.setMockInitialValues({});
    final service = DomainVerificationService(
      httpClient: MockClient(
        (request) async => http.Response(jsonEncode({'Answer': []}), 200),
      ),
      crypto: CryptoService(),
    );

    final verdict = await service.verify(
      claimedDomain: 'example.com',
      identityFingerprint: 'abc',
      parentSignatureHex: 'aa',
    );

    expect(verdict.state, TrustState.dnsMissing);
  });
}

/// A verdict reached before a restart must be on screen at the next launch,
/// not re-earned through another spinner.
void survivesRestart() {
  test('a conclusive verdict is readable by a fresh instance', () async {
    SharedPreferences.setMockInitialValues({});
    const pem = 'FAKE-PEM-CONTENT';
    final pin = CryptoService().sha256Hex(pem);

    final client = MockClient((request) async {
      if (request.url.host.contains('dns')) {
        return http.Response(
          jsonEncode({
            'Answer': [
              {'data': '"v=revoked1; k=sha256/$pin"'},
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({'publicKey': pem, 'fingerprint': pin}),
        200,
      );
    });

    final before = DomainVerificationService(
      httpClient: client,
      crypto: CryptoService(),
    );
    final verdict = await before.verify(
      claimedDomain: 'example.com',
      identityFingerprint: 'abc',
      parentSignatureHex: 'aa',
    );
    expect(verdict.state, TrustState.spoofed, reason: 'conclusive, so stored');

    // A new instance is what a relaunch produces.
    final after = DomainVerificationService(crypto: CryptoService());
    await after.loadCache();

    expect(
      after
          .cachedVerdict(
            claimedDomain: 'example.com',
            identityFingerprint: 'abc',
          )
          ?.state,
      TrustState.spoofed,
    );
  });
}
