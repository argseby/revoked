import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/utils/slug.dart';

void main() {
  test('a generated slug is 24 characters the server accepts', () {
    final pattern = RegExp(r'^[a-z0-9_-]+$');
    for (var i = 0; i < 200; i++) {
      final slug = randomSlug();
      expect(slug.length, slugLength);
      expect(slugLength, greaterThanOrEqualTo(24));
      expect(pattern.hasMatch(slug), isTrue, reason: slug);
    }
  });

  test('generated slugs do not repeat and use the whole alphabet', () {
    final slugs = {for (var i = 0; i < 1000; i++) randomSlug()};
    expect(slugs.length, 1000);
    final used = slugs.join().split('').toSet();
    expect(used, slugAlphabet.split('').toSet());
  });
}
