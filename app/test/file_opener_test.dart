import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/files/file_opener.dart';

/// A viewed file's name can come from whoever answered a request, and it
/// becomes a path on disk and an argument to the OS opener.
void main() {
  test('a plain name passes through', () {
    expect(safeOpenFilename('Contract 2026.pdf'), 'Contract 2026.pdf');
  });

  test('path segments cannot climb out of the temp directory', () {
    expect(safeOpenFilename('../../etc/passwd'), 'passwd');
    expect(safeOpenFilename(r'..\..\Windows\evil.bat'), 'evil.bat');
    expect(safeOpenFilename('..'), 'file');
  });

  test('shell metacharacters never survive', () {
    final name = safeOpenFilename('a&calc^|"x".pdf');
    expect(name, 'a_calc___x_.pdf');
    expect(name, isNot(matches(RegExp(r'[&^|"<>%;$`]'))));
  });

  test('a leading dot cannot hide the file', () {
    expect(safeOpenFilename('.bashrc'), 'bashrc');
  });

  test('a missing extension is taken from the type', () {
    expect(safeOpenFilename('scan', 'application/pdf'), 'scan.pdf');
    expect(
      safeOpenFilename('photo', 'image/jpeg; charset=binary'),
      'photo.jpg',
    );
    expect(safeOpenFilename('blob', 'application/x-unknown'), 'blob');
  });

  test('a long name is cut but keeps its extension', () {
    final name = safeOpenFilename('${'a' * 300}.docx');
    expect(name.length, 120);
    expect(name, endsWith('.docx'));
  });
}
