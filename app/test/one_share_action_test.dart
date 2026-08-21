import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Handing a link to someone is one act, so it is one button.
///
/// It used to be three — "Web & API", "Copy link", "QR code" — which made the
/// reader choose a carrier before they had decided to share at all. The
/// carriers live inside [showShareSheet]; a card that grows its own copy or QR
/// entry has split the act back apart.
void main() {
  final cards = {
    'shares': File(
      'lib/features/shares/view/shares_screen.dart',
    ).readAsStringSync(),
    'requests': File(
      'lib/features/requests/view/inbox_screen.dart',
    ).readAsStringSync(),
  };

  test('link cards expose exactly one share action', () {
    for (final entry in cards.entries) {
      expect(
        entry.value,
        contains('showShareSheet('),
        reason: '${entry.key} must hand off through the shared sheet',
      );
      for (final gone in [
        "label: 'Copy link'",
        "label: 'QR code'",
        "label: 'Web & API'",
      ]) {
        expect(
          entry.value.contains(gone),
          isFalse,
          reason: '${entry.key} still carries a separate $gone action',
        );
      }
    }
  });

  test('a request is never handed out as a web link', () {
    // The browser page is read-only by design. A request collects input, and
    // input belongs in the app, which verifies the server before anything is
    // typed — so the sheet must keep the web link share-only.
    final sheet = File(
      'lib/core/widgets/share_sheet.dart',
    ).readAsStringSync();
    expect(sheet, contains('isRequest ? null :'));
  });
}
