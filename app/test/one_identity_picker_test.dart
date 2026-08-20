import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Choosing which key signs something is one decision, so it gets one control.
/// It drifted into three: a radio list in the share drawer, a tap-through
/// sub-sheet in the request drawer, and a dropdown on the public request
/// screen — each with its own idea of how the `from_root` restriction and the
/// single-identity case should look.
void main() {
  test('no view hand-rolls a list of identities', () {
    final offenders = <String>[];

    for (final entity in Directory('lib/features').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (!entity.path.contains('/view/')) continue;

      final source = entity.readAsStringSync();
      // Iterating the identity list in a view means building a picker by hand;
      // reading it to check for emptiness or to resolve one id is fine.
      final iterates = RegExp(
        r'for \(final \w+ in Stores\.identities\.identities\)|'
        r'Stores\.identities\.identities\.map\(',
      ).hasMatch(source);
      if (iterates && !source.contains('IdentityPicker(')) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'use IdentityPicker instead of rendering identities inline:\n'
          '${offenders.join('\n')}',
    );
  });

  test('every identity choice goes through IdentityPicker', () {
    const flows = [
      'lib/features/shares/view/share_create_sheet.dart',
      'lib/features/shares/view/public_share_screen.dart',
      'lib/features/requests/view/request_create_sheet.dart',
      'lib/features/requests/view/public_request_screen.dart',
    ];

    for (final path in flows) {
      expect(
        File(path).readAsStringSync(),
        contains('IdentityPicker('),
        reason: '$path picks a signing identity and must use the shared widget',
      );
    }
  });
}
