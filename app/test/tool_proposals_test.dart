import 'package:flutter_test/flutter_test.dart';

import 'package:revoked_app/core/models/attestation_ask.dart';
import 'package:revoked_app/core/models/check_proposal.dart';
import 'package:revoked_app/core/models/request_proposal.dart';
import 'package:revoked_app/core/utils/deep_links.dart';

void main() {
  const client = 'http://localhost:47303';

  test('a request proposal reaches the requests screen whole', () {
    final location = DeepLinks.locationFor(
      Uri.parse(
        'revoked://pr?template=Event%20registration&label=Summer%20party'
        '&days=14&from=Assistant&client=$client&ref=summer',
      ),
    );
    expect(location, startsWith('/requests?'));
    final query = Uri.parse(location!).queryParameters;
    expect(query['propose'], '1');
    final back = RequestProposal.fromQuery(query)!;
    expect(back.template, 'Event registration');
    expect(back.label, 'Summer party');
    expect(back.days, 14);
    expect(back.proposer.client, client);
    expect(back.proposer.ref, 'summer');
    expect(back.proposer.label, 'Assistant');
  });

  test('a check proposal reaches the attestations screen whole', () {
    final location = DeepLinks.locationFor(
      Uri.parse(
        'revoked://check?type=membership&issuers=Chess-Club.org'
        '&claims=member_since,board&client=$client&ref=door',
      ),
    );
    expect(location, startsWith('/attestations?'));
    final query = Uri.parse(location!).queryParameters;
    expect(query['check'], '1');
    final back = CheckProposal.fromQuery(query)!;
    expect(back.issuers, ['chess-club.org']);
    expect(back.claims, ['member_since', 'board']);
    expect(back.proposer.host, 'localhost');
  });

  test('an attestation ask keeps the tool that sent it', () {
    final ask = AttestationAsk.fromQuery({
      'type': 'membership',
      'for': 'ab' * 32,
      'name': 'Assistant',
      'client': client,
      'ref': 'member-42',
    })!;
    final back = AttestationAsk.fromQuery(ask.toQuery())!;
    expect(back.proposer.client, client);
    expect(back.proposer.ref, 'member-42');
    expect(back.proposer.label, 'Assistant');
  });

  test('a half-right proposal opens nothing', () {
    for (final link in [
      'revoked://pr?label=No%20template',
      'revoked://pr?template=x&days=400',
      'revoked://pr?template=x&client=http://evil.example',
      'revoked://pr?template=x&ref=without-a-tool',
      'revoked://check?claims=9bad',
      'revoked://check?issuers=evil.example/path',
      'revoked://check?client=https://tool.example/app',
    ]) {
      expect(DeepLinks.locationFor(Uri.parse(link)), isNull, reason: link);
    }
    expect(
      AttestationAsk.fromQuery({
        'type': 'membership',
        'for': 'ab' * 32,
        'client': 'http://evil.example',
      }),
      isNull,
    );
  });
}
