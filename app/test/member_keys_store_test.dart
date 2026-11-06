import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/crypto/sealing.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/features/sealing/store/member_keys_store.dart';

const _me = 'user000000000aa';
const _bob = 'user000000000bb';
const _workspace = 'wspace00000000a';

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A person's device list, signed the way their app would sign it.
class _List {
  final String user;
  final SealingKeyPair signing = Sealing.generateKeyPair();
  final List<DeviceChainEntry> entries = [];

  _List(this.user) {
    entries.add(_entry(1, Uint8List(0)));
  }

  DeviceChainEntry _entry(int seq, Uint8List previous) => DeviceChainEntry.sign(
    user: user,
    seq: seq,
    action: DeviceChainEntry.actionAdd,
    kind: DeviceChainEntry.kindDevice,
    label: 'Device $seq',
    hpkePublicKey: Sealing.generateKeyPair().publicKey,
    signingPublicKey: seq == 1
        ? signing.publicKey
        : Sealing.generateKeyPair().publicKey,
    targetSeq: 0,
    previousHash: previous,
    signerSeq: 1,
    signer: signing,
  );

  void grow() => entries.add(_entry(entries.length + 1, entries.last.hash));

  Uint8List get root => entries.first.hash;

  List<Map<String, dynamic>> toJson() => [
    for (final e in entries) {...e.toJson(), 'user': user},
  ];
}

class _Server {
  final Map<String, List<Map<String, dynamic>>> lists = {};

  http.Client get client => MockClient((request) async {
    if (request.url.path != '/api/sealed/workspaces/$_workspace/members') {
      return http.Response('{}', 404);
    }
    return http.Response(
      jsonEncode({
        'members': [
          for (final entry in lists.entries)
            {
              'user': entry.key,
              'email': '${entry.key}@example.test',
              'isSelf': entry.key == _me,
              'canRead': true,
              'devices': entry.value,
            },
        ],
      }),
      200,
    );
  });
}

MemberKeysStore _store(
  _Server server,
  _Storage storage, {
  Uint8List? Function()? ownRoot,
}) => MemberKeysStore(
  ApiClient(httpClient: server.client),
  currentUser: () => _me,
  ownRoot: ownRoot ?? () => null,
  storage: storage,
);

Future<MemberKeys> _bobAfterLoad(MemberKeysStore store) async {
  await store.load(_workspace);
  expect(store.errorMessage, isNull);
  return store.byUser(_bob)!;
}

