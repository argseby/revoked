import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A button says what it does twice — in its label and in its glyph — so a
/// screen is scannable before it is readable. The exception is the one button
/// that does nothing: a cancel carries no icon, which is what makes the icons
/// on the others mean "this acts".
void main() {
  const dismissals = {"'Cancel'", "'Close'", "'Not now'", 'cancelLabel'};

  test('every AppButton has an icon, except the ones that dismiss', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;
      // The widget's own constructor, not a call site.
      if (entity.path.endsWith('app_button.dart')) continue;

      final source = entity.readAsStringSync();
      for (final match in RegExp(r'\bAppButton\(').allMatches(source)) {
        var i = match.end;
        var depth = 1;
        while (depth > 0 && i < source.length) {
          final c = source[i];
          if (c == '(' || c == '[' || c == '{') depth++;
          if (c == ')' || c == ']' || c == '}') depth--;
          i++;
        }
        final call = source.substring(match.start, i);
        if (call.contains('icon:')) continue;

        final label = RegExp(r'label:\s*([^,\n]+)').firstMatch(call)?.group(1);
        if (label != null && dismissals.contains(label.trim())) continue;

        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('${entity.path}:$line  ${label ?? '(no label)'}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'give each of these a context icon, or — if it only dismisses — add '
          'its label to the dismissals list in this test',
    );
  });
}
