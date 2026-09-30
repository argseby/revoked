import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

/// PKCE (RFC 7636), for the one-time code the server's sign-in page hands
/// back: only the app that made the challenge holds the verifier the code is
/// redeemed with, so a code seen by anything else on the device is worthless.
abstract final class Pkce {
  /// [bytes] of CSPRNG output, base64url without padding.
  static String randomToken([int bytes = 32]) {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(bytes, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  /// The S256 challenge of [verifier].
  static String challenge(String verifier) {
    final digest = pc.SHA256Digest().process(
      Uint8List.fromList(ascii.encode(verifier)),
    );
    return base64Url.encode(digest).replaceAll('=', '');
  }

  /// A short code both ends derive from a [challenge], for a person to
  /// compare: the page that made the challenge shows it, and so does whoever
  /// is asked to answer it. `83C-047`.
  static String checkCode(String challenge) {
    final digest = pc.SHA256Digest().process(
      Uint8List.fromList(ascii.encode(challenge)),
    );
    final hex = digest
        .take(3)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return '${hex.substring(0, 3)}-${hex.substring(3)}';
  }
}
