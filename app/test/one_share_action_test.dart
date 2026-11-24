import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('request details use one action for sharing', () {
    final detail = File('lib/features/requests/view/request_detail_screen.dart')
        .readAsStringSync();
    expect(detail, contains('showShareSheet('));
    expect(detail, isNot(contains("label: 'Copy link'")));
    expect(detail, isNot(contains("label: 'QR code'")));
    expect(detail, isNot(contains("label: 'Web & API'")));
  });

  test('a request is never handed out as a web link', () {
    // The browser page is read-only by design. A request collects input, and
    // input belongs in the app, which verifies the server before anything is
    // typed — so the sheet must keep the web link share-only.
    final sheet = File('lib/core/widgets/share_sheet.dart').readAsStringSync();
    expect(sheet, contains('isRequest ? null :'));
  });
}
