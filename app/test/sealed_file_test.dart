import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/crypto/sealing.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart';

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

Uint8List _bytes(int n) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) (i * 13 + 5) % 256]);

void main() {
  const workspace = 'wsfiletest00001';
  const record = 'recfiletest0001';
  final fileKey = SealedFile.newFileKey();

  Uint8List seal(Uint8List bytes) => SealedFile.seal(
    fileKey: fileKey,
    bytes: bytes,
    workspace: workspace,
    record: record,
  );

  Uint8List open(
    Uint8List blob,
    int size, {
    String ws = workspace,
    String rec = record,
    Uint8List? key,
  }) => SealedFile.open(
    fileKey: key ?? fileKey,
    blob: blob,
    workspace: ws,
    record: rec,
    size: size,
  );

  group('the pinned vector', () {
    final v = jsonDecode(
      File('test/fixtures/sealing_file_vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final entry = v['entry'] as Map<String, dynamic>;

    test('opens from the address to the bytes', () {
      final copyKey = SealedFormats.linkCopyKey(
        linkKey: SealedFormats.parseLinkKey(v['linkKey'] as String)!,
        record: entry['id'] as String,
      );
      final viewer = SealedFormats.openLinkViewer(
        copyKey: copyKey,
        wrapped: entry['viewerWrap'] as String,
        record: entry['id'] as String,
        version: entry['sealedVersion'] as int,
      );
      final content = SealedContent.tryDecode(
        SealedFormats.openValue(
          valueKey: viewer.valueKey,
          sealed: entry['sealedValue'] as String,
          workspace: viewer.workspace,
          record: entry['id'] as String,
          recordKey: entry['key'] as String,
          version: entry['sealedVersion'] as int,
        ),
      )!;
      final expected = v['content'] as Map<String, dynamic>;
      final x = expected['x'] as Map<String, dynamic>;
      expect(content.type, 'file');
      expect(content.value, '');
      expect(content.label, expected['l']);
      expect(content.file!.name, x['n']);
      expect(content.file!.mime, x['m']);
      expect(content.file!.size, x['s']);

      final bytes = SealedFile.open(
        fileKey: content.file!.fileKey,
        blob: SealedFormats.decode(v['blob'] as String),
        workspace: viewer.workspace,
        record: entry['id'] as String,
        size: content.file!.size,
      );
      expect(_hex(Sealing.sha256(bytes)), v['plaintextSha256']);
      for (var i = 0; i < bytes.length; i += 977) {
        expect(bytes[i], (i * 31 + 7) % 256);
      }

      final small = v['small'] as Map<String, dynamic>;
      final text = utf8.encode(small['text'] as String);
      expect(
        SealedFile.open(
          fileKey: content.file!.fileKey,
          blob: SealedFormats.decode(small['blob'] as String),
          workspace: viewer.workspace,
          record: entry['id'] as String,
          size: text.length,
        ),
        text,
      );
    });
  });

  group('round trip', () {
    for (final size in [
      0,
      1,
      1024,
      1025,
      SealedFile.segmentLength - 1,
      SealedFile.segmentLength,
      SealedFile.segmentLength + 1,
      3 * SealedFile.segmentLength,
      200000,
    ]) {
      test('$size bytes', () {
        final bytes = _bytes(size);
        final blob = seal(bytes);
        expect(blob.length, SealedFile.blobLength(size));
        expect(open(blob, size), bytes);
      });
    }

    test('two seals of the same file differ', () {
      final bytes = _bytes(5000);
      expect(seal(bytes), isNot(seal(bytes)));
    });
  });

  group('padding', () {
    test('small files share one length', () {
      expect(SealedFile.blobLength(0), SealedFile.blobLength(1024));
    });

    test('never shrinks and adds at most 12.5 %', () {
      var previous = 0;
      for (var size = 1; size < 30 * 1024 * 1024; size = size * 3 ~/ 2 + 7) {
        final padded = SealedFile.paddedLength(size);
        expect(padded, greaterThanOrEqualTo(size));
        expect(padded, greaterThanOrEqualTo(previous));
        if (size > 1024) expect(padded / size, lessThanOrEqualTo(1.125));
        previous = padded;
      }
    });

    test('hides the exact size', () {
      expect(SealedFile.blobLength(100000), SealedFile.blobLength(100100));
    });
  });

  group('tampering fails', () {
    const size = 3 * SealedFile.segmentLength + 500;
    final bytes = _bytes(size);
    late Uint8List blob;
    setUp(() => blob = seal(bytes));

    Matcher fails() => throwsA(isA<SealingException>());

    test('moved to another record', () {
      expect(() => open(blob, size, rec: 'recother0000001'), fails());
    });

    test('moved to another workspace', () {
      expect(() => open(blob, size, ws: 'wsother00000001'), fails());
    });

    test('opened with another file key', () {
      expect(() => open(blob, size, key: SealedFile.newFileKey()), fails());
    });

    test('a flipped bit', () {
      final bad = Uint8List.fromList(blob)..[blob.length ~/ 2] ^= 1;
      expect(() => open(bad, size), fails());
    });

    test('a flipped salt', () {
      final bad = Uint8List.fromList(blob)..[3] ^= 1;
      expect(() => open(bad, size), fails());
    });

    test('a dropped segment', () {
      const seg = SealedFile.segmentLength + 16;
      final bad = Uint8List.fromList([
        ...blob.sublist(0, 17 + seg),
        ...blob.sublist(17 + 2 * seg),
      ]);
      expect(() => open(bad, size - SealedFile.segmentLength), fails());
    });

    test('two segments swapped', () {
      const seg = SealedFile.segmentLength + 16;
      final bad = Uint8List.fromList([
        ...blob.sublist(0, 17),
        ...blob.sublist(17 + seg, 17 + 2 * seg),
        ...blob.sublist(17, 17 + seg),
        ...blob.sublist(17 + 2 * seg),
      ]);
      expect(() => open(bad, size), fails());
    });

    test('cut after a full segment', () {
      expect(
        SealedFile.blobLength(2 * SealedFile.segmentLength),
        17 + 2 * (SealedFile.segmentLength + 16),
      );
      // Whole segments only: the reader must notice the missing last flag,
      // not just a length that no longer matches.
      final cut = 17 + 2 * (SealedFile.segmentLength + 16);
      final bad = Uint8List.sublistView(blob, 0, cut);
      expect(
        () => SealedFile.open(
          fileKey: fileKey,
          blob: bad,
          workspace: workspace,
          record: record,
          size: 2 * SealedFile.segmentLength,
        ),
        fails(),
      );
    });

    test('a size the sealed value does not state', () {
      // The size is authenticated inside the sealed value, so only a writer
      // can state it. A wrong one still never yields the padded tail as data
      // nor drops real bytes unnoticed.
      expect(() => open(blob, size - 1), fails());
      expect(() => open(blob, SealedFile.paddedLength(size) + 1), fails());
    });

    test('padding that is not zeros', () {
      final padded = Uint8List(SealedFile.paddedLength(10))
        ..setAll(0, _bytes(10))
        ..[20] = 1;
      final bad = seal(padded);
      expect(() => open(bad, 10), fails());
    });

    test('a later format version', () {
      final bad = Uint8List.fromList(blob)..[0] = 2;
      expect(() => open(bad, size), fails());
    });
  });

  group('the descriptor', () {
    final info = SealedFileInfo(
      name: 'Pass.pdf',
      mime: 'application/pdf',
      size: 12,
      fileKey: SealedFile.newFileKey(),
    );

    test('round-trips inside the sealed value', () {
      final text = SealedContent(
        value: '',
        label: 'Pass',
        type: 'file',
        format: 'default',
        file: info,
      ).encode();
      final back = SealedContent.tryDecode(text)!;
      expect(back.file!.name, 'Pass.pdf');
      expect(back.file!.fileKey, info.fileKey);
    });

    test('a value without one is unchanged', () {
      final text = const SealedContent(
        value: 'x',
        label: 'l',
        type: 'text',
        format: 'default',
      ).encode();
      expect(jsonDecode(text), {
        'v': 'x',
        'l': 'l',
        't': 'text',
        'f': 'default',
      });
    });

    test('a file needs a complete one, and a value none', () {
      String content(Map<String, dynamic> m) => jsonEncode(m);
      final x = info.toJson();
      expect(
        SealedContent.tryDecode(
          content({'v': '', 'l': 'l', 't': 'file', 'f': 'default'}),
        ),
        isNull,
      );
      expect(
        SealedContent.tryDecode(
          content({'v': 'x', 'l': 'l', 't': 'file', 'f': 'default', 'x': x}),
        ),
        isNull,
      );
      expect(
        SealedContent.tryDecode(
          content({'v': '', 'l': 'l', 't': 'text', 'f': 'default', 'x': x}),
        ),
        isNull,
      );
      expect(
        SealedContent.tryDecode(
          content({
            'v': '',
            'l': 'l',
            't': 'file',
            'f': 'default',
            'x': {...x, 'k': 'short'},
          }),
        ),
        isNull,
      );
      expect(
        SealedContent.tryDecode(
          content({
            'v': '',
            'l': 'l',
            't': 'file',
            'f': 'default',
            'x': {...x, 's': SealedFile.maxLength + 1},
          }),
        ),
        isNull,
      );
    });
  });
}
