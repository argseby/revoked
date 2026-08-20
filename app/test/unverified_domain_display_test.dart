import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// An unproven domain must never be rendered with the typography of a fact.
///
/// `Name (example.com)` in plain text is the phishing primitive this product
/// exists to stop: the string comes from the request itself, so anyone can put
/// anything there. It may only be printed as a domain once DNS has proven it,
/// and a domain that provably failed must not be echoed at all — repeating it
/// only helps whoever chose it.
void main() {
  final source = File(
    'lib/features/requests/view/public_request_screen.dart',
  ).readAsStringSync();

  test('the bare "name (domain)" form is gated on a proven verdict', () {
    final interpolation = source.indexOf(r"'$name ($domain)'");
    expect(interpolation, isNot(-1), reason: 'the verified form should exist');

    // The only place it may appear is inside the proven branch.
    final guard = source.indexOf('if (_trustProven) {');
    expect(guard, isNot(-1), reason: '_requesterLine must branch on proof');
    expect(
      guard,
      lessThan(interpolation),
      reason: 'the domain is printed before anything checks it was proven',
    );
  });

  test('proof means verified, not merely "a verdict arrived"', () {
    expect(source, contains('TrustState.verified'));
    expect(
      source.contains(
        '_store.publicTrustVerdict?.state == TrustState.verified',
      ),
      isTrue,
      reason: '_trustProven must require the verified state specifically',
    );
  });

  test('the requester panel carries the verdict-gated warning line', () {
    // The full-width band was replaced by the info panel; the warning
    // must still exist somewhere the responder cannot miss.
    expect(source, contains('_requesterLine('));
    expect(source, contains('_trustTag('));
  });

  shareTrust();

  test('no check-shield is drawn for an unproven request', () {
    // The header icon and the null-verdict tag both used to claim a checkmark.
    expect(
      source,
      contains('_trustProven ? AppIcons.shieldCheck : AppIcons.exclamation'),
      reason: 'the panel header icon must follow the verdict',
    );
    final nullVerdictTag = source.indexOf("label: 'Unverified',");
    final windowStart = nullVerdictTag - 200;
    expect(
      source.substring(windowStart, nullVerdictTag),
      isNot(contains('shieldCheck')),
      reason: 'an unverified request must not be tagged with a check shield',
    );
  });
}

/// The share side of the same rule. A share carries no domain of its own, but a
/// signed one carries the sharer's identity — so it can and must be checked,
/// and the shield must follow the answer rather than assert it.
void shareTrust() {
  final source = File(
    'lib/features/shares/view/public_share_screen.dart',
  ).readAsStringSync();

  test('the public share view walks the DNS chain', () {
    expect(source, contains('_verifyShareTrust('));
    expect(source, contains('Stores.domainVerification.verify('));
  });

  test('no shield is drawn green unless the share is proven', () {
    expect(source, contains('_shareProven ? AppIcons.shieldLock'));
    expect(source, contains('_shareProven ? AppIcons.share'));
    expect(
      source,
      contains('_store.shareTrustVerdict?.state == TrustState.verified'),
      reason: 'proof must mean verified, not merely "a verdict arrived"',
    );
  });

  test('the share info panel states the verdict, including "not signed"', () {
    // Absence of an identity is a finding, not a blank: an unsigned share
    // must say so in the panel that sits beside the data.
    expect(source, contains('_buildInfoPanel(theme)'));
    expect(source, contains("Text('Not signed')"));
    expect(
      source,
      contains('an unsigned share carries no domain claim'),
      reason: 'the DNS line must explain why there is nothing to verify',
    );
  });
}
