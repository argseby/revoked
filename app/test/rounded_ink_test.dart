import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Hover and press feedback follows the shape of the thing being touched.
/// Material paints a rectangle unless the surface says otherwise, so an
/// [InkWell] without a radius is a square highlight on a rounded control —
/// which is how the app ended up with them scattered across every screen.
void main() {
  test('every ink surface declares its shape', () {
    final offenders = <String>[];

    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();

      for (final match in RegExp(r'Ink(Well|Response)\(').allMatches(source)) {
        final open = source.indexOf('(', match.start);
        final body = source.substring(open + 1, _closingParen(source, open));
        if (body.contains('borderRadius:') || body.contains('customBorder:')) {
          continue;
        }
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('${file.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'these ink surfaces would paint a rectangular hover:\n'
          '${offenders.join('\n')}',
    );
  });
}

/// Index of the `)` matching the `(` at [open].
int _closingParen(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '(') depth++;
    if (source[i] == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return source.length;
}
