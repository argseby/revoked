import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/sign_in_request.dart';
import 'package:revoked_app/core/utils/deep_links.dart';

/// A service that does not know which server its user is on sends them to
/// the app with `revoked://signin`, and the app continues on its own server.
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

  test('a valid request continues on the signed-in server', () {
    final r = SignInRequest.fromQuery(query({'claims': '{"userinfo":{}}'}))!;
    final uri = r.authorizeUri('https://revoked.firma.de');
    expect(uri.origin, 'https://revoked.firma.de');
    expect(uri.path, '/oidc/authorize');
    expect(uri.queryParameters['client_id'], 'https://game.example');
    expect(
      uri.queryParameters['redirect_uri'],
      'https://game.example/callback',
    );
    expect(uri.queryParameters['code_challenge'], challenge);
    expect(uri.queryParameters['state'], 'st-1');
    expect(uri.queryParameters['claims'], '{"userinfo":{}}');
    expect(r.clientHost, 'game.example');
  });

  test('only authorization parameters are passed on', () {
    final r = SignInRequest.fromQuery(
      query({'evil': 'x', 'response_mode': 'fragment'}),
    )!;
    final params = r.authorizeUri('https://revoked.firma.de').queryParameters;
    expect(params.containsKey('evil'), isFalse);
    expect(params.containsKey('response_mode'), isFalse);
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
