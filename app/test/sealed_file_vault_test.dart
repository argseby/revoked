import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/crypto/sealing.dart';
import 'package:revoked_app/core/files/pending_upload.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart';
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _me = 'user000000000aa';
const _workspace = 'wspace00000000a';
const _accountScope = 'account:$_me';
const _canary = 'payslip-canary-41c7';

/// One part of a multipart body: its form name, file name and raw bytes.
typedef _Part = ({String name, String? filename, Uint8List bytes});

/// Splits a multipart body without a library. Latin-1 keeps every byte as one
/// character, so a binary blob comes back exactly as sent.
List<_Part> _parts(http.Request request) {
  final type = request.headers['content-type']!;
  final boundary = '--${type.split('boundary=').last}';
  final text = latin1.decode(request.bodyBytes);
  final out = <_Part>[];
  for (final chunk in text.split(boundary)) {
    final split = chunk.indexOf('\r\n\r\n');
    if (split < 0) continue;
    final head = chunk.substring(0, split);
    var body = chunk.substring(split + 4);
    if (body.endsWith('\r\n')) body = body.substring(0, body.length - 2);
    final name = RegExp(r'name="([^"]*)"').firstMatch(head)!.group(1)!;
    final filename = RegExp(r'filename="([^"]*)"').firstMatch(head)?.group(1);
    out.add((
      name: name,
      filename: filename,
      bytes: Uint8List.fromList(latin1.encode(body)),
    ));
  }
  return out;
}

/// An honest server for encrypted files (design/e2ee-sharing.md §7): it keeps
/// what it is given and opens nothing. A file's blob comes as multipart beside
/// the usual JSON in `meta`.
class _Server {
  final devices = <Map<String, dynamic>>[];
  final epochs = <Map<String, dynamic>>[];
  final wraps = <Map<String, dynamic>>[];
  final accountEpochs = <Map<String, dynamic>>[];
  final accountWraps = <Map<String, dynamic>>[];
  final records = <String, Map<String, dynamic>>{};
  final blobs = <String, Uint8List>{};

  /// Records some live link carries, as the server counts them.
  final onLinks = <String>{};

  /// Every byte sent, as Latin-1, to look for what must never arrive.
  final received = StringBuffer();
  final writes = <({String path, Map<String, dynamic> meta, _Part? blob})>[];

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    final method = request.method;
    received.writeln(latin1.decode(request.bodyBytes));
    final multipart =
        request.headers['content-type']?.startsWith('multipart/') ?? false;
    _Part? blob;
    Map<String, dynamic> body;
    if (multipart) {
      final parts = _parts(request);
      body = jsonDecode(
        utf8.decode(parts.firstWhere((p) => p.name == 'meta').bytes),
      ) as Map<String, dynamic>;
      blob = parts.where((p) => p.name == 'blob').firstOrNull;
    } else {
      body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map<String, dynamic>;
    }

    if (path == '/api/server') {
      return _json({
        'sealing': {'records': true},
        'limits': {'maxFileSize': -1},
      });
    }
    if (path == '/api/sealed/state') {
      return _json({
        'devices': devices,
        'workspaces': [
          if (epochs.isNotEmpty)
            {'workspace': _workspace, 'epochs': epochs, 'wraps': wraps},
        ],
        'account': accountEpochs.isEmpty
            ? null
            : {
                'workspace': _accountScope,
                'epochs': accountEpochs,
                'wraps': accountWraps,
              },
      });
    }
    if (path == '/api/sealed/devices') {
      for (final raw in body['entries'] as List<dynamic>) {
        devices.add({...raw as Map<String, dynamic>, 'user': _me});
      }
      for (final raw in body['wraps'] as List<dynamic>? ?? const []) {
        final wrap = raw as Map<String, dynamic>;
        (wrap['workspace'] == _accountScope ? accountWraps : wraps).add(wrap);
      }
      return _json({'ok': true});
    }
    if (path.endsWith('/epochs')) {
      final account = path == '/api/sealed/account/epochs';
      (account ? accountEpochs : epochs).add({
        'epoch': body['epoch'],
        'priorWrap': body['priorWrap'],
        'rotationDue': false,
      });
      for (final raw in body['wraps'] as List<dynamic>) {
        (account ? accountWraps : wraps).add(raw as Map<String, dynamic>);
      }
      return _json({'ok': true});
    }

