import 'dart:typed_data';

import 'package:revoked_app/core/utils/deep_links.dart';

/// The key a share's address ended in, between the address arriving and the
/// share's screen opening.
///
/// The key opens the share's end-to-end encrypted records and must reach
/// nothing durable. A router location is kept across the splash, held on disk
/// while someone signs up and shown wherever a route is, so the key does not
/// travel in one. It waits here, in memory, for the one screen it was meant
/// for, and is gone once that screen has taken it.
abstract final class HeldLinkKeys {
  static ({String share, Uint8List key})? _held;

  static String _id(String slug, String? origin) => '${origin ?? ''}/$slug';

  /// Holds the key [uri] carries, when [uri] is a share's app link. A share
  /// arriving without one drops whatever was held: an earlier arrival's key
  /// says nothing about this one.
  static void holdFrom(Uri uri) {
    final link = DeepLinks.parse(uri);
    if (link == null || link.kind != 's') return;
    hold(slug: link.slug, origin: link.origin, key: DeepLinks.linkKey(uri));
  }

  static void hold({
    required String slug,
    String? origin,
    required Uint8List? key,
  }) {
    _held = key == null ? null : (share: _id(slug, origin), key: key);
  }

  /// The key held for this share, given up: it is handed out once.
  static Uint8List? take({required String slug, String? origin}) {
    final held = _held;
    _held = null;
    return held != null && held.share == _id(slug, origin) ? held.key : null;
  }
}
