import 'dart:async';

import 'package:app_links/app_links.dart';

/// Thin wrapper over `app_links` for receiving incoming `revoked://` deep
/// links — both the cold-start link and links delivered while running.
class DeepLinkService {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  /// The link the app was launched with, if any (cold start).
  Future<Uri?> initialLink() => _appLinks.getInitialLink();

  /// Subscribe to links delivered while the app is already running.
  void onLink(void Function(Uri uri) handler) {
    _sub ??= _appLinks.uriLinkStream.listen(handler);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
