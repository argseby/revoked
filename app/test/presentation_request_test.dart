import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/presentation_request.dart';
import 'package:revoked_app/core/router/resume_location.dart';
import 'package:revoked_app/core/utils/deep_links.dart';

/// A service asks to be shown an attestation with `revoked://present`. The
/// link is built by whoever wants, so the app answers only a request whose
/// answer can go nowhere but to the service that is named in it.
void main() {
  Map<String, String> query([Map<String, String> overlay = const {}]) => {
    'client_id': 'https://shop.example',
    'response_uri': 'https://shop.example/present/callback',
    'nonce': 'n-0123456789',
    'state': 'st-1',
    'type': 'verified_adult',
    ...overlay,
  };

  test('a valid request names the service, the occasion and what is asked', () {
    final r = PresentationRequest.fromQuery(
      query({
        'issuers': 'Verify.Example, club.example:8443',
        'claims': 'age_over_18,name',
      }),
    )!;
    expect(r.clientId, 'https://shop.example');
    expect(r.clientHost, 'shop.example');
    expect(r.responseUri, 'https://shop.example/present/callback');
    expect(r.nonce, 'n-0123456789');
    expect(r.type, 'verified_adult');
    expect(r.issuers, ['verify.example', 'club.example:8443']);
    expect(r.claims, ['age_over_18', 'name']);
  });

  test('the answer can only go to the service that asked', () {
    for (final overlay in <Map<String, String>>[
      {'response_uri': 'https://evil.example/collect'},
      {'response_uri': 'https://shop.example.evil.example/collect'},
      {'response_uri': 'http://shop.example/present/callback'},
      {'client_id': 'https://shop.example/path'},
      {'client_id': 'http://shop.example'},
      {'client_id': ''},
    ]) {
      expect(
        PresentationRequest.fromQuery(query(overlay)),
        isNull,
        reason: '$overlay',
      );
    }
  });

  test('a request without a usable nonce is refused', () {
    // The nonce is what makes a presentation single-use; without one the
    // app would be signing something replayable.
    for (final nonce in ['', 'short', 'has space 123456', 'a' * 300]) {
      expect(
        PresentationRequest.fromQuery(query({'nonce': nonce})),
        isNull,
        reason: nonce,
      );
    }
  });

  test('malformed lists refuse the request rather than being trimmed', () {
    for (final overlay in <Map<String, String>>[
      {'issuers': 'https://verify.example'},
      {'issuers': 'verify example'},
      {'claims': 'has space'},
      {'claims': '_sd'},
      {'type': 'two words'},
      {'state': 'has space'},
    ]) {
      expect(
        PresentationRequest.fromQuery(query(overlay)),
        isNull,
        reason: '$overlay',
      );
    }
  });

  test('type and attesters decide which credentials fit', () {
    final any = PresentationRequest.fromQuery(query({'type': ''}))!;
    expect(
      any.accepts(issuer: 'x.example', credentialType: 'anything'),
      isTrue,
    );

    final typed = PresentationRequest.fromQuery(query())!;
    expect(
      typed.accepts(issuer: 'x.example', credentialType: 'verified_adult'),
      isTrue,
    );
    expect(
      typed.accepts(issuer: 'x.example', credentialType: 'membership'),
      isFalse,
    );

    final from = PresentationRequest.fromQuery(
      query({'issuers': 'verify.example'}),
    )!;
    expect(
      from.accepts(issuer: 'Verify.Example', credentialType: 'verified_adult'),
      isTrue,
    );
    expect(
      from.accepts(issuer: 'other.example', credentialType: 'verified_adult'),
      isFalse,
    );
  });

  test('the deep link maps to the presentation route and back', () {
    final link = Uri(
      scheme: 'revoked',
      host: 'present',
      queryParameters: query({'claims': 'age_over_18', 'evil': 'x'}),
    );
    final location = DeepLinks.locationFor(link);
    expect(location, isNotNull);
    final routed = Uri.parse(location!);
    expect(routed.path, '/present');
    // Only what the request understood travels on.
    expect(routed.queryParameters.containsKey('evil'), isFalse);
    final again = PresentationRequest.fromQuery(routed.queryParameters)!;
    expect(again.claims, ['age_over_18']);
    expect(again.nonce, 'n-0123456789');
  });

  test('a malformed presentation link maps to nothing', () {
    final link = Uri(
      scheme: 'revoked',
      host: 'present',
      queryParameters: query({'response_uri': 'https://evil.example/x'}),
    );
    expect(DeepLinks.locationFor(link), isNull);
  });

  test('an offer link names the server it lives on', () {
    expect(
      DeepLinks.attestation('tok123', origin: 'verify.example'),
      'revoked://a/verify.example/tok123',
    );
    expect(
      DeepLinks.locationFor(Uri.parse('revoked://a/verify.example/tok123')),
      '/a/tok123?o=verify.example',
    );
    expect(DeepLinks.locationFor(Uri.parse('revoked://a/tok123')), '/a/tok123');
    expect(
      DeepLinks.locationFor(Uri.parse('revoked://attestation/tok123')),
      '/a/tok123',
    );
  });

  test('both links survive signing in and setting up a workspace', () {
    expect(ResumeLocation.isResumable('/a/tok123?o=verify.example'), isTrue);
    expect(ResumeLocation.isResumable('/present?client_id=x'), isTrue);
    expect(ResumeLocation.isResumable('/vault'), isFalse);
  });
}
