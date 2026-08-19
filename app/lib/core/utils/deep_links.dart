/// Builds and parses `revoked://` deep links.
///
/// Requests and shares are distributed as **app** deep links rather than web
/// URLs, so a recipient must have the installed app to open them. That is
/// deliberate anti-spoofing: there is no web page for a scammer to fake.
///
/// Short forms are canonical; the long forms still resolve for older links:
///
///   `revoked://s/<slug>`  ->  `/s/<slug>`   (also accepts `share`)
///   `revoked://r/<slug>`  ->  `/r/<slug>`   (also accepts `request`)
class DeepLinks {
  DeepLinks._();

  static const String scheme = 'revoked';

  static String request(String slug) => '$scheme://r/$slug';
  static String share(String slug) => '$scheme://s/$slug';
  static String invite(String token) => '$scheme://i/$token';

  /// Maps an incoming deep-link [uri] to an in-app router location, or returns
  /// null if it isn't a recognized `revoked://` link. Accepts both the short
  /// (`s`/`r`) and long (`share`/`request`) hosts.
  static String? locationFor(Uri uri) {
    if (uri.scheme != scheme) return null;
    final host = uri.host;
    final segments = uri.pathSegments;
    if (segments.isEmpty) return null;
    final slug = segments.first;
    if (host == 's' || host == 'share') return '/s/$slug';
    if (host == 'r' || host == 'request') return '/r/$slug';
    if (host == 'i' || host == 'invite') return '/i/$slug';
    return null;
  }
}
