import 'package:flutter_test/flutter_test.dart';

import 'package:revoked_app/core/models/attestation_ask.dart';
import 'package:revoked_app/core/utils/deep_links.dart';

void main() {
  final fingerprint = 'ab' * 32;

  test('an ask survives the trip through its link', () {
    final ask = AttestationAsk(
      type: 'membership',
      claims: AttestationAsk.splitClaims('member_since, board board'),
      fingerprint: fingerprint,
      name: 'Laptop',
    );
    expect(ask.claims, ['member_since', 'board']);

    final location = DeepLinks.locationFor(Uri.parse(ask.link));
    expect(location, startsWith('/attestations?'));
    final back = AttestationAsk.fromQuery(Uri.parse(location!).queryParameters);
    expect(back?.type, 'membership');
    expect(back?.claims, ['member_since', 'board']);
    expect(back?.fingerprint, fingerprint);
    expect(back?.name, 'Laptop');
  });

  test('a half-right ask fills in nothing', () {
    Map<String, String> q(Map<String, String> over) => {
      'type': 'membership',
      'for': fingerprint,
      ...over,
    };
    expect(AttestationAsk.fromQuery(q({})), isNotNull);
    expect(AttestationAsk.fromQuery(q({'for': 'not-a-fingerprint'})), isNull);
    expect(AttestationAsk.fromQuery(q({'type': 'two words'})), isNull);
    expect(AttestationAsk.fromQuery(q({'claims': 'ok, 9bad'})), isNull);
    expect(
      DeepLinks.locationFor(Uri.parse('revoked://attest?type=x&for=zz')),
      isNull,
    );
  });
}
