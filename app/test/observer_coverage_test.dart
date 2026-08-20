import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A view that reads a store outside an `Observer` compiles, analyzes clean and
/// passes every other test — it simply never repaints. The public request
/// screen lost its wrapper this way and sat on "Retrieving request…" forever,
/// because the probe landed on a tree that no longer listened.
///
/// This is a shape check, not a proof: it requires a file that reads store
/// state to mention `Observer` at all. It cannot tell you the wrapper is in the
/// right place, so it is a floor, not a guarantee.
void main() {
  test('every view that reads a store also builds an Observer', () {
    final offenders = <String>[];

    for (final entity in Directory('lib/features').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (!entity.path.contains('/view/')) continue;

      final source = entity.readAsStringSync();
      final readsStore =
          source.contains('_store.') || source.contains('Stores.');
      if (readsStore && !source.contains('Observer(')) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'these read observable state but never wrap it — they will not '
          'rebuild:\n${offenders.join('\n')}',
    );
  });

  test('a screen whose whole build is one Observer keeps it', () {
    // The wrapper is a one-line `build` delegating to `_build`. Losing that
    // line is invisible to the analyzer, so pin the screens that use it.
    const delegating = [
      'lib/features/requests/view/public_request_screen.dart',
      'lib/features/shares/view/public_share_screen.dart',
    ];

    for (final path in delegating) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('Observer(builder: (_) => _build(context))'),
        isTrue,
        reason: '$path must delegate its build through an Observer',
      );
    }
  });
}
