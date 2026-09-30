/// How a tool identifies itself in a `revoked://` link, checked the way the
/// server checks it: the tool is its origin, and it may only be answered at an
/// address on that origin.
///
/// Every value arrives in a link anyone could have built, so anything that
/// does not fit is refused rather than repaired.
abstract final class ToolClient {
  static final _origin = RegExp(
    r'^(https://[a-z0-9.-]+|http://(localhost|127\.0\.0\.1))(:[0-9]{1,5})?$',
  );
  static final _pkce = RegExp(r'^[A-Za-z0-9._~-]{43,128}$');
  static final _state = RegExp(r'^[A-Za-z0-9._~-]{1,128}$');

  /// scheme://host[:port], lower-cased, or null when [raw] is anything more
  /// or anything else.
  static String? origin(String? raw) {
    final uri = Uri.tryParse((raw ?? '').trim());
    if (uri == null || uri.userInfo.isNotEmpty || uri.host.isEmpty) return null;
    if ((uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final port = uri.hasPort ? ':${uri.port}' : '';
    final origin = '${uri.scheme}://${uri.host}$port'.toLowerCase();
    return _origin.hasMatch(origin) ? origin : null;
  }

  /// Whether [redirect] is an absolute address on exactly [origin].
  static bool redirectWithin(String redirect, String origin) {
    final uri = Uri.tryParse(redirect.trim());
    if (uri == null || uri.userInfo.isNotEmpty || uri.host.isEmpty) {
      return false;
    }
    if (uri.hasFragment) return false;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port'.toLowerCase() == origin;
  }

  static bool validChallenge(String s) => _pkce.hasMatch(s);

  /// The server a tool says it watches for the answer (`poll`), as an origin:
  /// empty when it named none, null when what it named is not one.
  static String? pollOrigin(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    return origin(raw);
  }

  static bool validState(String s) => _state.hasMatch(s);

  /// The address a tool is sent back to: its own return address with what it
  /// needs to carry on added to the query. Values the app decides, never the
  /// link's own.
  static Uri returnUri(String redirect, Map<String, String> params) {
    final uri = Uri.parse(redirect);
    return uri.replace(queryParameters: {...uri.queryParameters, ...params});
  }
}

/// Why a tool asks for what the owner may allow or not, in its own words:
/// `revoke_reason` and `links_reason` on a `revoked://` link. Shown as the
/// tool's claim, never as fact.
class ToolReasons {
  /// Why it wants to revoke the links it proposed.
  final String revoke;

  /// Why it wants to receive links the owner shares with it.
  final String links;

  const ToolReasons({this.revoke = '', this.links = ''});

  static const maxReason = 120;

  /// Reads the reasons from a link's query, or null when one is too long.
  static ToolReasons? fromQuery(Map<String, String> query) {
    final revoke = _line(query['revoke_reason']);
    final links = _line(query['links_reason']);
    if (revoke == null || links == null) return null;
    return ToolReasons(revoke: revoke, links: links);
  }

  Map<String, String> toQuery() => {
    if (revoke.isNotEmpty) 'revoke_reason': revoke,
    if (links.isNotEmpty) 'links_reason': links,
  };

  static String? _line(String? raw) {
    final s = (raw ?? '')
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return s.length > maxReason ? null : s;
  }
}

/// A tool asking to be connected: `revoked://connect?client=…&name=…&redirect=…&state=…&challenge=…`
/// (+ `revoke_reason`, `links_reason`, `poll`).
///
/// Connecting lets the tool see the status of the links it proposes. Whether
/// it may also revoke them, or receive links, is the owner's choice. It never
/// reads the vault.
class ConnectRequest {
  /// The tool's origin — who it is.
  final String client;

  /// The name it gives itself. A claim, shown as one.
  final String name;

  /// Where the one-time code goes; on [client]'s origin.
  final String redirect;

  /// The tool's own value, handed back unchanged.
  final String state;

  /// PKCE S256 challenge: only the page that made it can use the code.
  final String challenge;

  final ToolReasons reasons;

  /// The server the page that asked is watching for the answer, as an
  /// origin; empty when it waits to be sent back to [redirect] instead.
  final String poll;

  const ConnectRequest({
    required this.client,
    required this.name,
    required this.redirect,
    required this.state,
    required this.challenge,
    this.reasons = const ToolReasons(),
    this.poll = '',
  });

  static const maxName = 40;

  /// Reads a connect request, or null when any part is invalid.
  static ConnectRequest? fromQuery(Map<String, String> query) {
    final client = ToolClient.origin(query['client']);
    if (client == null) return null;
    final redirect = (query['redirect'] ?? '').trim();
    if (!ToolClient.redirectWithin(redirect, client)) return null;
    final challenge = query['challenge'] ?? '';
    if (!ToolClient.validChallenge(challenge)) return null;
    final state = query['state'] ?? '';
    if (!ToolClient.validState(state)) return null;
    final name = _cleanName(query['name']);
    if (name == null) return null;
    final reasons = ToolReasons.fromQuery(query);
    if (reasons == null) return null;
    final poll = ToolClient.pollOrigin(query['poll']);
    if (poll == null) return null;
    return ConnectRequest(
      client: client,
      name: name.isEmpty ? Uri.parse(client).host : name,
      redirect: redirect,
      state: state,
      challenge: challenge,
      reasons: reasons,
      poll: poll,
    );
  }

  Map<String, String> toQuery() => {
    'client': client,
    'name': name,
    'redirect': redirect,
    'state': state,
    'challenge': challenge,
    ...reasons.toQuery(),
    if (poll.isNotEmpty) 'poll': poll,
  };

  static String? _cleanName(String? raw) {
    final s = (raw ?? '')
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return s.length > maxName ? null : s;
  }
}
