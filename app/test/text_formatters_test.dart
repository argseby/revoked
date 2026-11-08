import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/widgets/text_formatters.dart';

TextEditingValue _type(TextInputFormatter f, String text) => f.formatEditUpdate(
  TextEditingValue.empty,
  TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  ),
);

void main() {
  test('a key spells out German letters instead of dropping them', () {
    final v = _type(KeyInputFormatter(), 'Größe Straße');
    expect(v.text, 'groesse_strasse');
    expect(v.selection.baseOffset, v.text.length);
  });

  test('a slug spells out German letters instead of dropping them', () {
    final v = _type(SlugInputFormatter(), 'Mütter-Übersicht');
    expect(v.text, 'muetter-uebersicht');
    expect(v.selection.baseOffset, v.text.length);
  });

  test('a key made from a German label stays readable', () {
    expect(
      keyFromLabel('Geburtsdatum Mütter', const []),
      'geburtsdatum_muetter',
    );
    expect(keyFromLabel('Straße', const ['strasse']), 'strasse_2');
  });
}
