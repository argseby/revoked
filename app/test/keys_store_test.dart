import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/crypto/sealing.dart';
import 'package:revoked_app/core/models/passkey.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart';

const _user = 'user000000000aa';
const _workspace = 'wspace00000000a';
const _otherWorkspace = 'wspace00000000b';
const _canary = 'smtp-password-canary-9d2f';
const _recordKey = 'smtp_password';

/// One device's own storage. A shared map would make two devices the same one.
class _DeviceStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async => values.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Plays an honest server that keeps what it is given and records every byte it
/// was sent. A test tampers with its state, or sets a hook, to play a dishonest
/// one.
class _FakeServer {
  List<Map<String, dynamic>> devices = [];
  final List<Map<String, dynamic>> epochs = [];
  final List<Map<String, dynamic>> wraps = [];
  final List<Map<String, dynamic>> otherEpochs = [];
  final List<Map<String, dynamic>> otherWraps = [];
  final StringBuffer received = StringBuffer();

  bool supportsSealing = true;
  bool failEpochs = false;

  /// Answers "ok" to a device list change and stores nothing.
  bool dropEntries = false;

  /// Fails the first state read after a device list change.
  bool failStateAfterDevices = false;

  /// Refuses device list changes outright.
  bool failDevices = false;

  /// Lets a dishonest server rewrite what it answers.
  Map<String, dynamic> Function(Map<String, dynamic> state)? tamperState;

  bool _failNextState = false;

  http.Client get client => MockClient((request) async {
    received
      ..writeln(request.url)
      ..writeln(request.headers)
      ..writeln(request.body);
    final path = request.url.path;
    if (path == '/api/server') {
      return _json({
        'sealing': {'records': supportsSealing},
      });
    }
    if (path == '/api/sealed/state') {
      if (_failNextState) {
        _failNextState = false;
        return http.Response('{"message":"down"}', 500);
      }
      final current = state();
      return _json(tamperState == null ? current : tamperState!(current));
    }
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (path == '/api/sealed/devices') {
      if (dropEntries) return _json({'ok': true});
      if (failDevices) return http.Response('{"message":"down"}', 500);
      _failNextState = failStateAfterDevices;
      for (final raw in body['entries'] as List<dynamic>) {
        final entry = {...raw as Map<String, dynamic>, 'user': _user};
        if (entry['seq'] != devices.length + 1) {
          return http.Response(
            jsonEncode({'code': 'sealed_version_conflict', 'status': 409}),
            409,
          );
        }
        devices.add(entry);
        if (entry['action'] == 'remove') {
          for (final (keyEpochs, keyWraps) in [
            (epochs, wraps),
            (otherEpochs, otherWraps),
          ]) {
            keyWraps.removeWhere((w) => w['deviceSeq'] == entry['targetSeq']);
            if (keyEpochs.isNotEmpty) keyEpochs.last['rotationDue'] = true;
          }
        }
      }
      for (final raw in body['wraps'] as List<dynamic>? ?? const []) {
        final wrap = raw as Map<String, dynamic>;
        (wrap['workspace'] == _otherWorkspace ? otherWraps : wraps).add(wrap);
      }
      return _json({'ok': true});
    }
    if (path.endsWith('/epochs')) {
      if (failEpochs) return http.Response('{"message":"down"}', 500);
      final other = path.contains('/$_otherWorkspace/');
      final keyEpochs = other ? otherEpochs : epochs;
      final keyWraps = other ? otherWraps : wraps;
      if (body['epoch'] != keyEpochs.length + 1) {
        return http.Response(
          jsonEncode({'code': 'sealed_version_conflict', 'status': 409}),
          409,
        );
      }
      keyEpochs.add({
        'epoch': body['epoch'],
        'priorWrap': body['priorWrap'],
        'rotationDue': false,
      });
      for (final raw in body['wraps'] as List<dynamic>) {
        keyWraps.add(raw as Map<String, dynamic>);
      }
      return _json({'ok': true});
    }
    if (path == '/api/sealed/reset') {
      devices = [];
      epochs.clear();
      wraps.clear();
      otherEpochs.clear();
      otherWraps.clear();
      return _json({'ok': true, 'deleted': 0});
    }
    return http.Response('{}', 404);
  });

  Map<String, dynamic> state() =>
      jsonDecode(
            jsonEncode({
              'devices': devices,
              'workspaces': [
                if (epochs.isNotEmpty)
                  {'workspace': _workspace, 'epochs': epochs, 'wraps': wraps},
                if (otherEpochs.isNotEmpty)
                  {
                    'workspace': _otherWorkspace,
                    'epochs': otherEpochs,
                    'wraps': otherWraps,
                  },
              ],
            }),
          )
          as Map<String, dynamic>;

  static http.Response _json(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200);
}

KeysStore _device(_FakeServer server, {_DeviceStorage? storage}) => KeysStore(
  ApiClient(httpClient: server.client),
  currentUser: () => _user,
  storage: storage ?? _DeviceStorage(),
);

void _typeBack(KeysStore keys) {
  final groups = keys.recoveryCode!.split('-');
  keys.recoveryConfirm.text = groups.sublist(groups.length - 2).join('-');
}

/// Sets up encryption on a new device and returns it and the recovery code.
Future<(KeysStore, String)> _setUp(
  _FakeServer server, {
  _DeviceStorage? storage,
}) async {
  final keys = _device(server, storage: storage);
  await keys.load();
  keys.beginSetup();
  final code = keys.recoveryCode!;
  _typeBack(keys);
  expect(await keys.finishRecovery(workspace: _workspace), isTrue);
  expect(keys.status, SealingStatus.ready);
  return (keys, code);
}

models.Record _sealedRecord(
  KeysStore keys, {
  String id = 'record000000001',
  int version = 1,
  String value = _canary,
}) => _recordFrom(
  id,
  version,
  keys.sealValue(
    workspace: _workspace,
    record: id,
    recordKey: _recordKey,
    version: version,
    value: value,
  ),
);

models.Record _recordFrom(String id, int version, SealedPayload payload) =>
    models.Record(
      id: id,
      key: _recordKey,
      value: '',
      label: 'SMTP password',
      type: 'text',
      format: 'hidden',
      user: _user,
      workspace: _workspace,
      sealed: true,
      sealedValue: payload.sealedValue,
      sealedVersion: version,
      keyEpoch: payload.keyEpoch,
      keyWrap: payload.keyWrap,
    );

/// Adds a device through the codes a person carries both ways.
Future<KeysStore> _addDevice(
  _FakeServer server,
  KeysStore trusted, {
  _DeviceStorage? storage,
}) async {
  final added = _device(server, storage: storage);
  await added.load();
  expect(added.status, SealingStatus.needsThisDevice);
  await added.prepareThisDevice();
  expect(await trusted.addDevice(added.deviceInvite!), isTrue);
  await added.load();
  expect(added.status, SealingStatus.needsConfirmation);
  expect(await added.confirmThisDevice(trusted.deviceConfirmation!), isTrue);
  expect(added.status, SealingStatus.ready);
  return added;
}

/// A list an attacker controls: their own device first, then whatever follows.
class _AttackerChain {
  final SealingKeyPair signing = Sealing.generateKeyPair();
  final SealingKeyPair hpke = Sealing.generateKeyPair();
  final List<DeviceChainEntry> entries = [];

  _AttackerChain() {
    entries.add(
      DeviceChainEntry.sign(
        user: _user,
        seq: 1,
        action: DeviceChainEntry.actionAdd,
        kind: DeviceChainEntry.kindDevice,
        label: 'Attacker',
        hpkePublicKey: hpke.publicKey,
        signingPublicKey: signing.publicKey,
        targetSeq: 0,
        previousHash: Uint8List(0),
        signerSeq: 1,
        signer: signing,
      ),
    );
  }

  void add(Uint8List hpkeKey, Uint8List signingKey) {
    entries.add(
      DeviceChainEntry.sign(
        user: _user,
        seq: entries.length + 1,
        action: DeviceChainEntry.actionAdd,
        kind: DeviceChainEntry.kindDevice,
        label: 'Victim',
        hpkePublicKey: hpkeKey,
        signingPublicKey: signingKey,
        targetSeq: 0,
        previousHash: entries.last.hash,
        signerSeq: 1,
        signer: signing,
      ),
    );
  }

  List<Map<String, dynamic>> toJson() => [
    for (final e in entries) {...e.toJson(), 'user': _user},
  ];
}

(Uint8List, Uint8List) _publicKeysOf(_FakeServer server, int seq) {
  final entry = DeviceChainEntry.fromJson(
    server.devices.firstWhere((d) => d['seq'] == seq),
  );
  return (entry.hpkePublicKey, entry.signingPublicKey);
}

/// A key handed over and signed by [signer], not by anyone honest.
Map<String, dynamic> _forgedWrap({
  required Uint8List recipient,
  required int deviceSeq,
  required Uint8List key,
  required int epoch,
  required SealingKeyPair signer,
  required int signerSeq,
  required int chainSeq,
}) {
  final wrap = SealedFormats.wrapWorkspaceKey(
    recipientHpkeKey: recipient,
    key: key,
    workspace: _workspace,
    epoch: epoch,
  );
  return {
    'workspace': _workspace,
    'epoch': epoch,
    'deviceSeq': deviceSeq,
    'wrap': wrap,
    'signerSeq': signerSeq,
    'chainSeq': chainSeq,
    'signature': SealedFormats.encode(
      Sealing.sign(
        signer,
        SealedFormats.wrapSignaturePayload(
          workspace: _workspace,
          epoch: epoch,
          recipientHpkeKey: recipient,
          wrap: wrap,
          chainSeq: chainSeq,
        ),
      ),
    ),
  };
}