    if (path == '/api/sealed/records' && method == 'POST') {
      writes.add((path: path, meta: body, blob: blob));
      final id = body['id'] as String;
      if ((body['type'] == 'file') != (blob != null)) {
        return _refuse(400, 'sealed_invalid');
      }
      records[id] = {
        'id': id,
        'key': body['key'],
        'label': body['label'],
        'type': body['type'],
        'format': body['format'],
        'user': _me,
        'workspace': _workspace,
        'value': '',
        'sealed': true,
        'sealedValue': body['sealedValue'],
        'sealedVersion': 1,
        'keyEpoch': body['keyEpoch'],
        'keyWrap': body['keyWrap'],
        if (blob != null) ..._storeBlob(id, blob.bytes),
      };
      return _json(records[id]!);
    }
    final unseal = RegExp(r'^/api/sealed/records/([^/]+)/unseal$')
        .firstMatch(path);
    if (unseal != null) {
      writes.add((path: path, meta: body, blob: blob));
      final record = records[unseal.group(1)!]!;
      record
        ..['sealed'] = false
        ..['sealedValue'] = ''
        ..['sealedVersion'] = (record['sealedVersion'] as int) + 1
        ..['filename'] = body['filename']
        ..['mime'] = 'application/pdf'
        ..addAll(_storeBlob(record['id'] as String, blob!.bytes))
        ..['size'] = blob.bytes.length;
      return _json(record);
    }
    final recordLinks = RegExp(r'^/api/sealed/records/([^/]+)/links$')
        .firstMatch(path);
    if (recordLinks != null) {
      return _json({'record': recordLinks.group(1), 'links': []});
    }
    final recordWrite = RegExp(r'^/api/sealed/records/([^/]+)$')
        .firstMatch(path);
    if (recordWrite != null && method == 'PUT') {
      writes.add((path: path, meta: body, blob: blob));
      final id = recordWrite.group(1)!;
      final record = records[id]!;
      if (record['sealedVersion'] != body['expectedVersion']) {
        return _refuse(409, 'sealed_version_conflict');
      }
      if (record['sealed'] != true &&
          onLinks.contains(id) &&
          body['dropLinks'] != true &&
          (body['linkSeals'] as List?)?.isNotEmpty != true) {
        return _refuse(409, 'sealed_links_affected');
      }
      final isFile = record['type'] == 'file';
      if ((blob != null && !isFile) ||
          (isFile && record['sealed'] != true && blob == null)) {
        return _refuse(400, 'sealed_invalid');
      }
      record
        ..['sealed'] = true
        ..['value'] = ''
        ..['label'] = body['label'] ?? record['label']
        ..['format'] = body['format'] ?? record['format']
        ..['sealedValue'] = body['sealedValue']
        ..['sealedVersion'] = (record['sealedVersion'] as int) + 1
        ..['keyEpoch'] = body['keyEpoch']
        ..['keyWrap'] = body['keyWrap'];
      if (blob != null) {
        record
          ..addAll(_storeBlob(id, blob.bytes))
          ..['filename'] = ''
          ..['contentHash'] = '';
      }
      return _json(record);
    }
    if (path == '/api/files/token') return _json({'token': 'file-token'});
    final file = RegExp(r'^/api/files/records/([^/]+)/([^/]+)$')
        .firstMatch(path);
    if (file != null) {
      final record = records[file.group(1)!]!;
      if (record['file'] != file.group(2)) return http.Response('', 404);
      return http.Response.bytes(blobs[record['id']]!, 200);
    }
    if (method == 'GET') {
      if (path == '/api/collections/records/records') {
        return _json({'items': records.values.toList()});
      }
      if (path == '/api/collections/sections/records' ||
          path == '/api/collections/links/records' ||
          path == '/api/collections/templates/records' ||
          path == '/api/collections/identities/records' ||
          path == '/api/collections/bookmarks/records' ||
          path == '/api/collections/bookmarkGroups/records' ||
          path == '/api/collections/connections/records') {
        return _json({'items': []});
      }
      if (path == '/api/shared/vault') {
        return _json({'records': [], 'sections': []});
      }
    }
    return http.Response('{}', 404);
  }

  var _stored = 0;

  Map<String, dynamic> _storeBlob(String id, Uint8List bytes) {
    blobs[id] = bytes;
    return {'file': 'stored_${_stored++}.bin', 'size': bytes.length};
  }

  static http.Response _json(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200);

  static http.Response _refuse(int status, String code) => http.Response(
    jsonEncode({'code': code, 'message': code, 'status': status}),
    status,
  );
}

