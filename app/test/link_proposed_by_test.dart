import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/link.dart';

/// A link a connected tool proposed says so, and names the tool by the host
/// the server recorded — also after the tool was disconnected, when the link
/// no longer has a connection to look the name up in.
void main() {
  Map<String, dynamic> json([Map<String, dynamic> extra = const {}]) => {
    'id': 'abc123def456ghi',
    'slug': 's',
    'label': 'Emergency card',
    ...extra,
  };

  test('a link made in the app carries no tool', () {
    final link = Link.fromJson(json());
    expect(link.isFromTool, isFalse);
  });

  test('a proposed link names its tool by host, without a connection', () {
    final link = Link.fromJson(
      json({'connection': '', 'proposedBy': 'https://notfallkarte.example'}),
    );
    expect(link.isFromTool, isTrue);
    expect(link.proposedByHost, 'notfallkarte.example');
    expect(
      Link.fromJson(
        json({'proposedBy': 'http://localhost:5173'}),
      ).proposedByHost,
      'localhost:5173',
    );
  });

  test('the links list shows where a link came from', () {
    final screen = File(
      'lib/features/shares/view/shares_screen.dart',
    ).readAsStringSync();
    expect(screen, contains('share.isFromTool'));
    expect(screen, contains('share.proposedByHost'));
  });
}
