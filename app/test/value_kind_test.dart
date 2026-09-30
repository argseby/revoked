import 'package:flutter_test/flutter_test.dart';

import 'package:revoked_app/core/utils/value_kind.dart';

/// A shared value gets an icon for what it is and an action that fits it:
/// call a number, write to an address, open a web page. The rules match the
/// public web page, so a value reads the same in the browser and the app.
void main() {
  ValueKind kind(String value, {String type = 'text', String key = ''}) =>
      valueKindOf(type: type, value: value, key: key);

  group('valueKindOf', () {
    test('recognises contact details inside plain text', () {
      expect(kind('+49 170 1234567'), ValueKind.phone);
      expect(kind('0221 123456'), ValueKind.phone);
      expect(kind('anna.weber@mail.de'), ValueKind.email);
      expect(kind('https://example.com/a'), ValueKind.url);
      expect(kind('www.example.com'), ValueKind.url);
    });

    test('a number is only a phone number when it looks like one', () {
      expect(kind('3450', type: 'number'), ValueKind.number);
      expect(kind('50674'), ValueKind.text);
      expect(kind('12 345 678', key: 'phone'), ValueKind.phone);
      expect(kind('1991-04-12'), ValueKind.date);
    });

    test('the record type wins where it says more', () {
      expect(kind('true', type: 'boolean'), ValueKind.boolean);
      expect(kind('linkedin.com/in/a', type: 'url'), ValueKind.url);
      expect(
        valueKindOf(type: 'file', value: '', filename: 'payslip.PDF'),
        ValueKind.pdf,
      );
      expect(
        valueKindOf(type: 'file', value: '', mime: 'image/png'),
        ValueKind.image,
      );
    });

    test('falls back to the key for everyday fields', () {
      expect(kind('Lindenstr. 4', key: 'current_address'), ValueKind.place);
      expect(kind('Stadtwerke', key: 'employer'), ValueKind.work);
      expect(kind('Anna Weber', key: 'full_name'), ValueKind.person);
      expect(kind('Anything'), ValueKind.text);
    });
  });

  test('displayValue reads the way a person would say it', () {
    expect(displayValue(ValueKind.boolean, 'true'), 'Yes');
    expect(displayValue(ValueKind.boolean, 'false'), 'No');
    expect(displayValue(ValueKind.date, '1991-04-12'), '12 April 1991');
    expect(displayValue(ValueKind.text, '  kept  '), 'kept');
  });

  group('actionUri', () {
    test('builds only tel, mailto and web links', () {
      expect(
        actionUri(ValueKind.phone, '+49 (170) 123-4567').toString(),
        'tel:+491701234567',
      );
      expect(actionUri(ValueKind.email, 'a@b.de').toString(), 'mailto:a@b.de');
      expect(
        actionUri(ValueKind.url, 'example.com/x').toString(),
        'https://example.com/x',
      );
      expect(actionUri(ValueKind.text, 'hello'), isNull);
    });

    test('a shared value can never become a script link', () {
      expect(actionUri(ValueKind.url, 'javascript:alert(1)'), isNull);
      expect(actionUri(ValueKind.email, 'not an address'), isNull);
    });
  });
}
