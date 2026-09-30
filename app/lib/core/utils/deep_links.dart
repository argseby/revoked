import 'package:revoked_app/core/models/share_proposal.dart';
import 'package:revoked_app/core/models/tool_client.dart';

/// Builds and parses `revoked://` deep links.
///
/// Requests and shares are distributed as **app** deep links rather than web
/// URLs, so a recipient must have the installed app to open them. That is
/// deliberate anti-spoofing: there is no web page for a scammer to fake.
///
/// A link names the server it lives on, because every instance is
/// self-hosted and slugs only mean something to the server that minted them:
///
///   `revoked://s/<host[:port]>/<slug>`  ->  `/s/<slug>?o=<host[:port]>`
///   `revoked://r/<host[:port]>/<slug>`  ->  `/r/<slug>?o=<host[:port]>`
///   `revoked://i/<host[:port]>/<token>` ->  `/i/<token>?o=<host[:port]>`
///
/// The embedded origin is untrusted input — it routes the fetch and nothing
/// more. Who the sender *is* stays a question for the DNS trust chain.
/// Single-segment links from before origins existed still resolve, against
/// the server the app is signed into.
///
/// A tool proposing a share carries no origin: the share is created on the
/// server the app is signed into, which is the owner's own.
///
///   `revoked://p?label=…&keys=…` ->  `/p?label=…&keys=…`
///
/// A tool asking to be connected, answered on the same server:
///
///   `revoked://connect?client=…&redirect=…&state=…&challenge=…` -> `/connect?…`
///
/// And the server's sign-in page sending the person back with a one-time
/// code, which is an answer rather than a destination:
///
///   `revoked://auth?code=…&state=…`
class DeepLinks {
  DeepLinks._();

  static const String scheme = 'revoked';

  /// Whether [uri] is the sign-in page's way back into the app.
  static bool isSignInReturn(Uri uri) =>
      uri.scheme == scheme && uri.host == 'auth';

  static String request(String slug, {String origin = ''}) =>
      origin.isEmpty ? '$scheme://r/$slug' : '$scheme://r/$origin/$slug';
  static String share(String slug, {String origin = ''}) =>
      origin.isEmpty ? '$scheme://s/$slug' : '$scheme://s/$origin/$slug';
  static String invite(String token, {String origin = ''}) =>
      origin.isEmpty ? '$scheme://i/$token' : '$scheme://i/$origin/$token';

  /// A recognized link: which kind, which slug, and — when the link carries
  /// one — which server it lives on.
  static ({String kind, String slug, String? origin})? parse(Uri uri) {
    if (uri.scheme != scheme) return null;
    final kind = switch (uri.host) {
      's' || 'share' => 's',
      'r' || 'request' => 'r',
      'i' || 'invite' => 'i',
      _ => null,
    };
    if (kind == null) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    if (segments.length == 1) {
      return (kind: kind, slug: segments[0], origin: null);
    }
    final origin = segments[0];
    // The origin is host[:port] and nothing else. A segment that cannot be
    // one makes the whole link unrecognizable rather than half-trusted.
    final parsed = Uri.tryParse('https://$origin');
    if (parsed == null ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        origin.contains('/')) {
      return null;
    }
    return (kind: kind, slug: segments[1], origin: origin);
  }

  /// Reads an invite key out of whatever a person pasted: the bare token, or
  /// the whole `revoked://i/<token>` link they were sent.
  ///
  /// Both entry points into joining accept the same input, so they read it the
  /// same way — a second parser would eventually disagree with this one about
  /// which halves of a link are the key.
  static String inviteTokenFrom(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final location = DeepLinks.locationFor(Uri.tryParse(trimmed) ?? Uri());
    if (location != null && location.startsWith('/i/')) {
      // locationFor may append the origin as a query, which is not the key.
      return Uri.parse(location.substring(3)).path;
    }
    return trimmed;
  }

  /// Maps an incoming deep-link [uri] to an in-app router location, or null
  /// if it isn't a recognized `revoked://` link.
  static String? locationFor(Uri uri) {
    if (uri.scheme == scheme && uri.host == 'connect') {
      final request = ConnectRequest.fromQuery(uri.queryParameters);
      if (request == null) return null;
      return Uri(
        path: '/connect',
        queryParameters: request.toQuery(),
      ).toString();
    }
    if (uri.scheme == scheme && (uri.host == 'p' || uri.host == 'propose')) {
      // Only what the proposal understood travels on, so the route never
      // sees a parameter nothing validated.
      final proposal = ShareProposal.fromQuery(uri.queryParameters);
      if (proposal == null) return null;
      return Uri(path: '/p', queryParameters: proposal.toQuery()).toString();
    }
    final link = parse(uri);
    if (link == null) return null;
    final suffix = link.origin == null
        ? ''
        : '?o=${Uri.encodeQueryComponent(link.origin!)}';
    return '/${link.kind}/${link.slug}$suffix';
  }
}
