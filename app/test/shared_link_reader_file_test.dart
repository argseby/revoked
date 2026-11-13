import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/crypto/sealing.dart';
import 'package:revoked_app/features/shares/store/shared_link_reader.dart';

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final v = jsonDecode(
    File('test/fixtures/sealing_file_vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final key = SealedFormats.parseLinkKey(v['linkKey'] as String)!;
  final served = {
    ...(v['entry'] as Map<String, dynamic>),
    'sealed': true,
    'type': 'file',
    'label': 'stated by the server',
    'size': 99,
    'downloadToken': 'token',
  };
  final x = (v['content'] as Map<String, dynamic>)['x'] as Map<String, dynamic>;
  Map<String, dynamic> open(Uint8List? k) =>
      (SharedLinkReader.open({
                    'records': [served],
                  }, k)['records']
                  as List)
              .single
          as Map<String, dynamic>;

  test('an encrypted file opens from the address to its bytes', () {
    final r = open(key);
    expect(r['type'], 'file');
    expect(r['filename'], x['n']);
    expect(r['mime'], x['m']);
    expect(r['size'], x['s']);
    expect(r['downloadToken'], 'token');
    final bytes = SharedLinkReader.openFile(
      r,
      SealedFormats.decode(v['blob'] as String),
    );
    expect(_hex(Sealing.sha256(bytes)), v['plaintextSha256']);
  });

  test('a changed blob does not open', () {
    final r = open(key);
    final blob = SealedFormats.decode(v['blob'] as String);
    blob[blob.length - 50] ^= 1;
    expect(
      () => SharedLinkReader.openFile(r, blob),
      throwsA(isA<SealingException>()),
    );
  });

  test('a closed file carries no key and no download', () {
    final r = open(null);
    expect(r[SharedLinkReader.closedField], ClosedEntry.incomplete.name);
    expect(r.containsKey('downloadToken'), isFalse);
    expect(r.containsKey(SharedLinkReader.fileSealField), isFalse);
  });
}