Future<_Server> _signIn() async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final server = _Server();
  await Stores.init(httpClient: MockClient(server.handle));
  while (!Stores.auth.isInitialized) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  runInAction(
    () => Stores.auth.currentUser = User.fromJson({
      'id': _me,
      'email': 'ada@example.com',
      'activeWorkspace': _workspace,
    }),
  );
  final keys = Stores.keys;
  await keys.load();
  keys.beginSetup();
  final groups = keys.recoveryCode!.split('-');
  keys.recoveryConfirm.text = groups.sublist(groups.length - 2).join('-');
  expect(await keys.finishRecovery(workspace: _workspace), isTrue);
  expect(keys.status, SealingStatus.ready);
  return server;
}

Uint8List _pdf(String marker, int size) {
  final head = utf8.encode('%PDF-1.4 $marker ');
  return Uint8List.fromList([
    ...head,
    for (var i = head.length; i < size; i++) (i * 7) % 256,
  ]);
}

PendingUpload _upload(String name, Uint8List bytes) => PendingUpload(
  name: name,
  size: bytes.length,
  open: () => Stream.value(bytes),
);

Future<String> _createEncryptedFile(String name, Uint8List bytes) async {
  expect(
    await Stores.vault.createRecord(
      key: 'payslip',
      value: '',
      label: 'Payslip',
      type: 'file',
      format: 'default',
      user: _me,
      workspace: _workspace,
      file: _upload(name, bytes),
      sealed: true,
    ),
    isTrue,
    reason: Stores.vault.errorMessage,
  );
  return Stores.vault.records.firstWhere((r) => r.key == 'payslip').id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an encrypted file leaves the device as ciphertext only', () async {
    final server = await _signIn();
    final bytes = _pdf(_canary, 70000);
    final id = await _createEncryptedFile('Lohnabrechnung-Oktober.pdf', bytes);

    final write = server.writes.single;
    expect(write.meta['type'], 'file');
    expect(write.blob!.filename, 'encrypted.bin');
    expect(write.blob!.bytes.length, SealedFile.blobLength(bytes.length));
    final sent = server.received.toString();
    expect(sent, isNot(contains(_canary)));
    expect(sent, isNot(contains('Lohnabrechnung')));

    final record = Stores.vault.records.firstWhere((r) => r.id == id);
    expect(record.isSealedFile, isTrue);
    expect(record.displayName, 'Lohnabrechnung-Oktober.pdf');
    expect(record.mime, 'application/pdf');
    expect(record.size, bytes.length);
    expect(await Stores.vault.fetchRecordFileBytes(record), bytes);
  });

  test('a reload opens the name and the file from the seal', () async {
    final server = await _signIn();
    final bytes = _pdf(_canary, 3000);
    await _createEncryptedFile('Pass.pdf', bytes);
    await Stores.vault.loadRecords();
    final record = Stores.vault.records.single;
    expect(record.isLocked, isFalse);
    expect(record.displayName, 'Pass.pdf');
    expect(record.size, bytes.length);
    expect(server.records.values.single['size'], isNot(bytes.length));
    expect(await Stores.vault.fetchRecordFileBytes(record), bytes);
  });

  test('a rename keeps the blob, new content replaces it', () async {
    final server = await _signIn();
    final first = _pdf('first', 4000);
    final id = await _createEncryptedFile('a.pdf', first);
    final blob = server.blobs[id];

    expect(
      await Stores.vault.updateRecord(id, {'filename': 'b.pdf'}),
      isTrue,
      reason: Stores.vault.errorMessage,
    );
    expect(server.writes.last.blob, isNull);
    expect(server.blobs[id], same(blob));
    var record = Stores.vault.records.firstWhere((r) => r.id == id);
    expect(record.displayName, 'b.pdf');
    expect(await Stores.vault.fetchRecordFileBytes(record), first);

    final second = _pdf('second', 9000);
    expect(
      await Stores.vault.updateRecordFile(id, _upload('c.pdf', second)),
      isTrue,
      reason: Stores.vault.errorMessage,
    );
    expect(server.writes.last.blob, isNotNull);
    record = Stores.vault.records.firstWhere((r) => r.id == id);
    expect(record.displayName, 'b.pdf');
    expect(record.size, second.length);
    expect(await Stores.vault.fetchRecordFileBytes(record), second);
  });

  test('a blob moved from another record does not open', () async {
    final server = await _signIn();
    final id = await _createEncryptedFile('a.pdf', _pdf('a', 3000));
    final other = Sealing.randomBytes(SealedFile.blobLength(3000))..[0] = 1;
    server.blobs[id] = other;
    final record = Stores.vault.records.firstWhere((r) => r.id == id);
    expect(await Stores.vault.fetchRecordFileBytes(record), isNull);
    expect(Stores.vault.errorMessage, isNotNull);
  });

  test('a plain file is encrypted in place, and back', () async {
    final server = await _signIn();
    final plain = _pdf(_canary, 5000);
    server.records['plainfile000001'] = {
      'id': 'plainfile000001',
      'key': 'cv',
      'label': 'CV',
      'type': 'file',
      'format': 'default',
      'user': _me,
      'workspace': _workspace,
      'value': '',
      'filename': 'Lebenslauf.pdf',
      'mime': 'application/pdf',
      'contentHash': 'abc',
      'sealedVersion': 0,
      ...server._storeBlob('plainfile000001', plain),
    };
    await Stores.vault.loadRecords();

    expect(
      await Stores.vault.sealRecord('plainfile000001'),
      SealOutcome.sealed,
      reason: Stores.vault.errorMessage,
    );
    final sealedWrite = server.writes.last;
    expect(sealedWrite.meta['expectedVersion'], 0);
    expect(sealedWrite.blob, isNotNull);
    expect(
      latin1.decode(server.blobs['plainfile000001']!),
      isNot(contains(_canary)),
    );
    var record = Stores.vault.records.single;
    expect(record.isSealedFile, isTrue);
    expect(record.displayName, 'Lebenslauf.pdf');
    expect(await Stores.vault.fetchRecordFileBytes(record), plain);

    expect(
      await Stores.vault.unsealRecord(record.id),
      isTrue,
      reason: Stores.vault.errorMessage,
    );
    final unseal = server.writes.last;
    expect(unseal.blob!.bytes, plain);
    expect(unseal.meta['value'], '');
    expect(unseal.meta['filename'], 'Lebenslauf.pdf');
    expect(unseal.meta['signature'], isA<String>());
    record = Stores.vault.records.single;
    expect(record.sealed, isFalse);
    expect(await Stores.vault.fetchRecordFileBytes(record), plain);
  });

  test('a file over the encryption cap is refused before upload', () async {
    final server = await _signIn();
    final big = PendingUpload(
      name: 'huge.bin',
      size: SealedFile.maxLength + 1,
      open: () => const Stream.empty(),
    );
    expect(
      await Stores.vault.createRecord(
        key: 'huge',
        value: '',
        label: 'Huge',
        type: 'file',
        format: 'default',
        user: _me,
        workspace: _workspace,
        file: big,
        sealed: true,
      ),
      isFalse,
    );
    expect(Stores.vault.errorMessage, contains('50'));
    expect(server.writes, isEmpty);
  });

  test('a plain file on links this device cannot carry drops them after confirmation', () async {
    final server = await _signIn();
    server.records['plainfile000002'] = {
      'id': 'plainfile000002',
      'key': 'id_card',
      'label': 'ID card',
      'type': 'file',
      'format': 'default',
      'user': _me,
      'workspace': _workspace,
      'value': '',
      'filename': 'Ausweis.pdf',
      'mime': 'application/pdf',
      'sealedVersion': 0,
      ...server._storeBlob('plainfile000002', _pdf(_canary, 2000)),
    };
    server.onLinks.add('plainfile000002');
    await Stores.vault.loadRecords();

    expect(
      await Stores.vault.sealRecord('plainfile000002'),
      SealOutcome.linksAffected,
    );
    expect(
      await Stores.vault.sealRecord('plainfile000002', dropLinks: true),
      SealOutcome.sealed,
      reason: Stores.vault.errorMessage,
    );
    expect(server.writes.last.meta['linkSeals'], isNull);
    expect(server.writes.last.meta['dropLinks'], isTrue);
  });
}
