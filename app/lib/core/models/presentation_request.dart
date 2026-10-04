import 'package:revoked_app/core/models/tool_client.dart';

/// A service asking to be shown an attestation:
/// `revoked://present?client_id=…&response_uri=…&nonce=…&state=…&type=…`.
///
/// The service is its origin, as a connected tool is, and may only be
/// answered at an address on that origin. It names the kind of attestation it
/// wants, and may name the attesters it accepts and the claims it needs; the
/// person decides which credential to show and which claims travel.
///
/// Everything here arrives in a link anyone could have built, so anything
/// that does not fit is refused rather than repaired.
class PresentationRequest {
  /// The service's origin — who it is, and the audience of the presentation.
  final String clientId;

  /// Where the presentation is posted; on [clientId]'s origin.
  final String responseUri;

  /// The service's value for this occasion. The presentation commits to it,
  /// so it cannot be replayed.
  final String nonce;

  /// Returned unchanged, so the service can find what it was waiting for.
  final String state;

  /// The kind of attestation asked for. Empty asks for any.
  final String type;

  /// The attesting domains the service accepts. Empty leaves it open: which
  /// attesters to believe is the service's decision after it verified.
  final List<String> issuers;

  /// The claims the service asks for. Empty leaves the choice to the person.
  final List<String> claims;

  const PresentationRequest._({
    required this.clientId,
    required this.responseUri,
    required this.nonce,
    required this.state,
    required this.type,
    required this.issuers,
    required this.claims,
  });

  static final _token = RegExp(r'^[A-Za-z0-9._~-]{8,256}$');
  static final _type = RegExp(r'^[\x21-\x7e]{1,255}$');
  static final _domain = RegExp(
    r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*(:[0-9]{1,5})?$',
  );
  static final _claim = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$');

  static const maxIssuers = 20;
  static const maxClaims = 50;

  /// Reads a request from a link's query, or null when it is not one this
  /// app could answer safely.
  static PresentationRequest? fromQuery(Map<String, String> query) {
    final client = ToolClient.origin(query['client_id']);
    final response = query['response_uri'] ?? '';
    if (client == null || !ToolClient.redirectWithin(response, client)) {
      return null;
    }
    final nonce = query['nonce'] ?? '';
    if (!_token.hasMatch(nonce)) return null;
    final state = query['state'] ?? '';
    if (state.isNotEmpty && !ToolClient.validState(state)) return null;
    final type = query['type'] ?? '';
    if (type.isNotEmpty && !_type.hasMatch(type)) return null;

    final issuers = _list(query['issuers'], _domain, maxIssuers, lower: true);
    final claims = _list(query['claims'], _claim, maxClaims);
    if (issuers == null || claims == null) return null;

    return PresentationRequest._(
      clientId: client,
      responseUri: response,
      nonce: nonce,
      state: state,
      type: type,
      issuers: issuers,
      claims: claims,
    );
  }

  static List<String>? _list(
    String? raw,
    RegExp pattern,
    int max, {
    bool lower = false,
  }) {
    final out = <String>[];
    for (var item in (raw ?? '').split(',')) {
      item = item.trim();
      if (lower) item = item.toLowerCase();
      if (item.isEmpty) continue;
      if (!pattern.hasMatch(item)) return null;
      if (!out.contains(item)) out.add(item);
    }
    return out.length > max ? null : out;
  }

  Map<String, String> toQuery() => {
    'client_id': clientId,
    'response_uri': responseUri,
    'nonce': nonce,
    if (state.isNotEmpty) 'state': state,
    if (type.isNotEmpty) 'type': type,
    if (issuers.isNotEmpty) 'issuers': issuers.join(','),
    if (claims.isNotEmpty) 'claims': claims.join(','),
  };

  /// The service's host, for showing who is asking.
  String get clientHost => Uri.parse(clientId).host;

  /// Whether a credential of [credentialType] from [issuer] is one this
  /// request asks for.
  bool accepts({required String issuer, required String credentialType}) {
    if (type.isNotEmpty && type != credentialType) return false;
    return issuers.isEmpty || issuers.contains(issuer.toLowerCase());
  }
}
