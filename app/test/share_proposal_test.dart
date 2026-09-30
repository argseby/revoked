import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/share_proposal.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/utils/pkce.dart';

/// A proposal link is built by a tool nobody vetted, so everything in it is
/// untrusted: it may only name keys and settings, and a malformed one is
/// refused whole rather than half-applied.
void main() {
  ShareProposal? parse(String link) {
    final location = DeepLinks.locationFor(Uri.parse(link));
    if (location == null) return null;
    return ShareProposal.fromQuery(Uri.parse(location).queryParameters);
  }

  test('a proposal link routes to the proposal screen with what it asked', () {
    final location = DeepLinks.locationFor(
      Uri.parse(
        'revoked://p?label=Musterstr.%205&keys=full_name,id_document'
        '&stamp=Nur%20f%C3%BCr%20Musterstr.%205&days=14'
        '&purpose=application&from=Mietunterlagen',
      ),
    );
    expect(location, startsWith('/p?'));

    final p = ShareProposal.fromQuery(Uri.parse(location!).queryParameters)!;
    expect(p.label, 'Musterstr. 5');
    expect(p.keys, ['full_name', 'id_document']);
    expect(p.stamp, 'Nur für Musterstr. 5');
    expect(p.days, 14);
    expect(p.purpose, 'application');
    expect(p.from, 'Mietunterlagen');
  });

  test('reads the link Mietunterlagen builds, commas percent-encoded', () {
    // Verbatim from the web client's proposalLink().
    final p = parse(
      'revoked://p?label=Musterstr.%205%2C%2010115%20Berlin'
      '&keys=full_name%2Cemail%2Cproof_of_income'
      '&stamp=Nur%20f%C3%BCr%20Wohnungsbewerbung%20Musterstr.%205%2C%2010115%20Berlin'
      '&days=14&purpose=application&from=Mietunterlagen'
      '&template=Tenant%20application',
    )!;
    expect(p.template, 'Tenant application');
    expect(p.label, 'Musterstr. 5, 10115 Berlin');
    expect(p.keys, ['full_name', 'email', 'proof_of_income']);
    expect(p.stamp, 'Nur für Wohnungsbewerbung Musterstr. 5, 10115 Berlin');
  });

  test('the long host name works too, and settings are optional', () {
    final p = parse('revoked://propose?label=Vet&keys=chip_number')!;
    expect(p.keys, ['chip_number']);
    expect(p.stamp, isEmpty);
    expect(p.days, isNull);
    expect(p.purpose, isEmpty);
  });

  test('duplicate and blank keys collapse', () {
    final p = parse('revoked://p?label=x&keys=a,,a,%20b%20')!;
    expect(p.keys, ['a', 'b']);
  });

  test('text is cleaned to one line', () {
    final p = parse('revoked://p?label=%20Muster%0Astr.%09%205%20&keys=a')!;
    expect(p.label, 'Muster str. 5');
  });

  test('a malformed proposal is refused whole', () {
    for (final link in [
      // No label, no keys.
      'revoked://p?keys=a',
      'revoked://p?label=x',
      // A key that could break out of a filter.
      'revoked://p?label=x&keys=a"%20||%20key!=""',
      'revoked://p?label=x&keys=Full_Name',
      // Out-of-range or unreadable expiry.
      'revoked://p?label=x&keys=a&days=0',
      'revoked://p?label=x&keys=a&days=366',
      'revoked://p?label=x&keys=a&days=soon',
      // A purpose the server does not know.
      'revoked://p?label=x&keys=a&purpose=anything',
      // An application the server would refuse for lacking a stamp.
      'revoked://p?label=x&keys=a&purpose=application',
      // Longer than a stamp can hold.
      'revoked://p?label=${'x' * 121}&keys=a',
    ]) {
      expect(DeepLinks.locationFor(Uri.parse(link)), isNull, reason: link);
    }
  });

  test('too many keys is refused', () {
    final keys = List.generate(ShareProposal.maxKeys + 1, (i) => 'k$i');
    expect(parse('revoked://p?label=x&keys=${keys.join(',')}'), isNull);
  });

  test('only understood parameters reach the route', () {
    final location = DeepLinks.locationFor(
      Uri.parse('revoked://p?label=x&keys=a&callback=https://evil.example'),
    )!;
    expect(
      Uri.parse(location).queryParameters.keys,
      isNot(contains('callback')),
    );
  });

  test('the query round-trips', () {
    const p = ShareProposal(
      label: 'Musterstr. 5',
      keys: ['a', 'b'],
      stamp: 'Nur für Musterstr. 5',
      days: 7,
      purpose: 'application',
      from: 'Tool',
      template: 'Tenant application',
    );
    final back = ShareProposal.fromQuery(p.toQuery())!;
    expect(back.toQuery(), p.toQuery());
  });
  group('a tool that names itself', () {
    final challenge = 'a' * 43;
    const tool = 'https://mietunterlagen.example.com';

    test('carries its origin, way back, state and reference', () {
      final p = parse(
        'revoked://p?label=x&keys=a&from=Tool&client=$tool'
        '&redirect=$tool/back%3Fx%3D1&state=s-1&challenge=$challenge&ref=flat-1',
      )!;
      expect(p.client, tool);
      expect(p.redirect, '$tool/back?x=1');
      expect(p.state, 's-1');
      expect(p.challenge, challenge);
      expect(p.ref, 'flat-1');
    });

    test('carries its reasons, and is refused when one is too long', () {
      final p = parse(
        'revoked://p?label=x&keys=a&client=$tool'
        '&revoke_reason=To%20end%20a%20link&links_reason=To%20copy%20it',
      )!;
      expect(p.reasons.revoke, 'To end a link');
      expect(p.reasons.links, 'To copy it');
      expect(ShareProposal.fromQuery(p.toQuery())!.reasons.links, 'To copy it');
      expect(
        parse(
          'revoked://p?label=x&keys=a&client=$tool&revoke_reason=${'r' * 121}',
        ),
        isNull,
      );
    });

    test('is named after its host when it gives no name', () {
      expect(
        parse('revoked://p?label=x&keys=a&client=$tool')!.from,
        'mietunterlagen.example.com',
      );
    });

    test('is refused when the parts do not fit together', () {
      for (final link in [
        // An origin is scheme and host, nothing more.
        'revoked://p?label=x&keys=a&client=$tool/path',
        'revoked://p?label=x&keys=a&client=http://evil.example',
        // A way back needs a tool, on that tool's own origin.
        'revoked://p?label=x&keys=a&redirect=$tool/',
        'revoked://p?label=x&keys=a&client=$tool&redirect=https://evil.example/',
        // A state needs a way back; a challenge needs a state.
        'revoked://p?label=x&keys=a&client=$tool&state=s',
        'revoked://p?label=x&keys=a&client=$tool&redirect=$tool/&challenge=$challenge',
        'revoked://p?label=x&keys=a&client=$tool&redirect=$tool/&state=s&challenge=short',
      ]) {
        expect(DeepLinks.locationFor(Uri.parse(link)), isNull, reason: link);
      }
    });
  });

  group('connect requests', () {
    final challenge = 'b' * 43;
    const tool = 'https://tool.example';

    test('route to the connect screen with what they asked', () {
      final location = DeepLinks.locationFor(
        Uri.parse(
          'revoked://connect?client=$tool&name=Tool&redirect=$tool/cb'
          '&state=st&challenge=$challenge',
        ),
      );
      expect(location, startsWith('/connect?'));
      final r = ConnectRequest.fromQuery(Uri.parse(location!).queryParameters)!;
      expect(r.client, tool);
      expect(r.name, 'Tool');
      expect(r.redirect, '$tool/cb');
    });

    test('are refused without a challenge, state or a way back home', () {
      for (final link in [
        'revoked://connect?client=$tool&redirect=$tool/&state=s',
        'revoked://connect?client=$tool&redirect=$tool/&challenge=$challenge',
        'revoked://connect?client=$tool&redirect=https://evil.example/&state=s&challenge=$challenge',
        'revoked://connect?client=$tool/x&redirect=$tool/&state=s&challenge=$challenge',
      ]) {
        expect(DeepLinks.locationFor(Uri.parse(link)), isNull, reason: link);
      }
    });

    test('a watched server is an origin or the link is refused', () {
      const base =
          'revoked://connect?client=$tool&redirect=$tool/&state=s'
          '&challenge=';
      ConnectRequest? read(String poll) {
        final location = DeepLinks.locationFor(
          Uri.parse('$base$challenge$poll'),
        );
        return location == null
            ? null
            : ConnectRequest.fromQuery(Uri.parse(location).queryParameters);
      }

      expect(read('')!.poll, isEmpty);
      expect(
        read('&poll=https%3A%2F%2Fvault.example')!.poll,
        'https://vault.example',
      );
      expect(read('&poll=https%3A%2F%2Fvault.example%2Fapi'), isNull);
      expect(read('&poll=http%3A%2F%2Fvault.example'), isNull);
      // A proposal names one only when it names itself.
      expect(
        ShareProposal.fromQuery({
          'label': 'x',
          'keys': 'a',
          'poll': 'https://vault.example',
        }),
        isNull,
      );
      expect(
        ShareProposal.fromQuery({
          'label': 'x',
          'keys': 'a',
          'client': tool,
          'poll': 'https://vault.example',
        })!.poll,
        'https://vault.example',
      );
    });

    test('both ends read the same check code from a challenge', () {
      // The same vector as the tool's own test.
      expect(
        Pkce.checkCode('E9LVI17tLpGpM3ZvzAq5HMYjQ3Z4Q1F2U6JtVZ0QxkA'),
        '83C-047',
      );
    });

    test('the way back keeps the tool\'s own query and adds the answer', () {
      final uri = ToolClient.returnUri('$tool/cb?keep=1', {
        'state': 's',
        'code': 'c',
      });
      expect(uri.queryParameters, {'keep': '1', 'state': 's', 'code': 'c'});
      expect(uri.origin, tool);
    });
  });
}
