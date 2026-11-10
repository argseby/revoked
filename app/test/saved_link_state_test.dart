import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/crypto/sealing.dart';
import 'package:revoked_app/features/bookmarks/store/saved_link_state.dart';
import 'package:revoked_app/features/shares/store/shared_link_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/sealing_link_read_vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final key = SealedFormats.parseLinkKey(fixture['linkKey'] as String)!;
  final original = fixture['entry'] as Map<String, dynamic>;
  final copy = SealedFormats.linkCopyKey(
    linkKey: key,
    record: original['id'] as String,
  );
  final viewer = SealedFormats.openLinkViewer(
    copyKey: copy,
    wrapped: original['viewerWrap'] as String,
    record: original['id'] as String,
    version: 6,
  );
  Map<String, dynamic> entry(int version, String value) => {
    ...original,
    'sealedVersion': version,
    'viewerWrap': SealedFormats.wrapLinkViewer(
      copyKey: copy,
      valueKey: viewer.valueKey,
      workspace: viewer.workspace,
      record: original['id'] as String,
      version: version,
    ),
    'sealedValue': SealedFormats.sealValue(
      valueKey: viewer.valueKey,
      value: jsonEncode({...fixture['content'] as Map, 'v': value}),
      workspace: viewer.workspace,
      record: original['id'] as String,
      recordKey: original['key'] as String,
      version: version,
    ),
  };
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  const address = 'device-account-share';
  Future<Map<String, dynamic>> read(
    SavedLinkState state,
    Map<String, dynamic> r,
  ) async {
    final served = {
      'records': [
        r,
        {'id': 'plain', 'value': 'plain'},
      ],
    };
    final data = await state.checkRead(
      address,
      served,
      SharedLinkReader.open(served, key),
    );
    expect((data['records'] as List)[1]['value'], 'plain');
    return (data['records'] as List).first as Map<String, dynamic>;
  }

  test(
    'saved share history survives a new reader and rejects rollback and same-version changes',
    () async {
      final state = SavedLinkState();
      expect((await read(state, original))['value'], isNotNull);
      final newer = entry(7, 'newer');
      expect((await read(state, newer))['value'], 'newer');
      for (final older in [
        original,
        entry(7, 'different'),
        {...original, 'sealed': false, 'value': 'downgraded'},
      ]) {
        final result = await read(SavedLinkState(), older);
        expect(result.containsKey('value'), isFalse);
        expect(ClosedEntry.of(result), ClosedEntry.rollback);
      }
      expect((await read(SavedLinkState(), newer))['value'], 'newer');
    },
  );
  test('duplicate record IDs never display a value or advance a pin', () async {
    final state = SavedLinkState();
    final served = {
      'records': [entry(9, 'nine'), original],
    };
    final checked = await state.checkRead(
      address,
      served,
      SharedLinkReader.open(served, key),
    );
    for (final row in checked['records'] as List) {
      expect(row.containsKey('value'), isFalse);
      expect(ClosedEntry.of(row), ClosedEntry.rollback);
    }
    expect((await read(state, original))['value'], isNotNull);
  });

  test('unauthenticated claimed versions do not advance the pin', () async {
    final state = SavedLinkState();
    await read(state, {...original, 'sealedVersion': 999999});
    expect((await read(state, original))['value'], isNotNull);
  });
  test('concurrent reads retain the highest authenticated version', () async {
    await Future.wait([
      read(SavedLinkState(), entry(8, 'eight')),
      read(SavedLinkState(), entry(7, 'seven')),
    ]);
    expect(
      ClosedEntry.of(await read(SavedLinkState(), entry(7, 'seven'))),
      ClosedEntry.rollback,
    );
  });
  test(
    'device keys are scoped to account, home server and exact share',
    () async {
      final a = SavedLinkState.address('alice', 'https://home', '', 'share');
      final state = SavedLinkState();
      await state.saveKey(a, key);
      expect(await SavedLinkState().key(a), key);
      for (final other in [
        SavedLinkState.address('bob', 'https://home', '', 'share'),
        SavedLinkState.address('alice', 'https://other', '', 'share'),
        SavedLinkState.address('alice', 'https://home', 'foreign', 'share'),
        SavedLinkState.address('alice', 'https://home', '', 'other'),
      ]) {
        expect(await state.key(other), isNull);
      }
      await state.deleteKey(a);
      expect(await state.key(a), isNull);
    },
  );
  test('bookmark key wraps bind every identity field and the account key', () {
    final account = Sealing.newSymmetricKey();
    final wrap = SealedFormats.wrapBookmarkKey(
      accountKey: account,
      linkKey: key,
      user: 'alice',
      server: 'https://home',
      origin: 'foreign',
      slug: 'share',
      epoch: 1,
    );
    Uint8List open({
      Uint8List? accountKey,
      String user = 'alice',
      String server = 'https://home',
      String origin = 'foreign',
      String slug = 'share',
      int epoch = 1,
    }) => SealedFormats.openBookmarkKey(
      accountKey: accountKey ?? account,
      wrapped: wrap,
      user: user,
      server: server,
      origin: origin,
      slug: slug,
      epoch: epoch,
    );
    expect(open(), key);
    for (final wrong in <Uint8List Function()>[
      () => open(user: 'bob'),
      () => open(server: 'https://elsewhere'),
      () => open(origin: ''),
      () => open(slug: 'other'),
      () => open(epoch: 2),
      () => open(accountKey: Sealing.newSymmetricKey()),
    ]) {
      expect(wrong, throwsA(isA<SealingException>()));
    }
  });
}
