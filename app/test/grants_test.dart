import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/crypto/sealing.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart';
import 'package:revoked_app/features/sealing/store/member_keys_store.dart';

const _alice = 'user00000000ali';
const _bob = 'user00000000bob';
const _shared = 'wspace0000share';
const _canary = 'shared-secret-canary-41ac';

class _Storage implements FlutterSecureStorage {
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

/// An honest server for several people. Alice can grant in the shared
/// workspace; Bob can read there but not grant. Each also has a workspace of
/// their own, where their device list starts its first key.
class _Server {
  final Map<String, List<Map<String, dynamic>>> devices = {};
  final Map<String, List<Map<String, dynamic>>> epochs = {};
  final List<Map<String, dynamic>> wraps = [];
  final Map<String, Map<String, bool>> members = {
    _shared: {_alice: true, _bob: false},
  };

  /// Lets a dishonest server rewrite one person's list as others see it.
  List<Map<String, dynamic>> Function(String user)? listShownToOthers;

  void join(String workspace, String user, {bool canGrant = false}) =>
      members.putIfAbsent(workspace, () => {})[user] = canGrant;

  int currentEpoch(String workspace) => epochs[workspace]?.length ?? 0;

  bool holds(String workspace, String user) => wraps.any(
    (w) =>
        w['workspace'] == workspace &&
        w['user'] == user &&
        w['epoch'] == currentEpoch(workspace),
  );

  http.Client clientFor(String caller) => MockClient((request) async {
    final path = request.url.path;
    if (path == '/api/server') {
      return _json({
        'sealing': {'records': true},
      });
    }
    if (path == '/api/sealed/state') {
      return _json(
        jsonDecode(
              jsonEncode({
                'devices': devices[caller] ?? [],
                'workspaces': [
                  for (final ws in members.keys)
                    if (members[ws]!.containsKey(caller) &&
                        (epochs[ws] ?? []).isNotEmpty)
                      {
                        'workspace': ws,
                        'epochs': epochs[ws],
                        'wraps': [
                          for (final w in wraps)
                            if (w['workspace'] == ws && w['user'] == caller) w,
                        ],
                      },
                ],
                'account': null,
              }),
            )
            as Map<String, dynamic>,
      );
    }
    final membersPath = RegExp(r'^/api/sealed/workspaces/([^/]+)/members$');
    if (membersPath.hasMatch(path)) {
      final ws = membersPath.firstMatch(path)!.group(1)!;
      return _json({
        'epoch': currentEpoch(ws),
        'members': [
          for (final entry in members[ws]!.entries)
            {
              'user': entry.key,
              'email': '${entry.key}@example.test',
              'isSelf': entry.key == caller,
              'canRead': true,
              'canGrant': entry.value,
              'holdsKey': holds(ws, entry.key),
              'devices': entry.key != caller && listShownToOthers != null
                  ? listShownToOthers!(entry.key)
                  : devices[entry.key] ?? [],
            },
        ],
      });
    }
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (path == '/api/sealed/devices') {
      final list = devices.putIfAbsent(caller, () => []);
      for (final raw in body['entries'] as List<dynamic>) {
        final entry = {...raw as Map<String, dynamic>, 'user': caller};
        list.add(entry);
        if (entry['action'] == 'remove') {
          final touched = {
            for (final w in wraps)
              if (w['user'] == caller && w['deviceSeq'] == entry['targetSeq'])
                w['workspace'],
          };
          wraps.removeWhere(
            (w) => w['user'] == caller && w['deviceSeq'] == entry['targetSeq'],
          );
          for (final ws in touched) {
            epochs[ws]!.last['rotationDue'] = true;
          }
        }
      }
      for (final raw in body['wraps'] as List<dynamic>? ?? const []) {
        wraps.add({...raw as Map<String, dynamic>, 'user': caller});
      }
      return _json({'ok': true});
    }
    final epochsPath = RegExp(r'^/api/sealed/workspaces/([^/]+)/epochs$');
    if (epochsPath.hasMatch(path)) {
      final ws = epochsPath.firstMatch(path)!.group(1)!;
      final list = epochs.putIfAbsent(ws, () => []);
      if (body['epoch'] != list.length + 1) {
        return http.Response(
          jsonEncode({'code': 'sealed_version_conflict', 'status': 409}),
          409,
        );
      }
      if ((body['grants'] as List<dynamic>? ?? const []).isNotEmpty &&
          members[ws]![caller] != true) {
        return http.Response(jsonEncode({'code': 'missing_permission'}), 403);
      }
      list.add({
        'epoch': body['epoch'],
        'priorWrap': body['priorWrap'],
        'rotationDue': false,
      });
      for (final raw in body['wraps'] as List<dynamic>) {
        wraps.add({...raw as Map<String, dynamic>, 'user': caller});
      }
      _grant(ws, caller, body['epoch'] as int, body['grants']);
      return _json({'ok': true});
    }
    final grantsPath = RegExp(r'^/api/sealed/workspaces/([^/]+)/grants$');
    if (grantsPath.hasMatch(path)) {
      final ws = grantsPath.firstMatch(path)!.group(1)!;
      if (members[ws]![caller] != true) {
        return http.Response(jsonEncode({'code': 'missing_permission'}), 403);
      }
      _grant(ws, caller, body['epoch'] as int, body['grants']);
      return _json({'ok': true});
    }
    return http.Response('{}', 404);
  });