SealingKeyPair _signingKeyOf(_DeviceStorage storage) {
  final raw = storage.values.entries
      .firstWhere((e) => e.key.startsWith('sealed_device_'))
      .value;
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return SealingKeyPair(
    privateKey: SealedFormats.decode(json['signingPrivate'] as String),
    publicKey: SealedFormats.decode(json['signingPublic'] as String),
  );
}

void main() {
  group('setting up', () {
    test(
      'nothing reaches the server until the recovery key is confirmed',
      () async {
        final server = _FakeServer();
        final keys = _device(server);
        await keys.load();
        expect(keys.status, SealingStatus.notSetUp);

        keys.beginSetup();
        expect(await keys.finishRecovery(workspace: _workspace), isFalse);
        keys.recoveryConfirm.text = 'WRONG-WRONG';
        expect(await keys.finishRecovery(workspace: _workspace), isFalse);
        expect(server.devices, isEmpty);

        keys.cancelRecovery();
        expect(keys.recoveryCode, isNull);
      },
    );

    test('this device can then encrypt in the workspace', () async {
      final (keys, _) = await _setUp(_FakeServer());
      expect(keys.canSeal(_workspace), isTrue);
    });

    test('a server without it offers nothing', () async {
      final server = _FakeServer()..supportsSealing = false;
      final keys = _device(server);
      await keys.load();
      expect(keys.status, SealingStatus.unavailable);
      expect(keys.isAvailable, isFalse);
    });

    test(
      'a failed step can be retried without losing the device key',
      () async {
        final server = _FakeServer()..failEpochs = true;
        final storage = _DeviceStorage();
        final keys = _device(server, storage: storage);
        await keys.load();
        keys.beginSetup();
        _typeBack(keys);
        expect(await keys.finishRecovery(workspace: _workspace), isFalse);
        final before = _signingKeyOf(storage);

        server.failEpochs = false;
        expect(await keys.finishRecovery(workspace: _workspace), isTrue);

        expect(_signingKeyOf(storage).privateKey, before.privateKey);
        expect(keys.status, SealingStatus.ready);
        expect(keys.canSeal(_workspace), isTrue);
      },
    );

    test(
      'a retry with a newer recovery code puts that code on the list',
      () async {
        final server = _FakeServer()..failEpochs = true;
        final keys = _device(server);
        await keys.load();
        keys.beginSetup();
        _typeBack(keys);
        await keys.finishRecovery(workspace: _workspace);
        server.failEpochs = false;
        keys.cancelRecovery();

        keys.beginSetup();
        final newCode = keys.recoveryCode!;
        _typeBack(keys);
        expect(await keys.finishRecovery(workspace: _workspace), isTrue);
        final record = _sealedRecord(keys);

        final fresh = _device(server);
        await fresh.load();
        fresh.recoveryInput.text = newCode;
        expect(await fresh.restoreWithRecoveryKey(), isTrue);
        expect(fresh.openRecord(record), _canary);
      },
    );
  });

  group('the server never sees', () {
    test('a value, a key or the recovery code', () async {
      final server = _FakeServer();
      final storage = _DeviceStorage();
      final (keys, code) = await _setUp(server, storage: storage);
      final record = _sealedRecord(keys);

      final sent =
          '${server.received}'
          '${record.sealedValue}${record.keyWrap}${jsonEncode(server.state())}';
      expect(sent, isNot(contains(_canary)));
      expect(sent, isNot(contains(code)));
      expect(sent, isNot(contains(code.replaceAll('-', ''))));

      final privateHalves =
          jsonDecode(
                storage.values.entries
                    .firstWhere((e) => e.key.startsWith('sealed_device_'))
                    .value,
              )
              as Map<String, dynamic>;
      expect(sent, isNot(contains(privateHalves['hpkePrivate'])));
      expect(sent, isNot(contains(privateHalves['signingPrivate'])));
    });
  });

  group('reading', () {
    test('a value round-trips on the device that wrote it', () async {
      final (keys, _) = await _setUp(_FakeServer());
      expect(keys.openRecord(_sealedRecord(keys)), _canary);
    });

    test('a value moved to another record does not open', () async {
      final (keys, _) = await _setUp(_FakeServer());
      final payload = keys.sealValue(
        workspace: _workspace,
        record: 'record000000001',
        recordKey: _recordKey,
        version: 1,
        value: _canary,
      );
      expect(
        keys.openRecord(_recordFrom('record000000002', 1, payload)),
        isNull,
      );
    });

    test('a value replayed as another version does not open', () async {
      final (keys, _) = await _setUp(_FakeServer());
      final payload = keys.sealValue(
        workspace: _workspace,
        record: 'record000000001',
        recordKey: _recordKey,
        version: 1,
        value: _canary,
      );
      expect(
        keys.openRecord(_recordFrom('record000000001', 2, payload)),
        isNull,
      );
    });

    test('a value shown under another record key does not open', () async {
      final (keys, _) = await _setUp(_FakeServer());
      final payload = keys.sealValue(
        workspace: _workspace,
        record: 'record000000001',
        recordKey: 'something_else',
        version: 1,
        value: _canary,
      );
      expect(
        keys.openRecord(_recordFrom('record000000001', 1, payload)),
        isNull,
      );
    });

    test('an older version than this device has seen is refused', () async {
      final (keys, _) = await _setUp(_FakeServer());
      final older = _sealedRecord(keys, version: 1, value: 'old');
      final newer = _sealedRecord(keys, version: 2, value: 'new');
      expect(keys.openRecord(newer), 'new');
      expect(keys.openRecord(older), isNull);
    });

    test('what this device just wrote pins the version', () async {
      final (keys, _) = await _setUp(_FakeServer());
      final older = _sealedRecord(keys, version: 1, value: 'old');
      keys.noteWritten(older.id, version: 2, epoch: older.keyEpoch);
      expect(keys.openRecord(older), isNull);
    });

    test('a malformed row does not take down the rest', () async {
      final (keys, _) = await _setUp(_FakeServer());
      final good = _sealedRecord(keys);
      for (final junk in ['', 'AQ', 'AQID', '!!!not base64!!!', 'AA==']) {
        final bad = models.Record(
          id: 'record000000002',
          key: _recordKey,
          value: '',
          label: 'l',
          type: 'text',
          format: 'default',
          user: _user,
          workspace: _workspace,
          sealed: true,
          sealedValue: junk,
          sealedVersion: 1,
          keyEpoch: good.keyEpoch,
          keyWrap: junk,
        );
        expect(keys.openRecord(bad), isNull, reason: 'junk: $junk');
      }
      expect(keys.openRecord(good), _canary);
    });

    test('a sealed row never carries a value from the server', () {
      final record = models.Record.fromJson({
        'id': 'r',
        'key': 'k',
        'value': 'planted by the server',
        'label': 'l',
        'type': 'text',
        'format': 'default',
        'user': _user,
        'workspace': _workspace,
        'sealed': true,
      });
      expect(record.value, '');
      expect(record.isLocked, isTrue);
    });

    test('a device without the key leaves the record locked', () async {
      final server = _FakeServer();
      final (keys, _) = await _setUp(server);
      final record = _sealedRecord(keys);
      final outsider = _device(server);
      await outsider.load();
      expect(outsider.openRecord(record), isNull);
      expect(outsider.canSeal(_workspace), isFalse);
    });
  });

  group('a plain copy of something known to be encrypted', () {
    test('is flagged once read, and until the owner says so', () async {
      final (keys, _) = await _setUp(_FakeServer());
      final record = _sealedRecord(keys);
      expect(keys.knewAsSealed(record.id), isFalse);
      keys.openRecord(record);
      expect(keys.knewAsSealed(record.id), isTrue);
      await keys.acceptUnsealed(record.id);
      expect(keys.knewAsSealed(record.id), isFalse);
    });

    test('is flagged from what this device wrote, too', () async {
      final (keys, _) = await _setUp(_FakeServer());
      keys.noteWritten('record000000009', version: 1, epoch: 1);
      expect(keys.knewAsSealed('record000000009'), isTrue);
    });

    test('accepting it does not let an old sealed copy back in', () async {
      final (keys, _) = await _setUp(_FakeServer());
      final old = _sealedRecord(keys, version: 3, value: 'old');
      keys.openRecord(old);
      await keys.acceptUnsealed(old.id);

      final resealed = _sealedRecord(keys, version: 2, value: 'lower');
      expect(keys.openRecord(resealed), isNull);
    });

    test('a server cannot switch the check off by denying support', () async {
      final server = _FakeServer();
      final storage = _DeviceStorage();
      final (keys, _) = await _setUp(server, storage: storage);
      keys.openRecord(_sealedRecord(keys));
      await Future<void>.delayed(Duration.zero);

      server.supportsSealing = false;
      final restarted = _device(server, storage: storage);
      await restarted.load();

      expect(restarted.status, SealingStatus.untrusted);
      expect(restarted.knewAsSealed('record000000001'), isTrue);
    });
  });

  group('another device', () {
    test('reads what the first wrote, and writes what it can read', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);

      expect(second.openRecord(_sealedRecord(first)), _canary);
      expect(
        first.openRecord(_sealedRecord(second, id: 'record000000002')),
        _canary,
      );
    });

    test('trusts nothing until the other device confirms it', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final record = _sealedRecord(first);
      final second = _device(server);
      await second.load();
      await second.prepareThisDevice();
      expect(await first.addDevice(second.deviceInvite!), isTrue);

      await second.load();
      expect(second.status, SealingStatus.needsConfirmation);
      expect(second.canSeal(_workspace), isFalse);
      expect(second.openRecord(record), isNull);
    });

    test('refuses a confirmation that does not match its list', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = _device(server);
      await second.load();
      await second.prepareThisDevice();
      await first.addDevice(second.deviceInvite!);
      await second.load();

      final wrong = DeviceConfirmation(
        first.chain.headSeq,
        Uint8List(16),
      ).encodeToString();
      expect(await second.confirmThisDevice(wrong), isFalse);
      expect(second.status, SealingStatus.needsConfirmation);
      expect(await second.confirmThisDevice('garbage'), isFalse);
    });

    test('a pasted code that is not whole is refused', () async {
      final (first, _) = await _setUp(_FakeServer());
      expect(await first.addDevice('rvkdev1.nope'), isFalse);
      expect(first.errorMessage, isNotNull);
    });

    test('a stale device re-reads the list before signing onto it', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);
      final third = await _addDevice(server, second);

      // First hasn't heard about the third device, and still signs correctly.
      expect(await first.removeDevice(third.thisDeviceSeq!), isTrue);
      expect(first.chainBroken, isFalse);
    });

    test('a stale device takes up a key another device started', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);

      expect(await first.ensureWorkspaceKey(_otherWorkspace), isTrue);
      expect(second.canSeal(_otherWorkspace), isFalse);

      expect(await second.ensureWorkspaceKey(_otherWorkspace), isTrue);
      expect(second.errorMessage, isNull);
      expect(server.otherEpochs.length, 1);
    });

    test('a key started elsewhere mid-way is taken up, not refused', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);
      expect(await first.ensureWorkspaceKey(_otherWorkspace), isTrue);

      // The read before the write still misses it, as if the other device
      // started it in between.
      var hidden = false;
      server.tamperState = (state) {
        if (hidden) return state;
        hidden = true;
        return {
          ...state,
          'workspaces': [
            for (final w in state['workspaces'] as List<dynamic>)
              if ((w as Map<String, dynamic>)['workspace'] != _otherWorkspace)
                w,
          ],
        };
      };

      expect(await second.ensureWorkspaceKey(_otherWorkspace), isTrue);
      expect(server.otherEpochs.length, 1);
    });

    test('a key replaced elsewhere mid-way does not fail the load', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);
      final third = await _addDevice(server, first);
      expect(await first.removeDevice(third.thisDeviceSeq!), isTrue);
      expect(server.epochs.length, 2);

      // Second reads the key as still due, after first already replaced it.
      var shown = false;
      server.tamperState = (state) {
        if (shown) return state;
        shown = true;
        final row =
            (state['workspaces'] as List<dynamic>).first
                as Map<String, dynamic>;
        return {
          ...state,
          'workspaces': [
            {
              ...row,
              'epochs': [
                {
                  ...(row['epochs'] as List<dynamic>).first,
                  'rotationDue': true,
                },
              ],
              'wraps': [
                for (final w in row['wraps'] as List<dynamic>)
                  if ((w as Map<String, dynamic>)['epoch'] == 1) w,
              ],
            },
          ],
        };
      };

      await second.load();
      expect(second.errorMessage, isNull);
      expect(second.status, SealingStatus.ready);
      expect(second.canSeal(_workspace), isTrue);
      expect(server.epochs.length, 2);
    });

    test('a device that was away reads the server again', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);
      expect(await first.ensureWorkspaceKey(_otherWorkspace), isTrue);

      await second.ensureLoaded();
      expect(second.canSeal(_otherWorkspace), isFalse);
      second.markStale();
      await second.ensureLoaded();
      expect(second.canSeal(_otherWorkspace), isTrue);
    });
  });

  group('removing a device', () {
    test('replaces the key, and old values still open', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);
      final before = _sealedRecord(first);
      final removed = second.thisDeviceSeq!;

      expect(await first.removeDevice(removed), isTrue);

      expect(server.epochs.length, 2);
      expect(server.epochs.last['rotationDue'], isFalse);
      expect(first.canSeal(_workspace), isTrue);
      expect(first.openRecord(before), _canary);
    });

    test('it cannot read what is written afterwards', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);
      final removed = second.thisDeviceSeq!;
      await first.removeDevice(removed);

      final after = _sealedRecord(first, id: 'record000000002');
      expect(after.keyEpoch, 2);
      expect(server.wraps.where((w) => w['deviceSeq'] == removed), isEmpty);

      // Still holding its old key, as a stolen device would.
      expect(second.openRecord(after), isNull);

      await second.load();
      expect(second.status, SealingStatus.needsThisDevice);
      expect(second.canSeal(_workspace), isFalse);
    });

    test('this device cannot remove itself', () async {
      final (first, _) = await _setUp(_FakeServer());
      expect(await first.removeDevice(first.thisDeviceSeq!), isFalse);
    });

    test('says so if the key could not be replaced', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);

      server.failEpochs = true;
      expect(await first.removeDevice(second.thisDeviceSeq!), isFalse);
      expect(first.errorMessage, isNotNull);
      expect(first.canSeal(_workspace), isFalse);
    });

    test('takes off whatever it added, but not this device', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);
      final third = await _addDevice(server, second);

      await first.load();
      expect(first.removalsFor(second.thisDeviceSeq!).map((e) => e.seq), [
        second.thisDeviceSeq,
        third.thisDeviceSeq,
      ]);
      expect(await first.removeDevice(second.thisDeviceSeq!), isTrue);
      expect(first.chain.isLive(third.thisDeviceSeq!), isFalse);

      // The device that first added this one can be removed by it.
      final fourth = await _addDevice(server, first);
      expect(await fourth.removeDevice(first.thisDeviceSeq!), isTrue);
      expect(fourth.status, SealingStatus.ready);
      expect(fourth.canSeal(_workspace), isTrue);
      expect(fourth.needsNewRecoveryKey, isTrue);
    });
  });

  group('the recovery key', () {
    test('brings back everything on a brand new device', () async {
      final server = _FakeServer();
      final (first, code) = await _setUp(server);
      final record = _sealedRecord(first);

      final fresh = _device(server);
      await fresh.load();
      fresh.recoveryInput.text = code;
      expect(await fresh.restoreWithRecoveryKey(), isTrue);
      expect(fresh.status, SealingStatus.ready);
      expect(fresh.openRecord(record), _canary);
      expect(fresh.canSeal(_workspace), isTrue);
    });

    test('reads through a rotation', () async {
      final server = _FakeServer();
      final (first, code) = await _setUp(server);
      final record = _sealedRecord(first);
      final second = await _addDevice(server, first);
      await first.removeDevice(second.thisDeviceSeq!);
      final afterwards = _sealedRecord(first, id: 'record000000002');

      final fresh = _device(server);
      await fresh.load();
      fresh.recoveryInput.text = code;
      expect(await fresh.restoreWithRecoveryKey(), isTrue);
      expect(fresh.openRecord(record), _canary);
      expect(fresh.openRecord(afterwards), _canary);
    });

    test('from another account is refused', () async {
      final server = _FakeServer();
      await _setUp(server);
      final fresh = _device(server);
      await fresh.load();
      fresh.recoveryInput.text = RecoveryCode.encode(Sealing.randomBytes(32));
      expect(await fresh.restoreWithRecoveryKey(), isFalse);
      expect(fresh.status, SealingStatus.needsThisDevice);
    });

    test('with a typo is refused', () async {
      final server = _FakeServer();
      await _setUp(server);
      final fresh = _device(server);
      await fresh.load();
      fresh.recoveryInput.text = 'AAAAA-BBBBB';
      expect(await fresh.restoreWithRecoveryKey(), isFalse);
    });

    test('once replaced, the old one no longer works', () async {
      final server = _FakeServer();
      final (first, oldCode) = await _setUp(server);
      first.beginRecoveryReplacement();
      final newCode = first.recoveryCode!;
      _typeBack(first);
      expect(await first.finishRecovery(workspace: _workspace), isTrue);
      expect(server.epochs.length, 2);

      final record = _sealedRecord(first);
      final stale = _device(server);
      await stale.load();
      stale.recoveryInput.text = oldCode;
      expect(await stale.restoreWithRecoveryKey(), isFalse);

      stale.recoveryInput.text = newCode;
      expect(await stale.restoreWithRecoveryKey(), isTrue);
      expect(stale.openRecord(record), _canary);
    });
  });

  group('a dishonest server', () {
    test('cannot add a device of its own', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final attacker = Sealing.generateKeyPair();
      final head = VerifiedChain.verify(_user, [
        for (final d in server.devices) DeviceChainEntry.fromJson(d),
      ]);
      server.devices.add({
        ...DeviceChainEntry.sign(
          user: _user,
          seq: head.nextSeq,
          action: DeviceChainEntry.actionAdd,
          kind: DeviceChainEntry.kindDevice,
          label: 'Totally your phone',
          hpkePublicKey: attacker.publicKey,
          signingPublicKey: attacker.publicKey,
          targetSeq: 0,
          previousHash: head.headHash,
          signerSeq: 1,
          signer: attacker,
        ).toJson(),
        'user': _user,
      });

      await first.load();
      expect(first.chainBroken, isTrue);
      expect(first.chain.live.map((e) => e.seq), isNot(contains(head.nextSeq)));
      expect(first.canSeal(_workspace), isFalse);
      expect(() => _sealedRecord(first), throwsA(isA<SealingException>()));
    });

    test('cannot hand a device a key of its own choosing', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final seq = first.thisDeviceSeq!;
      final (hpke, _) = _publicKeysOf(server, seq);
      server.epochs.add({'epoch': 2, 'priorWrap': '', 'rotationDue': false});
      server.wraps.add(
        _forgedWrap(
          recipient: hpke,
          deviceSeq: seq,
          key: Sealing.newSymmetricKey(),
          epoch: 2,
          signer: Sealing.generateKeyPair(),
          signerSeq: seq,
          chainSeq: 2,
        ),
      );

      await first.load();
      expect(first.canSeal(_workspace), isFalse);
      expect(() => _sealedRecord(first), throwsA(isA<SealingException>()));
    });

    // Reproduced in review: the client adopted the list served back after its
    // own upload, pinned the attacker's root, and wrapped the key to them.
    test('cannot put its own device first during setup', () async {
      final server = _FakeServer();
      final attacker = _AttackerChain();
      final keys = _device(server);
      await keys.load();

      server.tamperState = (state) {
        if (server.devices.isEmpty) return state;
        if (attacker.entries.length == 1) {
          final (hpke, signing) = _publicKeysOf(server, 1);
          attacker.add(hpke, signing);
        }
        return {...state, 'devices': attacker.toJson()};
      };

      keys.beginSetup();
      _typeBack(keys);
      expect(await keys.finishRecovery(workspace: _workspace), isFalse);
      expect(keys.status, SealingStatus.untrusted);
      expect(keys.canSeal(_workspace), isFalse);
      expect(server.wraps, isEmpty, reason: 'no key was handed to anyone');
    });

    // Reproduced in review: only the start of the list was pinned, so a stolen
    // device could fork it from before its removal, where it is still on it.
    test('and a stolen device cannot undo its removal by forking', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final stolenStorage = _DeviceStorage();
      final stolen = await _addDevice(server, first, storage: stolenStorage);
      final stolenSeq = stolen.thisDeviceSeq!;
      final stolenKey = _signingKeyOf(stolenStorage);

      expect(await first.removeDevice(stolenSeq), isTrue);
      final honest = server.devices.toList();
      final atRemoval = honest.indexWhere((d) => d['action'] == 'remove');

      final attacker = Sealing.generateKeyPair();
      final prefix = [
        for (final d in honest.sublist(0, atRemoval))
          DeviceChainEntry.fromJson(d),
      ];
      final fork = DeviceChainEntry.sign(
        user: _user,
        seq: prefix.last.seq + 1,
        action: DeviceChainEntry.actionAdd,
        kind: DeviceChainEntry.kindDevice,
        label: 'Attacker',
        hpkePublicKey: attacker.publicKey,
        signingPublicKey: attacker.publicKey,
        targetSeq: 0,
        previousHash: prefix.last.hash,
        signerSeq: stolenSeq,
        signer: stolenKey,
      );
      server.devices = [
        ...honest.sublist(0, atRemoval),
        {...fork.toJson(), 'user': _user},
      ];

      await first.load();
      expect(first.status, SealingStatus.untrusted);
      expect(first.canSeal(_workspace), isFalse);
      expect(
        first.chain.isLive(stolenSeq),
        isTrue,
        reason: 'the fork looks valid on its own; only the pin catches it',
      );
    });

    test('cannot roll back the device list', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      await _addDevice(server, first);
      await first.load();
      server.devices.removeLast();
      await first.load();
      expect(first.status, SealingStatus.untrusted);
      expect(first.canSeal(_workspace), isFalse);
    });

    test('cannot wipe the list and have a device start again', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      server.devices = [];
      await first.load();
      expect(first.status, SealingStatus.untrusted);
    });

    test('cannot swap in a whole new device list', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      server.devices = _AttackerChain().toJson();
      await first.load();
      expect(first.status, SealingStatus.untrusted);
      expect(first.canSeal(_workspace), isFalse);
    });

    test('cannot hide the newest key from a device that has seen it', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);
      await first.removeDevice(second.thisDeviceSeq!);
      expect(first.canSeal(_workspace), isTrue);

      server.epochs.removeLast();
      server.wraps.removeWhere((w) => w['epoch'] == 2);
      await first.load();
      expect(first.canSeal(_workspace), isFalse);
    });

    // Reproduced in review: rotation depended on a flag the server could leave
    // unset, so the client kept writing where the removed device could read.
    test('cannot keep a device on the old key by hiding the flag', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);
      final removed = second.thisDeviceSeq!;

      server.tamperState = (state) {
        for (final w in state['workspaces'] as List<dynamic>) {
          for (final e in (w as Map)['epochs'] as List<dynamic>) {
            (e as Map)['rotationDue'] = false;
          }
        }
        return state;
      };

      expect(await first.removeDevice(removed), isTrue);
      expect(server.epochs.length, 2, reason: 'rotated without being told');
      final after = _sealedRecord(first, id: 'record000000002');
      expect(after.keyEpoch, 2);
      expect(second.openRecord(after), isNull);
    });

    // Reproduced in review: a device with no history pinned a list built around
    // its own public keys, and wrote under a key the server chose.
    test('cannot build a list around a new device and trap it', () async {
      final server = _FakeServer();
      await _setUp(server);
      final victim = _device(server);
      await victim.load();
      await victim.prepareThisDevice();
      final invite = DeviceInvite.tryParse(victim.deviceInvite!)!;

      final attacker = _AttackerChain()
        ..add(invite.hpkePublicKey, invite.signingPublicKey);
      server.tamperState = (state) => {
        'devices': attacker.toJson(),
        'workspaces': [
          {
            'workspace': _workspace,
            'epochs': [
              {'epoch': 1, 'priorWrap': '', 'rotationDue': false},
            ],
            'wraps': [
              _forgedWrap(
                recipient: invite.hpkePublicKey,
                deviceSeq: 2,
                key: Sealing.newSymmetricKey(),
                epoch: 1,
                signer: attacker.signing,
                signerSeq: 1,
                chainSeq: 2,
              ),
            ],
          },
        ],
      };

      await victim.load();
      expect(victim.status, SealingStatus.needsConfirmation);
      expect(victim.canSeal(_workspace), isFalse);
      expect(
        await victim.confirmThisDevice(
          DeviceConfirmation(2, Uint8List(16)).encodeToString(),
        ),
        isFalse,
      );
      expect(victim.canSeal(_workspace), isFalse);
    });

    test(
      'cannot fool the recovery key with a copy of its public keys',
      () async {
        final server = _FakeServer();
        final (_, code) = await _setUp(server);
        final secret = RecoveryCode.decode(code)!;
        final attacker = _AttackerChain();
        attacker.entries.add(
          DeviceChainEntry.sign(
            user: _user,
            seq: 2,
            action: DeviceChainEntry.actionAdd,
            kind: DeviceChainEntry.kindRecovery,
            label: 'Recovery key',
            hpkePublicKey: RecoveryCode.hpkeKey(secret).publicKey,
            signingPublicKey: RecoveryCode.signingKey(secret).publicKey,
            targetSeq: 0,
            previousHash: attacker.entries.last.hash,
            signerSeq: 1,
            signer: attacker.signing,
            anchorSignature: Sealing.sign(
              attacker.signing,
              SealedFormats.recoveryAnchorPayload(
                _user,
                attacker.entries.first.hash,
              ),
            ),
          ),
        );
        server.devices = attacker.toJson();

        final fresh = _device(server);
        await fresh.load();
        fresh.recoveryInput.text = code;
        expect(await fresh.restoreWithRecoveryKey(), isFalse);
        expect(fresh.status, isNot(SealingStatus.ready));
      },
    );

    // Reproduced in review: a removed device's key, re-signed by the recovery
    // key during restore, reached a new device as if it were trustworthy.
    test('cannot launder a removed device\'s key through recovery', () async {
      final server = _FakeServer();
      final (first, code) = await _setUp(server);
      final stolenStorage = _DeviceStorage();
      final stolen = await _addDevice(server, first, storage: stolenStorage);
      final stolenSeq = stolen.thisDeviceSeq!;
      final stolenKey = _signingKeyOf(stolenStorage);
      await first.removeDevice(stolenSeq);

      final recoverySeq = first.chain.liveRecovery!.seq;
      final (recoveryHpke, _) = _publicKeysOf(server, recoverySeq);
      server.epochs.add({'epoch': 3, 'priorWrap': '', 'rotationDue': false});
      server.wraps.add(
        _forgedWrap(
          recipient: recoveryHpke,
          deviceSeq: recoverySeq,
          key: Sealing.newSymmetricKey(),
          epoch: 3,
          signer: stolenKey,
          signerSeq: stolenSeq,
          chainSeq: first.chain.headSeq,
        ),
      );

      final fresh = _device(server);
      await fresh.load();
      fresh.recoveryInput.text = code;
      await fresh.restoreWithRecoveryKey();

      for (final w in server.wraps.where((w) => w['epoch'] == 3)) {
        expect(w['signerSeq'], stolenSeq, reason: 'nobody re-signed it');
      }
      if (fresh.canSeal(_workspace)) {
        expect(
          _sealedRecord(fresh, id: 'record000000005').keyEpoch,
          isNot(3),
          reason: 'wrote under the key a removed device chose',
        );
      }
    });

    // Reproduced in review: one forged high epoch blocked all writes for good.
    test('a removed device cannot pin an absurd epoch', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final stolenStorage = _DeviceStorage();
      final stolen = await _addDevice(server, first, storage: stolenStorage);
      final stolenSeq = stolen.thisDeviceSeq!;
      final stolenKey = _signingKeyOf(stolenStorage);
      await first.removeDevice(stolenSeq);

      final seq = first.thisDeviceSeq!;
      final (hpke, _) = _publicKeysOf(server, seq);
      final chosen = Sealing.newSymmetricKey();
      final headSeq = first.chain.headSeq;
      server.tamperState = (state) {
        final row = (state['workspaces'] as List<dynamic>).first as Map;
        (row['epochs'] as List<dynamic>).add({
          'epoch': 1000000,
          'priorWrap': '',
          'rotationDue': false,
        });
        (row['wraps'] as List<dynamic>).add(
          _forgedWrap(
            recipient: hpke,
            deviceSeq: seq,
            key: chosen,
            epoch: 1000000,
            signer: stolenKey,
            signerSeq: stolenSeq,
            chainSeq: headSeq,
          ),
        );
        return state;
      };
      await first.load();
      expect(first.canSeal(_workspace), isFalse);

      // A value written under the forged key is not accepted as genuine.
      final forgedKey = Sealing.newSymmetricKey();
      final forged = models.Record(
        id: 'record000000007',
        key: _recordKey,
        value: '',
        label: 'l',
        type: 'text',
        format: 'default',
        user: _user,
        workspace: _workspace,
        sealed: true,
        sealedValue: SealedFormats.sealValue(
          valueKey: forgedKey,
          value: 'forged',
          workspace: _workspace,
          record: 'record000000007',
          recordKey: _recordKey,
          version: 1,
        ),
        sealedVersion: 1,
        keyEpoch: 1000000,
        keyWrap: SealedFormats.wrapValueKey(
          workspaceKey: chosen,
          valueKey: forgedKey,
          workspace: _workspace,
          record: 'record000000007',
          version: 1,
          epoch: 1000000,
        ),
      );
      expect(first.openRecord(forged), isNull);

      // And it recovers as soon as the server stops.
      server.tamperState = null;
      await first.load();
      expect(first.canSeal(_workspace), isTrue);
    });

    test('a record cannot go back to a key it has left', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);
      final underOldKey = _sealedRecord(first, version: 9, value: 'forged');
      expect(underOldKey.keyEpoch, 1);

      await first.removeDevice(second.thisDeviceSeq!);
      final current = _sealedRecord(first, version: 2, value: 'real');
      expect(current.keyEpoch, 2);
      expect(first.openRecord(current), 'real');
      expect(first.openRecord(underOldKey), isNull);
    });
  });

  group('a stolen device', () {
    // Reproduced in review: it added a second recovery key, invisible on the
    // device list, which kept receiving every new key after it was removed.
    test('cannot keep a recovery key of its own after its removal', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final stolenStorage = _DeviceStorage();
      final stolen = await _addDevice(server, first, storage: stolenStorage);
      final stolenSeq = stolen.thisDeviceSeq!;
      final stolenKey = _signingKeyOf(stolenStorage);

      // A second recovery entry alongside the first breaks the list at once.
      final planted = Sealing.generateKeyPair();
      final chain = stolen.chain;
      final second = DeviceChainEntry.sign(
        user: _user,
        seq: chain.nextSeq,
        action: DeviceChainEntry.actionAdd,
        kind: DeviceChainEntry.kindRecovery,
        label: 'Recovery key',
        hpkePublicKey: planted.publicKey,
        signingPublicKey: planted.publicKey,
        targetSeq: 0,
        previousHash: chain.headHash,
        signerSeq: stolenSeq,
        signer: stolenKey,
        anchorSignature: Sealing.sign(
          planted,
          SealedFormats.recoveryAnchorPayload(_user, chain.entries.first.hash),
        ),
      );
      final honest = server.devices.toList();
      server.devices = [
        ...honest,
        {...second.toJson(), 'user': _user},
      ];
      await first.load();
      expect(first.chainBroken, isTrue);
      expect(first.canSeal(_workspace), isFalse);

      // Replacing the recovery key instead: its entries go when it does.
      server.devices = honest;
      stolen.beginRecoveryReplacement();
      _typeBack(stolen);
      expect(await stolen.finishRecovery(workspace: _workspace), isTrue);
      final plantedRecovery = stolen.chain.liveRecovery!.seq;

      expect(await first.removeDevice(stolenSeq), isTrue);
      expect(first.chain.isLive(plantedRecovery), isFalse);
      expect(first.needsNewRecoveryKey, isTrue);
      expect(
        server.wraps.where(
          (w) =>
              w['deviceSeq'] == plantedRecovery &&
              (w['epoch'] as int) >= (server.epochs.last['epoch'] as int),
        ),
        isEmpty,
        reason: 'the new key never reached what it planted',
      );
    });
  });

  group('when this device does not trust the list', () {
    Future<KeysStore> untrusted(_FakeServer server) async {
      final (first, _) = await _setUp(server);
      server.devices = _AttackerChain().toJson();
      await first.load();
      expect(first.status, SealingStatus.untrusted);
      return first;
    }

    test('nothing that signs or hands out keys runs', () async {
      final server = _FakeServer();
      final keys = await untrusted(server);
      final posted = server.devices.length;
      final other = DeviceInvite(
        hpkePublicKey: Sealing.generateKeyPair().publicKey,
        signingPublicKey: Sealing.generateKeyPair().publicKey,
        label: 'x',
      ).encodeToString();

      expect(await keys.addDevice(other), isFalse);
      expect(await keys.removeDevice(1), isFalse);
      keys.beginRecoveryReplacement();
      _typeBack(keys);
      expect(await keys.finishRecovery(workspace: _workspace), isFalse);
      expect(await keys.ensureWorkspaceKey(_workspace), isFalse);
      expect(server.devices.length, posted);
    });

    test('rejoining still needs a device or the recovery key', () async {
      final server = _FakeServer();
      final keys = await untrusted(server);
      await keys.forgetThisDevice();
      expect(keys.status, SealingStatus.needsThisDevice);
      expect(keys.canSeal(_workspace), isFalse);
    });
  });

  group('starting over', () {
    test('needs the phrase, then clears the way to set up again', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);

      first.startOverConfirm.text = 'yes';
      expect(await first.startOver(), isFalse);
      expect(server.devices, isNotEmpty);

      first.startOverConfirm.text = KeysStore.startOverPhrase;
      expect(await first.startOver(), isTrue);
      expect(server.devices, isEmpty);
      expect(first.status, SealingStatus.notSetUp);
    });

    test('another device that knew the old list stops trusting it', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);

      first.startOverConfirm.text = KeysStore.startOverPhrase;
      await first.startOver();
      await first.load();
      first.beginSetup();
      _typeBack(first);
      expect(await first.finishRecovery(workspace: _workspace), isTrue);

      await second.load();
      expect(second.status, SealingStatus.untrusted);

      await second.forgetThisDevice();
      expect(second.status, SealingStatus.needsThisDevice);
    });
  });

  group('signing out', () {
    test('drops the keys from memory', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final record = _sealedRecord(first);

      first.forgetSession();
      expect(first.openRecord(record), isNull);
      expect(first.canSeal(_workspace), isFalse);

      await first.load();
      expect(first.status, SealingStatus.ready);
      expect(first.openRecord(record), _canary);
    });

    test('a load still in flight cannot put them back', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final loading = first.load();
      first.forgetSession();
      await loading;
      expect(first.canSeal(_workspace), isFalse);
      expect(first.status, SealingStatus.unknown);
    });
  });

  group('second-round attacks', () {
    // A stolen device adds a go-between, has it add a recovery key, then removes
    // the go-between. Following only live entries would miss what it planted.
    test('removal reaches what a removed go-between added', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final stolenStorage = _DeviceStorage();
      final stolen = await _addDevice(server, first, storage: stolenStorage);
      final stolenSeq = stolen.thisDeviceSeq!;

      final middleStorage = _DeviceStorage();
      final middle = await _addDevice(server, stolen, storage: middleStorage);
      final middleSeq = middle.thisDeviceSeq!;

      // The thief takes the real recovery key off, adds its own through the
      // go-between, then removes the go-between.
      middle.beginRecoveryReplacement();
      _typeBack(middle);
      expect(await middle.finishRecovery(workspace: _workspace), isTrue);
      final planted = middle.chain.liveRecovery!.seq;
      expect(await stolen.removeDevice(middleSeq), isTrue);
      await first.load();
      expect(
        first.chain.isLive(planted),
        isFalse,
        reason: 'removing the go-between took its recovery key with it',
      );

      // Same again, with the entry surviving because a go-between added it after
      // being signed by a device the owner then removes.
      expect(first.removalsFor(stolenSeq).map((e) => e.seq), [stolenSeq]);
      expect(await first.removeDevice(stolenSeq), isTrue);
      expect(first.chain.live.map((e) => e.seq), [first.thisDeviceSeq]);
    });

    test('the closure follows entries already removed', () {
      final a = Sealing.generateKeyPair();
      final b = Sealing.generateKeyPair();
      final c = Sealing.generateKeyPair();
      final d = Sealing.generateKeyPair();
      DeviceChainEntry add(
        int seq,
        SealingKeyPair key,
        Uint8List prev,
        int signerSeq,
        SealingKeyPair signer,
      ) => DeviceChainEntry.sign(
        user: _user,
        seq: seq,
        action: DeviceChainEntry.actionAdd,
        kind: DeviceChainEntry.kindDevice,
        label: 'd$seq',
        hpkePublicKey: key.publicKey,
        signingPublicKey: key.publicKey,
        targetSeq: 0,
        previousHash: prev,
        signerSeq: signerSeq,
        signer: signer,
      );
      final e1 = add(1, a, Uint8List(0), 1, a);
      final e2 = add(2, b, e1.hash, 1, a); // the stolen device
      final e3 = add(3, c, e2.hash, 2, b); // its go-between
      final e4 = add(4, d, e3.hash, 3, c); // what the go-between planted
      final e5 = DeviceChainEntry.sign(
        user: _user,
        seq: 5,
        action: DeviceChainEntry.actionRemove,
        kind: '',
        label: '',
        hpkePublicKey: Uint8List(0),
        signingPublicKey: Uint8List(0),
        targetSeq: 3,
        previousHash: e4.hash,
        signerSeq: 2,
        signer: b,
      );
      final chain = VerifiedChain.verify(_user, [e1, e2, e3, e4, e5]);
      expect(chain.broken, isFalse);
      expect(chain.removalsFor(2, keep: 1), [2, 4]);
    });

    test('restore takes every other device off the list', () async {
      final server = _FakeServer();
      final (first, code) = await _setUp(server);
      final record = _sealedRecord(first);
      await _addDevice(server, first);

      final fresh = _device(server);
      await fresh.load();
      fresh.recoveryInput.text = code;
      expect(await fresh.restoreWithRecoveryKey(), isTrue);

      final liveDevices = fresh.chain.live
          .where((e) => e.kind == DeviceChainEntry.kindDevice)
          .map((e) => e.seq);
      expect(liveDevices, [fresh.thisDeviceSeq]);
      expect(fresh.openRecord(record), _canary);
      expect(server.epochs.length, 2, reason: 'a new key only it holds');
    });

    // Reproduced in review: restore landed on a fork where a removed thief was
    // live again, and wrote under a key the thief chose.
    test('restore on a fork leaves the thief out of the new key', () async {
      final server = _FakeServer();
      final (first, code) = await _setUp(server);
      final stolenStorage = _DeviceStorage();
      final stolen = await _addDevice(server, first, storage: stolenStorage);
      final stolenSeq = stolen.thisDeviceSeq!;
      final stolenKey = _signingKeyOf(stolenStorage);
      await first.removeDevice(stolenSeq);

      final honest = server.devices.toList();
      final atRemoval = honest.indexWhere((d) => d['action'] == 'remove');
      final prefix = [
        for (final d in honest.sublist(0, atRemoval))
          DeviceChainEntry.fromJson(d),
      ];
      final attacker = Sealing.generateKeyPair();
      final fork = DeviceChainEntry.sign(
        user: _user,
        seq: prefix.last.seq + 1,
        action: DeviceChainEntry.actionAdd,
        kind: DeviceChainEntry.kindDevice,
        label: 'Attacker',
        hpkePublicKey: attacker.publicKey,
        signingPublicKey: attacker.publicKey,
        targetSeq: 0,
        previousHash: prefix.last.hash,
        signerSeq: stolenSeq,
        signer: stolenKey,
      );
      server.devices = [
        ...honest.sublist(0, atRemoval),
        {...fork.toJson(), 'user': _user},
      ];

      final fresh = _device(server);
      await fresh.load();
      fresh.recoveryInput.text = code;
      await fresh.restoreWithRecoveryKey();

      expect(fresh.chain.isLive(stolenSeq), isFalse);
      expect(fresh.chain.isLive(fork.seq), isFalse);
      if (fresh.canSeal(_workspace)) {
        final written = _sealedRecord(fresh, id: 'record000000005');
        final current = server.wraps
            .where((w) => w['epoch'] == written.keyEpoch)
            .map((w) => w['deviceSeq']);
        expect(current, isNot(contains(stolenSeq)));
        expect(current, isNot(contains(fork.seq)));
      }
    });

    // Reproduced in review: the server answered "ok", stored nothing, and the
    // app said the device was gone.
    test('a dropped removal is reported, not believed', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);
      server.dropEntries = true;
      expect(await first.removeDevice(second.thisDeviceSeq!), isFalse);
      expect(first.errorMessage, contains('did not save'));
    });

    test('a dropped recovery replacement is reported, not believed', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      server.dropEntries = true;
      first.beginRecoveryReplacement();
      _typeBack(first);
      expect(await first.finishRecovery(workspace: _workspace), isFalse);
      expect(first.errorMessage, contains('did not save'));
    });

    // Reproduced in review: restore gave a pre-removal key a fresh number, so it
    // looked as if it came after the removal.
    test('a key from before a removal stays marked as such', () async {
      final server = _FakeServer();
      final (first, code) = await _setUp(server);
      final second = await _addDevice(server, first);
      final removed = second.thisDeviceSeq!;
      await first.removeDevice(removed);

      // The server hides the rotation from a device recovering.
      server.epochs.removeLast();
      server.wraps.removeWhere((w) => w['epoch'] == 2);
      final fresh = _device(server);
      await fresh.load();
      fresh.recoveryInput.text = code;
      await fresh.restoreWithRecoveryKey();

      if (fresh.canSeal(_workspace)) {
        final written = _sealedRecord(fresh, id: 'record000000005');
        expect(written.keyEpoch, greaterThan(1));
        expect(second.openRecord(written), isNull);
      }
    });

    // Reproduced in review: a removed device replaced the key of the current
    // epoch, and a forged value opened on a record already pinned.
    test('nobody can swap the key of an epoch already known', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final stolenStorage = _DeviceStorage();
      final stolen = await _addDevice(server, first, storage: stolenStorage);
      final stolenSeq = stolen.thisDeviceSeq!;
      final stolenKey = _signingKeyOf(stolenStorage);
      await first.removeDevice(stolenSeq);
      final genuine = _sealedRecord(first);
      final epoch = genuine.keyEpoch;
      final seq = first.thisDeviceSeq!;
      final (hpke, _) = _publicKeysOf(server, seq);
      final chosen = Sealing.newSymmetricKey();
      final head = first.chain.headSeq;

      server.tamperState = (state) {
        final row = (state['workspaces'] as List<dynamic>).first as Map;
        (row['wraps'] as List<dynamic>)
          ..removeWhere((w) => w['deviceSeq'] == seq && w['epoch'] == epoch)
          ..add(
            _forgedWrap(
              recipient: hpke,
              deviceSeq: seq,
              key: chosen,
              epoch: epoch,
              signer: stolenKey,
              signerSeq: stolenSeq,
              chainSeq: head,
            ),
          );
        return state;
      };
      await first.load();

      final forgedKey = Sealing.newSymmetricKey();
      final forged = models.Record(
        id: genuine.id,
        key: _recordKey,
        value: '',
        label: 'l',
        type: 'text',
        format: 'default',
        user: _user,
        workspace: _workspace,
        sealed: true,
        sealedValue: SealedFormats.sealValue(
          valueKey: forgedKey,
          value: SealedContent(
            value: 'forged',
            label: 'l',
            type: 'text',
            format: 'default',
          ).encode(),
          workspace: _workspace,
          record: genuine.id,
          recordKey: _recordKey,
          version: 2,
        ),
        sealedVersion: 2,
        keyEpoch: epoch,
        keyWrap: SealedFormats.wrapValueKey(
          workspaceKey: chosen,
          valueKey: forgedKey,
          workspace: _workspace,
          record: genuine.id,
          version: 2,
          epoch: epoch,
        ),
      );
      expect(first.openRecord(forged), isNull);

      server.tamperState = null;
      await first.load();
      expect(first.openRecord(genuine), _canary);
    });

    // A live thief plus the server: a huge epoch must lead back to a known key.
    test('a huge epoch that leads nowhere is not pinned', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final stolenStorage = _DeviceStorage();
      final stolen = await _addDevice(server, first, storage: stolenStorage);
      final stolenSeq = stolen.thisDeviceSeq!;
      final stolenKey = _signingKeyOf(stolenStorage);
      await first.load();
      final seq = first.thisDeviceSeq!;
      final (hpke, _) = _publicKeysOf(server, seq);
      final head = first.chain.headSeq;

      server.tamperState = (state) {
        final row = (state['workspaces'] as List<dynamic>).first as Map;
        (row['epochs'] as List<dynamic>).add({
          'epoch': 1000000,
          'priorWrap': '',
          'rotationDue': false,
        });
        (row['wraps'] as List<dynamic>).add(
          _forgedWrap(
            recipient: hpke,
            deviceSeq: seq,
            key: Sealing.newSymmetricKey(),
            epoch: 1000000,
            signer: stolenKey,
            signerSeq: stolenSeq,
            chainSeq: head,
          ),
        );
        return state;
      };
      await first.load();
      expect(first.canSeal(_workspace), isFalse);

      server.tamperState = null;
      await first.load();
      expect(first.canSeal(_workspace), isTrue, reason: 'nothing was pinned');
    });

    test('a garbage public key cannot break rotation', () {
      final good = Sealing.generateKeyPair();
      final e1 = DeviceChainEntry.sign(
        user: _user,
        seq: 1,
        action: DeviceChainEntry.actionAdd,
        kind: DeviceChainEntry.kindDevice,
        label: 'a',
        hpkePublicKey: good.publicKey,
        signingPublicKey: good.publicKey,
        targetSeq: 0,
        previousHash: Uint8List(0),
        signerSeq: 1,
        signer: good,
      );
      final bad = DeviceChainEntry.sign(
        user: _user,
        seq: 2,
        action: DeviceChainEntry.actionAdd,
        kind: DeviceChainEntry.kindDevice,
        label: 'b',
        hpkePublicKey: Uint8List(65),
        signingPublicKey: good.publicKey,
        targetSeq: 0,
        previousHash: e1.hash,
        signerSeq: 1,
        signer: good,
      );
      final chain = VerifiedChain.verify(_user, [e1, bad]);
      expect(chain.broken, isTrue);
      expect(chain.live.map((e) => e.seq), [1]);
    });

    test('a device taken off the list says so', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);
      await second.removeDevice(first.thisDeviceSeq!);
      await first.load();
      expect(first.status, SealingStatus.needsThisDevice);
      expect(first.removedFromList, isTrue);
    });

    test('something new on the list is pointed out', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);
      await second.load();
      expect(second.unreviewedEntries, isEmpty);

      final third = await _addDevice(server, first);
      await second.load();
      expect(second.unreviewedEntries.map((e) => e.seq), [third.thisDeviceSeq]);

      await second.acknowledgeNewEntries();
      expect(second.unreviewedEntries, isEmpty);
      await second.load();
      expect(second.unreviewedEntries, isEmpty);
    });

    // Reproduced in review: forcing a rejoin wiped what the device remembered,
    // after which a server could downgrade or roll back unnoticed.
    test('rejoining keeps what this device knows of its records', () async {
      final server = _FakeServer();
      final storage = _DeviceStorage();
      final (first, _) = await _setUp(server, storage: storage);
      final record = _sealedRecord(first, version: 5);
      first.openRecord(record);
      final before = _signingKeyOf(storage).privateKey;

      server.devices = _AttackerChain().toJson();
      await first.load();
      expect(first.status, SealingStatus.untrusted);
      await first.forgetThisDevice();

      expect(first.knewAsSealed(record.id), isTrue);
      expect(_signingKeyOf(storage).privateKey, before);
      expect(first.status, SealingStatus.needsThisDevice);
    });

    test('starting over does not leave anything behind', () async {
      final server = _FakeServer();
      final storage = _DeviceStorage();
      final (first, _) = await _setUp(server, storage: storage);
      first.openRecord(_sealedRecord(first));
      first.startOverConfirm.text = KeysStore.startOverPhrase;
      expect(await first.startOver(), isTrue);
      expect(
        storage.values.keys.where((k) => k.startsWith('sealed_')),
        isEmpty,
      );
    });

    // Reproduced in review: one bad answer stuck for the rest of the session.
    test('one bad answer about support does not stick', () async {
      final server = _FakeServer();
      final storage = _DeviceStorage();
      await _setUp(server, storage: storage);

      server.supportsSealing = false;
      final restarted = _device(server, storage: storage);
      await restarted.load();
      expect(restarted.status, SealingStatus.untrusted);

      server.supportsSealing = true;
      await restarted.load();
      expect(restarted.status, SealingStatus.ready);
    });

    test('adding a device keeps its code if the refresh after fails', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = _device(server);
      await second.load();
      await second.prepareThisDevice();
      server.failStateAfterDevices = true;
      expect(await first.addDevice(second.deviceInvite!), isFalse);
      // The entry went in, so the code is what lets the new device finish.
      expect(server.devices.length, 3);
      expect(first.deviceConfirmation, isNotNull);
      await second.load();
      expect(await second.confirmThisDevice(first.deviceConfirmation!), isTrue);
    });

    test('the label and format inside the ciphertext win', () async {
      final (keys, _) = await _setUp(_FakeServer());
      final payload = keys.sealValue(
        workspace: _workspace,
        record: 'record000000001',
        recordKey: _recordKey,
        version: 1,
        value: _canary,
        label: 'SMTP password',
        format: 'hidden',
      );
      final swapped = _recordFrom('record000000001', 1, payload);
      final content = keys.openContent(swapped)!;
      expect(content.value, _canary);
      expect(content.label, 'SMTP password');
      expect(content.format, 'hidden');
    });

    test('short hand-over data fails cleanly', () {
      final pair = Sealing.generateKeyPair();
      for (var tail = 0; tail < 16; tail++) {
        expect(
          () => Sealing.hpkeOpen(
            pair,
            Uint8List(0),
            Uint8List.fromList([...pair.publicKey, ...List.filled(tail, 0)]),
          ),
          throwsA(isA<SealingException>()),
        );
      }
    });
  });

  group('third-round attacks', () {
    /// A fork from before the stolen device was removed, as a dishonest server
    /// would serve it to a device recovering.
    Future<(_FakeServer, String, int, SealingKeyPair)> forkedServer() async {
      final server = _FakeServer();
      final (first, code) = await _setUp(server);
      final stolenStorage = _DeviceStorage();
      final stolen = await _addDevice(server, first, storage: stolenStorage);
      final stolenSeq = stolen.thisDeviceSeq!;
      final stolenKey = _signingKeyOf(stolenStorage);
      await first.removeDevice(stolenSeq);

      final honest = server.devices.toList();
      final atRemoval = honest.indexWhere((d) => d['action'] == 'remove');
      server.devices = honest.sublist(0, atRemoval);
      return (server, code, stolenSeq, stolenKey);
    }

    // Reproduced in review: pins were saved before the commit, so a restore the
    // server failed left this device trusting the fork, thief and all.
    test('a failed restore pins nothing', () async {
      final (server, code, stolenSeq, stolenKey) = await forkedServer();
      final storage = _DeviceStorage();
      final fresh = _device(server, storage: storage);
      await fresh.load();

      server.failDevices = true;
      fresh.recoveryInput.text = code;
      expect(await fresh.restoreWithRecoveryKey(), isFalse);
      server.failDevices = false;

      // The thief now adds this device to the fork, using what it just posted.
      await fresh.prepareThisDevice();
      final invite = DeviceInvite.tryParse(fresh.deviceInvite!)!;
      final chain = VerifiedChain.verify(_user, [
        for (final d in server.devices) DeviceChainEntry.fromJson(d),
      ]);
      server.devices.add({
        ...DeviceChainEntry.sign(
          user: _user,
          seq: chain.nextSeq,
          action: DeviceChainEntry.actionAdd,
          kind: DeviceChainEntry.kindDevice,
          label: 'Fresh',
          hpkePublicKey: invite.hpkePublicKey,
          signingPublicKey: invite.signingPublicKey,
          targetSeq: 0,
          previousHash: chain.headHash,
          signerSeq: stolenSeq,
          signer: stolenKey,
        ).toJson(),
        'user': _user,
      });

      final reloaded = _device(server, storage: storage);
      await reloaded.load();
      expect(reloaded.status, SealingStatus.needsConfirmation);
      expect(reloaded.canSeal(_workspace), isFalse);
    });

    test('a dropped restore pins nothing either', () async {
      final (server, code, _, _) = await forkedServer();
      final storage = _DeviceStorage();
      final fresh = _device(server, storage: storage);
      await fresh.load();
      server.dropEntries = true;
      fresh.recoveryInput.text = code;
      expect(await fresh.restoreWithRecoveryKey(), isFalse);
      final pins = storage.values.entries.where(
        (e) => e.key.startsWith('sealed_pins_'),
      );
      for (final saved in pins) {
        expect(jsonDecode(saved.value)['firstHash'], '');
      }
    });

    test(
      'retrying a restore on a list that already names this device works',
      () async {
        final (server, code, stolenSeq, stolenKey) = await forkedServer();
        final fresh = _device(server);
        await fresh.load();
        await fresh.prepareThisDevice();
        final invite = DeviceInvite.tryParse(fresh.deviceInvite!)!;
        final chain = VerifiedChain.verify(_user, [
          for (final d in server.devices) DeviceChainEntry.fromJson(d),
        ]);
        final added = DeviceChainEntry.sign(
          user: _user,
          seq: chain.nextSeq,
          action: DeviceChainEntry.actionAdd,
          kind: DeviceChainEntry.kindDevice,
          label: 'Fresh',
          hpkePublicKey: invite.hpkePublicKey,
          signingPublicKey: invite.signingPublicKey,
          targetSeq: 0,
          previousHash: chain.headHash,
          signerSeq: stolenSeq,
          signer: stolenKey,
        );
        server.devices.add({...added.toJson(), 'user': _user});

        fresh.recoveryInput.text = code;
        expect(
          await fresh.restoreWithRecoveryKey(),
          isTrue,
          reason: fresh.errorMessage,
        );
        expect(fresh.chain.isLive(stolenSeq), isFalse);
        expect(
          fresh.chain.isLive(added.seq),
          isTrue,
          reason: 'this device stays',
        );
      },
    );

    test('a restore works on a list at its cap', () async {
      final server = _FakeServer();
      final (first, code) = await _setUp(server);
      final record = _sealedRecord(first);
      await _addDevice(server, first);

      final fresh = _device(server);
      await fresh.load();
      fresh.recoveryInput.text = code;
      expect(await fresh.restoreWithRecoveryKey(), isTrue);
      final actions = server.devices.map((d) => d['action']).toList();
      expect(actions.sublist(actions.length - 3), ['remove', 'remove', 'add']);
      expect(fresh.openRecord(record), _canary);
    });

    // Reproduced in review: the server accepted an encoding of the same bytes
    // that Dart refuses, and every device then failed to load at all.
    test('an entry it cannot parse breaks the list, not the device', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final record = _sealedRecord(first);
      final poisoned =
          jsonDecode(jsonEncode(server.devices.first)) as Map<String, dynamic>;
      poisoned
        ..['seq'] = 3
        ..['signature'] = '\n';
      server.devices.add(poisoned);

      await first.load();
      expect(first.status, SealingStatus.ready);
      expect(first.chainBroken, isTrue);
      expect(first.canSeal(_workspace), isFalse);
      expect(first.openRecord(record), _canary, reason: 'it can still read');
    });

    // Reproduced in review: adding a phone marked everything as reviewed, so the
    // alert about a device the thief planted vanished.
    test('making a change does not silence an alert', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);
      final planted = await _addDevice(server, second);

      await first.load();
      expect(first.unreviewedEntries.map((e) => e.seq), [
        planted.thisDeviceSeq,
      ]);

      await _addDevice(server, first);
      expect(first.unreviewedEntries.map((e) => e.seq), [
        planted.thisDeviceSeq,
      ]);

      await first.load();
      expect(first.unreviewedEntries.map((e) => e.seq), [
        planted.thisDeviceSeq,
      ]);

      await first.acknowledgeNewEntries();
      await first.load();
      expect(first.unreviewedEntries, isEmpty);
    });

    test('a removal this device did not make is pointed out too', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = await _addDevice(server, first);
      final third = await _addDevice(server, first);
      await first.acknowledgeNewEntries();

      await second.removeDevice(third.thisDeviceSeq!);
      await first.load();
      expect(
        first.unreviewedEntries.map((e) => e.action),
        contains(DeviceChainEntry.actionRemove),
      );
    });

    test('a device on the list gets its code again', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      final second = _device(server);
      await second.load();
      await second.prepareThisDevice();
      expect(await first.addDevice(second.deviceInvite!), isTrue);
      final code = first.deviceConfirmation;

      first.clearDeviceConfirmation();
      expect(await first.addDevice(second.deviceInvite!), isTrue);
      expect(first.deviceConfirmation, isNotNull);
      expect(server.devices.length, 3, reason: 'not added twice');

      await second.load();
      expect(await second.confirmThisDevice(first.deviceConfirmation!), isTrue);
      expect(code, isNotNull);
    });

    test('this device knows which key new values go under', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      expect(first.writableEpoch(_workspace), 1);
      final second = await _addDevice(server, first);
      await first.removeDevice(second.thisDeviceSeq!);
      expect(first.writableEpoch(_workspace), 2);
      expect(first.writableEpoch('another-workspace'), isNull);
    });
  });
  group('a passkey', () {
    PasskeySignIn signIn(
      Uint8List? secret, {
      String credential = 'cred-A',
      String user = _user,
    }) => PasskeySignIn(
      user: user,
      credentialId: credential,
      name: 'Chrome on Mac',
      secret: secret,
      asked: true,
    );

    /// Sets up encryption on a device that signed in with [secret].
    Future<(KeysStore, String)> setUpWith(
      _FakeServer server,
      Uint8List secret,
    ) async {
      final first = _device(server);
      await first.offerPasskeySignIn(signIn(secret));
      await first.load();
      first.beginSetup();
      final code = first.recoveryCode!;
      _typeBack(first);
      expect(await first.finishRecovery(workspace: _workspace), isTrue);
      expect(first.status, SealingStatus.ready);
      return (first, code);
    }

    test(
      'joins the list at setup, and unlocks the next device by itself',
      () async {
        final server = _FakeServer();
        final secret = Sealing.randomBytes(32);
        final (first, _) = await setUpWith(server, secret);
        expect(first.chain.livePasskeys.map((e) => e.credentialId), ['cred-A']);
        expect(first.thisPasskeyCredentialId, 'cred-A');
        final record = _sealedRecord(first);

        final phone = _device(server);
        await phone.offerPasskeySignIn(signIn(secret));
        await phone.load();
        expect(phone.status, SealingStatus.ready);
        expect(phone.openRecord(record), _canary);
        expect(phone.canSeal(_workspace), isTrue);

        // Nobody was evicted.
        await first.load();
        expect(first.status, SealingStatus.ready);
        expect(first.openRecord(record), _canary);
        expect(first.chain.live, hasLength(4));

        // The secret and the keys it derives never left either device.
        final sent = server.received.toString();
        expect(sent, isNot(contains(SealedFormats.encode(secret))));
        expect(
          sent,
          isNot(
            contains(
              SealedFormats.encode(PasskeyKeys.hpkeKey(secret).privateKey),
            ),
          ),
        );

        first.forgetSession();
        expect(first.passkeySignIn, isNull);
      },
    );

    test(
      'is enrolled by a trusted device the first time it signs in there',
      () async {
        final server = _FakeServer();
        final (first, _) = await _setUp(server);
        expect(first.chain.livePasskeys, isEmpty);
        final record = _sealedRecord(first);

        final secret = Sealing.randomBytes(32);
        await first.offerPasskeySignIn(signIn(secret));
        expect(first.chain.livePasskeys.single.label, 'Chrome on Mac');

        final phone = _device(server);
        await phone.offerPasskeySignIn(signIn(secret));
        await phone.load();
        expect(phone.status, SealingStatus.ready);
        expect(phone.openRecord(record), _canary);
      },
    );

    test('confirms a device the list already names', () async {
      final server = _FakeServer();
      final secret = Sealing.randomBytes(32);
      final (first, _) = await setUpWith(server, secret);
      final phone = _device(server);
      await phone.load();
      await phone.prepareThisDevice();
      expect(await first.addDevice(phone.deviceInvite!), isTrue);
      await phone.load();
      expect(phone.status, SealingStatus.needsConfirmation);

      await phone.offerPasskeySignIn(signIn(secret));
      expect(phone.status, SealingStatus.ready);
      expect(phone.openRecord(_sealedRecord(first)), _canary);
    });

    test('a different passkey gets nothing', () async {
      final server = _FakeServer();
      final (first, _) = await setUpWith(server, Sealing.randomBytes(32));
      final record = _sealedRecord(first);
      final phone = _device(server);
      await phone.offerPasskeySignIn(
        signIn(Sealing.randomBytes(32), credential: 'cred-B'),
      );
      await phone.load();
      expect(phone.status, SealingStatus.needsThisDevice);
      expect(phone.openRecord(record), isNull);
      expect(server.devices, hasLength(3));
    });

    test('a secret from another account is ignored', () async {
      final server = _FakeServer();
      final secret = Sealing.randomBytes(32);
      final (first, _) = await setUpWith(server, secret);
      final phone = _device(server);
      await phone.offerPasskeySignIn(signIn(secret, user: 'someone0000else'));
      await phone.load();
      expect(phone.status, SealingStatus.needsThisDevice);
      await first.offerPasskeySignIn(
        signIn(
          Sealing.randomBytes(32),
          credential: 'cred-X',
          user: 'someone0000else',
        ),
      );
      expect(first.chain.livePasskeys.map((e) => e.credentialId), ['cred-A']);
    });

    test('one without a secret changes nothing', () async {
      final server = _FakeServer();
      final (first, _) = await _setUp(server);
      await first.offerPasskeySignIn(signIn(null));
      expect(first.passkeyWithoutSecret, isTrue);
      expect(first.thisPasskeyCredentialId, isNull);
      expect(first.canConnectPasskey, isFalse);
      expect(first.chain.livePasskeys, isEmpty);
    });

    test(
      'a list the server built around the passkey’s keys is not trusted',
      () async {
        final server = _FakeServer();
        final secret = Sealing.randomBytes(32);
        final hpke = PasskeyKeys.hpkeKey(secret);
        final signing = PasskeyKeys.signingKey(secret);
        // The public keys are on the real list, so a server knows them. The
        // anchor needs the secret, which it does not have.
        final attacker = _AttackerChain();
        attacker.entries.add(
          DeviceChainEntry.sign(
            user: _user,
            seq: 2,
            action: DeviceChainEntry.actionAdd,
            kind: DeviceChainEntry.kindPasskey,
            label: 'Chrome on Mac',
            credentialId: 'cred-A',
            hpkePublicKey: hpke.publicKey,
            signingPublicKey: signing.publicKey,
            targetSeq: 0,
            previousHash: attacker.entries.last.hash,
            signerSeq: 1,
            signer: attacker.signing,
            anchorSignature: Sealing.sign(
              attacker.signing,
              SealedFormats.passkeyAnchorPayload(
                _user,
                attacker.entries.first.hash,
                'cred-A',
              ),
            ),
          ),
        );
        server.devices = attacker.toJson();
        server.epochs.add({'epoch': 1, 'priorWrap': '', 'rotationDue': false});
        server.wraps.add(
          _forgedWrap(
            recipient: hpke.publicKey,
            deviceSeq: 2,
            key: Sealing.newSymmetricKey(),
            epoch: 1,
            signer: attacker.signing,
            signerSeq: 1,
            chainSeq: 2,
          ),
        );

        final phone = _device(server);
        await phone.offerPasskeySignIn(signIn(secret));
        await phone.load();
        expect(phone.status, isNot(SealingStatus.ready));
        expect(phone.canSeal(_workspace), isFalse);
        expect(server.devices, hasLength(2));
      },
    );

    test('one the person took off is not put back by itself', () async {
      final server = _FakeServer();
      final (first, _) = await setUpWith(server, Sealing.randomBytes(32));
      expect(await first.removePasskeyEntry('cred-A'), isTrue);
      expect(first.chain.livePasskeys, isEmpty);
      expect(first.canSeal(_workspace), isTrue);

      await first.load();
      expect(first.chain.livePasskeys, isEmpty);
      expect(first.canConnectPasskey, isTrue);

      expect(await first.connectPasskey(), isTrue);
      expect(first.chain.livePasskeys.single.credentialId, 'cred-A');
      expect(first.canConnectPasskey, isFalse);
    });

    test('the recovery key takes passkeys off too', () async {
      final server = _FakeServer();
      final (first, code) = await setUpWith(server, Sealing.randomBytes(32));
      final record = _sealedRecord(first);
      final fresh = _device(server);
      fresh.recoveryInput.text = code;
      expect(await fresh.restoreWithRecoveryKey(), isTrue);
      expect(fresh.status, SealingStatus.ready);
      expect(fresh.chain.livePasskeys, isEmpty);
      expect(fresh.chain.live.map((e) => e.kind).toSet(), {
        DeviceChainEntry.kindDevice,
        DeviceChainEntry.kindRecovery,
      });
      expect(fresh.chain.live, hasLength(2));
      expect(fresh.openRecord(record), _canary);
    });
  });
}
