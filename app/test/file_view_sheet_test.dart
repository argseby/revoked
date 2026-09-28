import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/widgets/file_view_sheet.dart';

void main() {
  test('images and text open in the app', () {
    expect(
      canViewInApp(mime: 'image/png', filename: 'a.png', size: 10),
      isTrue,
    );
    expect(canViewInApp(mime: 'text/plain', filename: 'a', size: 10), isTrue);
    expect(
      canViewInApp(
        mime: 'application/json; charset=utf-8',
        filename: 'a',
        size: 10,
      ),
      isTrue,
    );
  });

  test('a text file typed as octet-stream is recognised by its name', () {
    expect(
      canViewInApp(
        mime: 'application/octet-stream',
        filename: 'notes.TXT',
        size: 10,
      ),
      isTrue,
    );
  });

  test('documents, SVG and oversized text go to another app', () {
    expect(
      canViewInApp(mime: 'application/pdf', filename: 'a.pdf', size: 10),
      isFalse,
    );
    expect(
      canViewInApp(mime: 'image/svg+xml', filename: 'a.svg', size: 10),
      isFalse,
    );
    expect(
      canViewInApp(
        mime: 'text/plain',
        filename: 'big.txt',
        size: 2 * 1024 * 1024,
      ),
      isFalse,
    );
  });
}
