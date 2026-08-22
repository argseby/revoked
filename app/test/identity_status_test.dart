import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/identity_status_assertion.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/services/crypto_service.dart';

/// Hex decoder matching the one inside DomainVerificationService.
Uint8List? _decodeHex(String hex) {
  if (hex.isEmpty || hex.length.isOdd) return null;
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    if (byte == null) return null;
    out[i] = byte;
  }
  return out;
}

void main() {
  final crypto = CryptoService();

  late Map<String, dynamic> fixture;
  late String rootPem;
  late String domain;
  late String fingerprint;
  late DateTime issuedAt;

  setUpAll(() {
    final file = File('test/fixtures/identity_status.json');
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'Regenerate with: go run app/tool/gen_identity_status_fixture.go '
          '> app/test/fixtures/identity_status.json',
    );
    fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    rootPem = fixture['publicKeyPem'] as String;
    domain = fixture['domain'] as String;
    fingerprint = fixture['fingerprint'] as String;
    issuedAt = DateTime.fromMillisecondsSinceEpoch(
      (fixture['issuedAtUnix'] as int) * 1000,
      isUtc: true,
    );
  });

  IdentityStatusAssertion assertionFor(String key) {
    final parsed = IdentityStatusAssertion.fromJson(
      fixture[key] as Map<String, dynamic>,
    );
    expect(parsed, isNotNull, reason: 'fixture $key did not parse');
    return parsed!;
  }

  IdentityStatusBody? verify(
    IdentityStatusAssertion assertion, {
    String? expectDomain,
    String? expectFingerprint,
    DateTime? now,
  }) {
    return IdentityStatusBody.verified(
      assertion: assertion,
      rootPublicKeyPem: rootPem,
      expectDomain: expectDomain ?? domain,
      expectFingerprint: expectFingerprint ?? fingerprint,
      now: now ?? issuedAt,
      verifySignature: crypto.verifySignature,
      decodeHex: _decodeHex,
    );
  }

  group('identity status assertion', () {
    // The whole point of the fixture: these bytes came out of the Go server,
    // so this fails if the two sides ever stop agreeing on what was signed.
    test('verifies output produced by the Go server', () {
      final body = verify(assertionFor('active'));
      expect(body, isNotNull);
      expect(body!.isActive, isTrue);
      expect(body.fingerprint, fingerprint);
      expect(body.domain, domain);
      expect(body.type, IdentityStatusAssertion.type);
    });

    test('reads a revocation, with its reason and time', () {
      final body = verify(assertionFor('revoked'));
      expect(body, isNotNull);
      expect(body!.isRevoked, isTrue);
      expect(body.reason, 'membership_ended');
      expect(body.revokedAt, isNotNull);
      expect(body.revokedAt!.isBefore(issuedAt), isTrue);
    });

    // An answer that never went stale would be no better than the ten-year
    // certificate it is supposed to qualify.
    test('refuses an answer past its expiry', () {
      final body = verify(
        assertionFor('active'),
        now: issuedAt.add(const Duration(hours: 2)),
      );
      expect(body, isNull);
    });

    test('refuses an answer issued in the future', () {
      final body = verify(
        assertionFor('active'),
        now: issuedAt.subtract(const Duration(hours: 2)),
      );
      expect(body, isNull);
    });

    // The issuing server is someone else's machine, so its clock is not this
    // one's. Rejecting an answer for being seconds ahead reads as an unverified
    // identity, not as a clock problem, and would make every identity from a
    // slightly fast server unverifiable.
    test('tolerates an issuer whose clock runs a little ahead', () {
      final body = verify(
        assertionFor('active'),
        now: issuedAt.subtract(const Duration(seconds: 30)),
      );
      expect(body, isNotNull);
    });

    // A genuine "active" for one identity must not vouch for another, or the
    // holder of any live identity could cover for a revoked one.
    test('refuses an answer about a different identity', () {
      final body = verify(assertionFor('active'), expectFingerprint: 'ab' * 32);
      expect(body, isNull);
    });

    test('refuses an answer for a different domain', () {
      final body = verify(assertionFor('active'), expectDomain: 'evil.test');
      expect(body, isNull);
    });

    // The payload is what gets checked, so rewriting it is the only way to
    // change the answer — and it breaks the signature.
    test('refuses a payload rewritten to say active', () {
      final revoked = assertionFor('revoked');
      final body =
          jsonDecode(utf8.decode(revoked.signedBytes()!))
              as Map<String, dynamic>;
      body['status'] = 'active';

      final forged = IdentityStatusAssertion(
        payload: base64Url
            .encode(utf8.encode(jsonEncode(body)))
            .replaceAll('=', ''),
        signature: revoked.signature,
      );
      expect(verify(forged), isNull);
    });

    test('refuses a signature from another key', () {
      final active = assertionFor('active');
      final other = crypto.generateIdentity(commonName: 'impostor');
      final body = IdentityStatusBody.verified(
        assertion: active,
        rootPublicKeyPem: other.publicKeyPem,
        expectDomain: domain,
        expectFingerprint: fingerprint,
        now: issuedAt,
        verifySignature: crypto.verifySignature,
        decodeHex: _decodeHex,
      );
      expect(body, isNull);
    });

    test('refuses malformed input rather than throwing', () {
      expect(IdentityStatusAssertion.fromJson(null), isNull);
      expect(IdentityStatusAssertion.fromJson('nope'), isNull);
      expect(IdentityStatusAssertion.fromJson({'payload': 'x'}), isNull);
      expect(
        verify(
          const IdentityStatusAssertion(
            payload: 'not-base64!!',
            signature: 'zz',
          ),
        ),
        isNull,
      );
    });
  });

  group('trust verdict', () {
    // Revoked is a hard stop like spoofed, for the opposite reason: nothing
    // was forged, the vouching simply stopped.
    test('a revoked verdict blocks submission', () {
      final verdict = TrustVerdict.revoked(
        domain: 'bmw.example',
        reason: 'withdrawn',
      );
      expect(verdict.state, TrustState.revoked);
      expect(verdict.allowsSubmit, isFalse);
    });

    test('soft states still allow submission behind a confirmation', () {
      expect(
        TrustVerdict.unverified(domain: 'x', reason: 'y').allowsSubmit,
        isTrue,
      );
      expect(
        TrustVerdict.dnsMissing(domain: 'x', reason: 'y').allowsSubmit,
        isTrue,
      );
    });
  });
}
