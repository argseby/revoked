import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/utils/sd_jwt.dart';

/// The app presents and the server verifies, so the two must agree on what a
/// key binding commits to. The credential here was issued by the server's own
/// code (regenerate with tool/gen_sd_jwt_fixture.sh); the same script has the
/// app present it, and the Go tests verify that presentation.
void main() {
  late Map<String, dynamic> fixture;
  late String credential;

  setUpAll(() {
    final file = File('test/fixtures/sd_jwt.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Regenerate with tool/gen_sd_jwt_fixture.sh',
    );
    fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    credential = fixture['credential'] as String;
  });

  Uint8List unb64(String s) => base64Url.decode(base64Url.normalize(s));

  test('a server-issued credential is taken apart', () {
    final parsed = SdJwtCredential.parse(credential);
    expect(parsed.issuer, 'https://fixture.test');
    expect(parsed.type, 'membership');
    expect(parsed.header['typ'], 'dc+sd-jwt');
    expect(parsed.disclosures.map((d) => d.name).toSet(), {
      'name',
      'age_over_18',
      'member_no',
    });
    final byName = {for (final d in parsed.disclosures) d.name: d.value};
    expect(byName['name'], 'Ada Lovelace');
    expect(byName['age_over_18'], isTrue);
    expect(byName['member_no'], 42);
    // Nothing it states is readable without a disclosure.
    expect(parsed.payload.containsKey('name'), isFalse);
  });

  test('what a key binding commits to matches the server, byte for byte', () {
    final parsed = SdJwtCredential.parse(credential);
    final disclose = (fixture['disclose'] as List).cast<String>();
    final signed = parsed.signedPart(disclose);
    expect(signed, fixture['signedPart']);
    expect(sdDigest(signed), fixture['sdHash']);
    // Withheld claims are not part of it.
    expect(parsed.signedPart(const []), '${parsed.jwt}~');
  });

  test('a presentation carries only what was chosen, bound to the key', () {
    final crypto = CryptoService();
    final identity = crypto.generateIdentity(commonName: 'holder');
    final at = DateTime.fromMillisecondsSinceEpoch(1800003600 * 1000);

    final presentation = presentSdJwt(
      credential: credential,
      disclose: const ['age_over_18'],
      audience: 'https://shop.test',
      nonce: 'nonce-1',
      privateKeyPem: identity.privateKeyPem,
      now: at,
    );

    final parts = presentation.split('~');
    final parsed = SdJwtCredential.parse(credential);
    expect(parts.first, parsed.jwt);
    expect(parts.length, 3, reason: 'the JWT, one disclosure, the key binding');
    final withheld = parsed.disclosures.firstWhere((d) => d.name == 'name');
    expect(presentation.contains(withheld.raw), isFalse);

    final binding = parts.last.split('.');
    expect(binding.length, 3);
    final header = jsonDecode(utf8.decode(unb64(binding[0]))) as Map;
    final payload = jsonDecode(utf8.decode(unb64(binding[1]))) as Map;
    expect(header, {'alg': 'ES256', 'typ': 'kb+jwt'});
    expect(payload['aud'], 'https://shop.test');
    expect(payload['nonce'], 'nonce-1');
    expect(payload['iat'], 1800003600);
    expect(payload['sd_hash'], sdDigest('${parts[0]}~${parts[1]}~'));

    // ES256 as JWS writes it: r and s side by side, not ASN.1.
    final signature = unb64(binding[2]);
    expect(signature.length, 64);
    BigInt big(List<int> bytes) =>
        bytes.fold(BigInt.zero, (v, b) => (v << 8) | BigInt.from(b));
    final verified = CryptoUtils.ecVerify(
      CryptoUtils.ecPublicKeyFromPem(identity.publicKeyPem),
      Uint8List.fromList(utf8.encode('${binding[0]}.${binding[1]}')),
      pc.ECSignature(big(signature.sublist(0, 32)), big(signature.sublist(32))),
      algorithm: CryptoService.ecdsaAlgorithm,
    );
    expect(verified, isTrue);
  });

  test('a claim the credential does not hold cannot be presented', () {
    final identity = CryptoService().generateIdentity(commonName: 'holder');
    expect(
      () => presentSdJwt(
        credential: credential,
        disclose: const ['shoe_size'],
        audience: 'https://shop.test',
        nonce: 'nonce-1',
        privateKeyPem: identity.privateKeyPem,
      ),
      throwsFormatException,
    );
  });

  test('what is not a credential is not read as one', () {
    expect(SdJwtCredential.tryParse('nonsense'), isNull);
    expect(SdJwtCredential.tryParse('a.b.c'), isNull);
    expect(SdJwtCredential.tryParse('${credential}not-base64!~'), isNull);
  });
}
