import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// An unproven claim must never be rendered with the typography of a fact.
///
/// The strings arrive inside the request/share itself, so anyone can put
/// anything there. Trust is stated through exactly one vocabulary
/// (TrustCopy) and two widgets (TrustPanel for surfaces, TrustClaimText for
/// inline claims) — the same fact must never read differently on two screens.
void main() {
  final request = File(
    'lib/features/requests/view/public_request_screen.dart',
  ).readAsStringSync();
  final share = File(
    'lib/features/shares/view/public_share_screen.dart',
  ).readAsStringSync();
  final linkSheet = File(
    'lib/features/shell/view/link_search_sheet.dart',
  ).readAsStringSync();
  final panel = File('lib/core/widgets/trust_panel.dart').readAsStringSync();

  test('every trust surface renders through TrustPanel', () {
    for (final (name, source) in [
      ('request', request),
      ('share', share),
      ('link sheet', linkSheet),
    ]) {
      expect(
        source.contains('TrustPanel(checks:'),
        isTrue,
        reason: '$name must state trust through the shared panel',
      );
    }
  });

  test('proof means TrustState.verified, never merely "a verdict arrived"', () {
    for (final source in [request, share]) {
      expect(source, contains('TrustState.verified'));
    }
    // Both screens derive their check states from the verdict, and only
    // TrustState.verified may map to a green row.
    expect(request, contains("verdict?.state == TrustState.verified"));
    expect(share, contains("verdict?.state == TrustState.verified"));
  });

  test('an unsigned share is a failed check, not a blank', () {
    expect(share, contains('nothing proves who '));
    expect(share, contains('TrustCheckState.failed'));
  });

  test('the link origin is checked against the claimed domain', () {
    // The link routes the fetch; the sender claims a domain. When the two
    // disagree, the panel must say so on every surface that has an origin.
    for (final source in [request, share, linkSheet]) {
      expect(
        source,
        contains('The link points at a different server'),
        reason: 'origin-vs-domain mismatch must be a named check',
      );
    }
  });

  test('headers carry no verdict-conditional icons', () {
    // Status belongs to the trust panel alone. A shield or exclamation on a
    // card header restates the verdict in a second, unexplained vocabulary -
    // the confusion this pins against.
    for (final (name, source) in [('request', request), ('share', share)]) {
      expect(
        source.contains('? AppIcons.shieldCheck : AppIcons.exclamation') ||
            source.contains('? AppIcons.shieldLock : AppIcons.exclamation') ||
            source.contains('? AppIcons.share : AppIcons.exclamation') ||
            source.contains(
              '? AppIcons.shieldLock : AppIcons.exclamationTriangle',
            ),
        isFalse,
        reason: '$name must not gate a header icon on the verdict',
      );
    }
  });

  test('inline domain claims go through TrustClaimText only', () {
    final picker = File(
      'lib/core/widgets/identity_picker.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/features/settings/view/settings_screen.dart',
    ).readAsStringSync();
    expect(picker, contains('TrustClaimText('));
    expect(settings, contains('TrustClaimText('));
    for (final (name, source) in [('picker', picker), ('settings', settings)]) {
      expect(
        source.contains('issued by \${') ||
            source.contains('· \${id.domainAtIssue}'),
        isFalse,
        reason: '$name must not print a domain claim as bare prose',
      );
    }
  });

  test('the vocabulary is single-sourced and the alarm words exist', () {
    expect(panel, contains("static const verified = 'DNS verified'"));
    expect(panel, contains("static const spoofed = 'Spoofed'"));
    expect(panel, contains("static const unsigned = 'Not signed'"));
    expect(panel, contains('Do not send'));
  });
}
