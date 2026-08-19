import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/utils/deep_links.dart';

/// A revoked:// link is how a share or request reaches anyone, and it arrives
/// on the first frame — before the stored session has been checked. The splash
/// gate must not swallow where it was going.
void main() {
  test('public links map to routes that need no session', () {
    for (final raw in [
      'revoked://r/abc123',
      'revoked://s/def456',
      'revoked://i/ghi789',
    ]) {
      final location = DeepLinks.locationFor(Uri.parse(raw));
      expect(location, isNotNull, reason: '$raw produced no location');
      expect(
        location!.startsWith('/r/') ||
            location.startsWith('/s/') ||
            location.startsWith('/i/') ||
            location.startsWith('/request/') ||
            location.startsWith('/share/'),
        isTrue,
        reason:
            '$raw -> $location is not one of the public prefixes the '
            'router exempts from the splash gate',
      );
    }
  });

  test('an unknown scheme resolves to nothing', () {
    expect(
      DeepLinks.locationFor(Uri.parse('https://example.com/r/abc')),
      isNull,
    );
  });
}