  void _grant(String ws, String granter, int epoch, Object? grants) {
    for (final raw in grants as List<dynamic>? ?? const []) {
      final g = raw as Map<String, dynamic>;
      wraps.add({
        'workspace': ws,
        'epoch': epoch,
        'user': g['user'],
        'deviceSeq': g['deviceSeq'],
        'wrap': g['wrap'],
        'signerSeq': g['signerSeq'],
        'chainSeq': g['chainSeq'],
        'recipientChainSeq': g['recipientChainSeq'],
        'signature': g['signature'],
        'granter': granter,
      });
    }
  }

  static http.Response _json(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200);
}

/// One person on one device: their keys, and what they know of the others.
class _Person {
  final String user;
  final _Storage storage;
  late final KeysStore keys;
  late final MemberKeysStore members;

  _Person(_Server server, this.user, {_Storage? storage})
    : storage = storage ?? _Storage() {
    final api = ApiClient(httpClient: server.clientFor(user));
    members = MemberKeysStore(
      api,
      currentUser: () => user,
      ownRoot: () => keys.rootHash,
      storage: this.storage,
    );
    keys = KeysStore(
      api,
      currentUser: () => user,
      storage: this.storage,
      membersOf: members.membersOf,
    );
  }

  Future<String> setUp(String workspace) async {
    await keys.load();
    keys.beginSetup();
    final code = keys.recoveryCode!;
    final groups = code.split('-');
    keys.recoveryConfirm.text = groups.sublist(groups.length - 2).join('-');
    expect(await keys.finishRecovery(workspace: workspace), isTrue);
    return code;
  }

  /// Opens the Members part, then compares fingerprints with [other].
  Future<void> verify(String other) async {
    await members.load(_shared);
    await members.markVerified(other);
    expect(members.byUser(other)!.state, MemberKeyState.verified);
  }

  Future<bool> grantTo(String other) async {
    await members.load(_shared);
    return keys.grantAccess(_shared, members.byUser(other)!);
  }

