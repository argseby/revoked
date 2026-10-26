import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/sign_in_request.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/core/utils/pkce.dart';

/// A service that does not know which server its user is on sends them to
/// the app with `revoked://signin`, and the app opens the request on its own
/// server.
/// The link is built by whoever wants, so the app passes on only an
/// authorization request the server could accept, and only its parameters.
void main() {
  final challenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

  Map<String, String> query([Map<String, String> overlay = const {}]) => {
    'client_id': 'https://game.example',
    'redirect_uri': 'https://game.example/callback',
    'response_type': 'code',
    'scope': 'openid profile',
    'state': 'st-1',
    'nonce': 'n-1',
    'code_challenge': challenge,
    'code_challenge_method': 'S256',
    ...overlay,
  };

  test('a valid request carries its parameters on to the server', () {
    final r = SignInRequest.fromQuery(query({'claims': '{"userinfo":{}}'}))!;
    final params = r.toQuery();
    expect(params['client_id'], 'https://game.example');
    expect(params['redirect_uri'], 'https://game.example/callback');
    expect(params['code_challenge'], challenge);
    expect(params['state'], 'st-1');
    expect(params['claims'], '{"userinfo":{}}');
    expect(r.clientHost, 'game.example');
  });

  test('only authorization parameters are passed on', () {
    final r = SignInRequest.fromQuery(
      query({'evil': 'x', 'response_mode': 'fragment'}),
    )!;
    final params = r.toQuery();
    expect(params.containsKey('evil'), isFalse);
    expect(params.containsKey('response_mode'), isFalse);
  });

  test('a service that waits for the answer says so in the link', () {
    expect(SignInRequest.fromQuery(query())!.background, isFalse);
    final waits = SignInRequest.fromQuery(
      query({'revoked_return': 'background'}),
    )!;
    expect(waits.background, isTrue);
    expect(waits.challenge, challenge);
    // It survives the trip through the router.
    final routed = Uri.parse(
      DeepLinks.locationFor(
        Uri(
          scheme: 'revoked',
          host: 'signin',
          queryParameters: query({'revoked_return': 'background'}),
        ),
      )!,
    );
    expect(SignInRequest.fromQuery(routed.queryParameters)!.background, isTrue);
  });

  // A service shows the same code from the same challenge; Overlap's Go test
  // pins the same value.
  test('the check code is the one a waiting service shows', () {
    expect(Pkce.checkCode(challenge), '0D2-99B');
  });

  test('requests the server would refuse are refused here', () {
    for (final overlay in <Map<String, String>>[
      {'client_id': 'https://game.example/path'},
      {'client_id': 'http://game.example'},
      {'redirect_uri': 'https://evil.example/callback'},
      {'code_challenge': ''},
      {'code_challenge_method': 'plain'},
      {'response_type': 'token'},
      {'scope': 'profile'},
    ]) {
      expect(
        SignInRequest.fromQuery(query(overlay)),
        isNull,
        reason: '$overlay',
      );
    }
  });

  test('the deep link maps to the sign-in route and back', () {
    final link = Uri(
      scheme: 'revoked',
      host: 'signin',
      queryParameters: query(),
    );
    final location = DeepLinks.locationFor(link);
    expect(location, isNotNull);
    final routed = Uri.parse(location!);
    expect(routed.path, '/signin');
    expect(SignInRequest.fromQuery(routed.queryParameters), isNotNull);
  });

  test('a malformed sign-in link maps to nothing', () {
    final link = Uri(
      scheme: 'revoked',
      host: 'signin',
      queryParameters: query({'redirect_uri': 'https://evil.example/cb'}),
    );
    expect(DeepLinks.locationFor(link), isNull);
  });
}
