import 'package:revoked_app/core/models/tool_client.dart';

/// A service asking to sign its user in with Revoked, without knowing which
/// server the user is on:
/// `revoked://signin?client_id=…&redirect_uri=…&code_challenge=…&…`.
///
/// The parameters are those of an OpenID Connect authorization request, none
/// of which depend on the server. The app knows the server — the one it is
/// signed into — and opens that server's authorization page with them, in the
/// browser. The server's answer names itself (`iss`), which is how the
/// service learns where the person signed in.
///
/// Everything here arrives in a link anyone could have built. It is checked
/// as far as the app needs to decide what to show, and passed on unchanged
/// otherwise: the server checks it again and is the one that decides.
class SignInRequest {
  /// The service's origin — who it is.
  final String clientId;

  /// Where the answer goes; on [clientId]'s origin.
  final String redirectUri;

  /// Every parameter that travels on to the authorization page.
  final Map<String, String> params;

  const SignInRequest._({
    required this.clientId,
    required this.redirectUri,
    required this.params,
  });

  /// The authorization request parameters a link may carry. Anything else is
  /// dropped, so the page never receives a parameter nothing here looked at.
  static const forwarded = [
    'client_id',
    'redirect_uri',
    'response_type',
    'scope',
    'state',
    'nonce',
    'code_challenge',
    'code_challenge_method',
    'claims',
    'prompt',
  ];

  /// Reads a request from a link's query, or null when it is not one the
  /// server could accept: the service must be an origin, the answer must go
  /// back to it, and PKCE is required.
  static SignInRequest? fromQuery(Map<String, String> query) {
    final client = ToolClient.origin(query['client_id']);
    final redirect = query['redirect_uri'] ?? '';
    if (client == null || !ToolClient.redirectWithin(redirect, client)) {
      return null;
    }
    if (!ToolClient.validChallenge(query['code_challenge'] ?? '') ||
        query['code_challenge_method'] != 'S256') {
      return null;
    }
    if (query['response_type'] != 'code') return null;
    final scope = (query['scope'] ?? '').split(' ');
    if (!scope.contains('openid')) return null;

    final params = <String, String>{};
    for (final key in forwarded) {
      final value = query[key];
      if (value != null && value.isNotEmpty) params[key] = value;
    }
    // The answer must name this client's origin exactly as the server will.
    params['client_id'] = client;
    return SignInRequest._(
      clientId: client,
      redirectUri: redirect,
      params: params,
    );
  }

  Map<String, String> toQuery() => Map.of(params);

  /// The authorization page on [serverBase], the server the app is signed
  /// into, with this request's parameters.
  Uri authorizeUri(String serverBase) {
    final base = Uri.parse(serverBase);
    return base.replace(path: '/oidc/authorize', queryParameters: params);
  }

  /// The service's host, for showing who is asking.
  String get clientHost => Uri.parse(clientId).host;
}
