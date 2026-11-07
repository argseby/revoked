import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_sign_in/revoked_sign_in.dart';

void main() {
  test('the check code is spelled one character at a time', () {
    expect(spellCheckCode('0D2-99B'), '0 D 2, 9 9 B');
    expect(spellCheckCode(''), '');
  });

  test('German for de, English otherwise', () {
    expect(RevokedStrings.forLocale(const Locale('de', 'AT')).continueWith, 'Weiter mit Revoked');
    expect(RevokedStrings.forLocale(const Locale('fr')).continueWith, 'Continue with Revoked');
    expect(RevokedStrings.forLocale(null).continueWith, 'Continue with Revoked');
  });

  test('the icon-only button is named like the continue button', () {
    expect(RevokedStrings.en.label(RevokedLabel.iconOnly), RevokedStrings.en.continueWith);
    expect(RevokedStrings.de.label(RevokedLabel.signUp), 'Mit Revoked registrieren');
  });

  test('every check sentence has a place for the code', () {
    for (final strings in [RevokedStrings.en, RevokedStrings.de]) {
      expect(strings.check, contains('{code}'));
    }
  });
}
