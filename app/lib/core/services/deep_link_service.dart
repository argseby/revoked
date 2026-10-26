import 'dart:async';

import 'package:app_links/app_links.dart';

/// Thin wrapper over `app_links` for receiving incoming `revoked://` deep
/// links — both the cold-start link and links delivered while running.
class DeepLinkService {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  /// Subscribe to incoming links. The launch link arrives first, once; there
  /// is deliberately no `getInitialLink`, which never forgets it.
  void onLink(void Function(Uri uri) handler) {
    _sub ??= _appLinks.uriLinkStream.listen(handler);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