  models.Record seal(String id, {String value = _canary}) {
    final payload = keys.sealValue(
      workspace: _shared,
      record: id,
      recordKey: 'smtp_password',
      version: 1,
      value: value,
    );
    return models.Record(
      id: id,
      key: 'smtp_password',
      value: '',
      label: 'SMTP password',
      type: 'text',
      format: 'hidden',
      user: user,
      workspace: _shared,
      sealed: true,
      sealedValue: payload.sealedValue,
      sealedVersion: 1,
      keyEpoch: payload.keyEpoch,
      keyWrap: payload.keyWrap,
    );
  }
}

Future<(_Server, _Person, _Person)> _aliceAndBob() async {
  final server = _Server();
  server.join('wspace00000bob1', _bob, canGrant: true);
  final alice = _Person(server, _alice);
  await alice.setUp(_shared);
  final bob = _Person(server, _bob);
  await bob.setUp('wspace00000bob1');
  expect(bob.keys.isLockedFor(_shared), isTrue);
  return (server, alice, bob);
}

void main() {
  test('a grant is used once the granter is verified', () async {
    final (server, alice, bob) = await _aliceAndBob();
    final record = alice.seal('record000000001');

    expect(await alice.grantTo(_bob), isTrue, reason: alice.keys.errorMessage);
    expect(server.holds(_shared, _bob), isTrue);

    // Bob has a copy now, but Alice's word on her keys is the server's.
    await bob.keys.load();
    expect(bob.keys.pendingGrants[_shared], {_alice});
    expect(bob.keys.canSeal(_shared), isFalse);
    expect(bob.keys.openRecord(record), isNull);

    await bob.verify(_alice);
    await bob.keys.load();
    expect(bob.keys.pendingGrants[_shared], isNull);
    expect(bob.keys.canSeal(_shared), isTrue);
    expect(bob.keys.openRecord(record), _canary);

    // And Alice reads what Bob writes.
    final fromBob = bob.seal('record000000002', value: 'from-bob');
    expect(alice.keys.openRecord(fromBob), 'from-bob');
  });

  test('only someone who may grant can, and never to a changed list', () async {
    final (server, alice, bob) = await _aliceAndBob();
    // Bob cannot hand out what he does not hold.
    await bob.members.load(_shared);
    expect(
      await bob.keys.grantAccess(_shared, bob.members.byUser(_alice)!),
      isFalse,
    );

    // Alice saw Bob's list once; then the server shows her another.
    await alice.members.load(_shared);
    final forged = _Person(_Server(), _bob);
    await forged.setUp('wspace00000bob1');
    server.listShownToOthers = (user) =>
        user == _bob ? forged.keys.chain.entries.map(_json).toList() : [];
    expect(await alice.grantTo(_bob), isFalse);
    expect(alice.members.byUser(_bob)!.state, MemberKeyState.changed);
    expect(server.holds(_shared, _bob), isFalse);
  });

  test(
    'a list the server made up for the granter hands over nothing',
    () async {
      final (server, alice, bob) = await _aliceAndBob();
      // Bob pins Alice's real list and compares fingerprints.
      await bob.verify(_alice);

      // A server-made "Alice" grants Bob a key the server knows.
      final fake = _Person(
        _Server()..members[_shared] = {_alice: true},
        _alice,
      );
      await fake.setUp(_shared);
      final key = Sealing.newSymmetricKey();
      final device = DeviceChainEntry.fromJson({
        ...server.devices[_bob]!.first,
      });
      final wrap = SealedFormats.grantWorkspaceKey(
        recipientHpkeKey: device.hpkePublicKey,
        key: key,
        workspace: _shared,
        epoch: 1,
        recipientUser: _bob,
        granterUser: _alice,
      );
      server.wraps.add({
        'workspace': _shared,
        'epoch': 1,
        'user': _bob,
        'deviceSeq': device.seq,
        'wrap': wrap,
        'signerSeq': 1,
        'chainSeq': 1,
        'recipientChainSeq': 1,
        'signature': SealedFormats.encode(
          Sealing.sign(
            Sealing.generateKeyPair(),
            SealedFormats.grantSignaturePayload(
              workspace: _shared,
              epoch: 1,
              recipientUser: _bob,
              recipientHpkeKey: device.hpkePublicKey,
              wrap: wrap,
              granterUser: _alice,
              granterChainSeq: 1,
              recipientChainSeq: 1,
            ),
          ),
        ),
        'granter': _alice,
      });
      server.listShownToOthers = (user) =>
          user == _alice ? fake.keys.chain.entries.map(_json).toList() : [];
      bob.members.forgetSession();
      await bob.keys.load();
      expect(bob.keys.canSeal(_shared), isFalse);
      expect(bob.keys.pendingGrants[_shared], {_alice});
    },
  );

  test('a new key carries the members along', () async {
    final (server, alice, bob) = await _aliceAndBob();
    expect(await alice.grantTo(_bob), isTrue);
    await bob.verify(_alice);

    final second = _Person(server, _alice);
    await second.keys.load();
    await second.keys.prepareThisDevice();
    expect(await alice.keys.addDevice(second.keys.deviceInvite!), isTrue);
    await second.keys.load();
    expect(
      await second.keys.confirmThisDevice(alice.keys.deviceConfirmation!),
      isTrue,
    );
    expect(await alice.keys.removeDevice(second.keys.thisDeviceSeq!), isTrue);

    expect(server.currentEpoch(_shared), 2);
    expect(server.holds(_shared, _bob), isTrue);
    await bob.keys.load();
    expect(bob.keys.canSeal(_shared), isTrue);
    final after = alice.seal('record000000003');
    expect(after.keyEpoch, 2);
    expect(bob.keys.openRecord(after), _canary);
  });

  test(
    'someone who may not grant leaves a due key to someone who may',
    () async {
      final (server, alice, bob) = await _aliceAndBob();
      expect(await alice.grantTo(_bob), isTrue);
      await bob.verify(_alice);
      await bob.keys.load();
      expect(bob.keys.canSeal(_shared), isTrue);

      server.epochs[_shared]!.last['rotationDue'] = true;
      await bob.keys.load();
      // Replacing it here would cut Alice off; Bob waits instead.
      expect(server.currentEpoch(_shared), 1);
      expect(bob.keys.canSeal(_shared), isFalse);

      await alice.keys.load();
      expect(server.currentEpoch(_shared), 2);
      await bob.keys.load();
      expect(bob.keys.canSeal(_shared), isTrue);
    },
  );

  test('a granted key reaches the recipient\'s other devices', () async {
    final (server, alice, bob) = await _aliceAndBob();
    final record = alice.seal('record000000001');
    expect(await alice.grantTo(_bob), isTrue);
    await bob.verify(_alice);
    await bob.keys.load();

    final phone = _Person(server, _bob);
    await phone.keys.load();
    await phone.keys.prepareThisDevice();
    expect(await bob.keys.addDevice(phone.keys.deviceInvite!), isTrue);
    await phone.keys.load();
    expect(
      await phone.keys.confirmThisDevice(bob.keys.deviceConfirmation!),
      isTrue,
    );
    // Its own copy came from Bob's own device: no fingerprint to compare.
    expect(phone.keys.openRecord(record), _canary);
  });

  test('the recovery key brings a granted key back', () async {
    final server = _Server();
    server.join('wspace00000bob1', _bob, canGrant: true);
    final alice = _Person(server, _alice);
    await alice.setUp(_shared);
    final bobStorage = _Storage();
    final bob = _Person(server, _bob, storage: bobStorage);
    final code = await bob.setUp('wspace00000bob1');
    final record = alice.seal('record000000001');
    expect(await alice.grantTo(_bob), isTrue);
    await bob.verify(_alice);
    await bob.keys.load();

    // A new device of Bob's, which still remembers verifying Alice: the pins
    // are per person, and a fresh install would compare again.
    final fresh = _Person(
      server,
      _bob,
      storage: _Storage()
        ..values.addAll({
          for (final e in bobStorage.values.entries)
            if (e.key.startsWith('sealed_members_')) e.key: e.value,
        }),
    );
    await fresh.keys.load();
    fresh.keys.recoveryInput.text = code;
    expect(await fresh.keys.restoreWithRecoveryKey(), isTrue);
    expect(fresh.keys.openRecord(record), _canary);
  });
}

Map<String, dynamic> _json(DeviceChainEntry e) => {
  ...e.toJson(),
  'user': e.user,
};