void main() {
  test('the fingerprint format does not drift', () {
    expect(
      SealedFormats.memberFingerprint(_me, Uint8List(32)),
      matches(RegExp(r'^\d{5}( \d{5}){5}$')),
    );
    expect(
      SealedFormats.memberFingerprint(_me, Uint8List(32)),
      isNot(SealedFormats.memberFingerprint(_bob, Uint8List(32))),
    );
    expect(SealedFormats.memberFingerprint(_me, Uint8List(32)), _pinnedVector);
  });

  test('a first list is trusted, and growing from it stays trusted', () async {
    final server = _Server();
    final bob = _List(_bob);
    server.lists[_bob] = bob.toJson();
    final store = _store(server, _Storage());

    var seen = await _bobAfterLoad(store);
    expect(seen.state, MemberKeyState.trusted);
    expect(seen.usable, isTrue);
    expect(seen.fingerprint, SealedFormats.memberFingerprint(_bob, bob.root));

    bob.grow();
    server.lists[_bob] = bob.toJson();
    seen = await _bobAfterLoad(store);
    expect(seen.state, MemberKeyState.trusted);
    // Adding a device does not change who they are.
    expect(seen.fingerprint, SealedFormats.memberFingerprint(_bob, bob.root));
  });

  test('a list that starts elsewhere is a change, until accepted', () async {
    final server = _Server();
    final storage = _Storage();
    final first = _List(_bob);
    server.lists[_bob] = first.toJson();
    await _bobAfterLoad(_store(server, storage));

    final replaced = _List(_bob);
    server.lists[_bob] = replaced.toJson();
    final store = _store(server, storage);
    final seen = await _bobAfterLoad(store);
    expect(seen.state, MemberKeyState.changed);
    expect(seen.usable, isFalse);
    expect(
      seen.previousFingerprint,
      SealedFormats.memberFingerprint(_bob, first.root),
    );
    expect(store.changed.map((m) => m.user), [_bob]);

    await store.acceptChange(_bob);
    expect(store.byUser(_bob)!.state, MemberKeyState.trusted);
    expect(
      (await _bobAfterLoad(_store(server, storage))).state,
      MemberKeyState.trusted,
    );
  });

  test('a rolled-back list is a change', () async {
    final server = _Server();
    final storage = _Storage();
    final bob = _List(_bob)..grow();
    server.lists[_bob] = bob.toJson();
    await _bobAfterLoad(_store(server, storage));

    server.lists[_bob] = bob.toJson().sublist(0, 1);
    final seen = await _bobAfterLoad(_store(server, storage));
    expect(seen.state, MemberKeyState.changed);
  });

  test('a list that took another turn is a change', () async {
    final server = _Server();
    final storage = _Storage();
    final bob = _List(_bob)..grow();
    server.lists[_bob] = bob.toJson();
    await _bobAfterLoad(_store(server, storage));

    // Same start, a different second entry.
    bob.entries.removeLast();
    bob.grow();
    server.lists[_bob] = bob.toJson();
    final seen = await _bobAfterLoad(_store(server, storage));
    expect(seen.state, MemberKeyState.changed);
  });

  test('a list gone empty after being seen is a change', () async {
    final server = _Server();
    final storage = _Storage();
    server.lists[_bob] = _List(_bob).toJson();
    await _bobAfterLoad(_store(server, storage));

    server.lists[_bob] = [];
    final seen = await _bobAfterLoad(_store(server, storage));
    expect(seen.state, MemberKeyState.changed);
  });

  test('someone without encryption is just that', () async {
    final server = _Server();
    server.lists[_bob] = [];
    final seen = await _bobAfterLoad(_store(server, _Storage()));
    expect(seen.state, MemberKeyState.notSetUp);
    expect(seen.fingerprint, isNull);
  });

  test('a list that fails verification is never pinned', () async {
    final server = _Server();
    final storage = _Storage();
    final bob = _List(_bob);
    final forged = {...bob.toJson().first, 'label': 'Edited'};
    server.lists[_bob] = [forged];
    expect(
      (await _bobAfterLoad(_store(server, storage))).state,
      MemberKeyState.broken,
    );

    // So the real one is seen as a first sight, not a change.
    server.lists[_bob] = bob.toJson();
    expect(
      (await _bobAfterLoad(_store(server, storage))).state,
      MemberKeyState.trusted,
    );
  });

  test('a list for someone else is not theirs', () async {
    final server = _Server();
    server.lists[_bob] = _List('user000000000cc').toJson();
    final seen = await _bobAfterLoad(_store(server, _Storage()));
    expect(seen.state, MemberKeyState.broken);
  });

  test('verifying sticks, and a change clears it', () async {
    final server = _Server();
    final storage = _Storage();
    server.lists[_bob] = _List(_bob).toJson();
    final store = _store(server, storage);
    await _bobAfterLoad(store);
    await store.markVerified(_bob);
    expect(store.byUser(_bob)!.state, MemberKeyState.verified);
    expect(
      (await _bobAfterLoad(_store(server, storage))).state,
      MemberKeyState.verified,
    );

    server.lists[_bob] = _List(_bob).toJson();
    final again = _store(server, storage);
    expect((await _bobAfterLoad(again)).state, MemberKeyState.changed);
    await again.acceptChange(_bob);
    expect(again.byUser(_bob)!.state, MemberKeyState.trusted);
  });

  test('a changed list cannot be verified', () async {
    final server = _Server();
    final storage = _Storage();
    server.lists[_bob] = _List(_bob).toJson();
    await _bobAfterLoad(_store(server, storage));
    server.lists[_bob] = _List(_bob).toJson();
    final store = _store(server, storage);
    await _bobAfterLoad(store);
    await store.markVerified(_bob);
    expect(store.byUser(_bob)!.state, MemberKeyState.changed);
  });

  test('my own list must start where this device knows it does', () async {
    final server = _Server();
    final mine = _List(_me);
    server.lists[_me] = mine.toJson();

    final honest = _store(server, _Storage(), ownRoot: () => mine.root);
    await honest.load(_workspace);
    expect(honest.byUser(_me)!.state, MemberKeyState.verified);

    final elsewhere = _List(_me).root;
    final fooled = _store(server, _Storage(), ownRoot: () => elsewhere);
    await fooled.load(_workspace);
    expect(fooled.byUser(_me)!.state, MemberKeyState.changed);
  });
}

/// Computed once from the format above. A change here changes every
/// fingerprint people have already compared.
const _pinnedVector = '56312 37578 22557 61514 16119 58181';
