import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:revoked_app/core/crypto/sealing.dart';
import 'package:revoked_app/core/models/bookmark.dart';
import 'package:revoked_app/core/models/share_proposal.dart';
import 'package:revoked_app/features/bookmarks/store/bookmarks_store.dart';
import 'package:revoked_app/features/shares/view/share_proposal_screen.dart';
import 'package:revoked_app/features/shares/view/public_share_screen.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/features/vault/store/vault_store.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/share_sheet.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _me = 'user000000000aa';
const _workspace = 'wspace00000000a';
const _accountScope = 'account:$_me';
const _canary = 'smtp-password-canary-9d2f';

/// An honest server for encrypted records on links (design/e2ee-sharing.md
/// §3): it keeps what it is given, opens nothing, and enforces what the real
/// one does. A link takes an encrypted record only with a seal, and a write to
/// such a record has to renew every link carrying it.
class _Server {
  final devices = <Map<String, dynamic>>[];
  final epochs = <Map<String, dynamic>>[];
  final wraps = <Map<String, dynamic>>[];
  final accountEpochs = <Map<String, dynamic>>[];
  final accountWraps = <Map<String, dynamic>>[];

  final records = <String, Map<String, dynamic>>{};
  final links = <String, Map<String, dynamic>>{};
  final bookmarks = <String, Map<String, dynamic>>{};
  bool connectedTool = false;

  /// link id → record id → the seal as it was sent.
  final seals = <String, Map<String, Map<String, dynamic>>>{};

  /// Every byte this server was sent, to look for what must never arrive.
  final received = StringBuffer();
  final calls = <String>[];
  final sealedLinkBodies = <Map<String, dynamic>>[];
  final recordWrites = <Map<String, dynamic>>[];

  bool failSealedLinks = false;

  /// Answers the next "which links" question as if none carried the record,
  /// the way a link added a moment later looks to the writer.
  bool hideLinksOnce = false;
  var _nextLink = 1;

  bool _isSealed(String id) => records[id]?['sealed'] == true;

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    final method = request.method;
    received
      ..writeln(request.url)
      ..writeln(request.body);
    calls.add('$method $path');
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;

    if (path.startsWith('/api/public/links/')) {
      final link = links.values.firstWhere(
        (l) => l['slug'] == path.split('/').last,
      );
      if (method == 'GET') return _json({'label': link['label']});
      return _json({
        'label': link['label'],
        'records': [
          for (final id in link['records'] as List)
            if (!_isSealed(id))
              records[id]
            else
              {
                for (final field in [
                  'id',
                  'key',
                  'label',
                  'type',
                  'format',
                  'sealed',
                  'sealedValue',
                  'sealedVersion',
                ])
                  field: records[id]![field],
                'viewerWrap': seals[link['id']]![id]!['viewerWrap'],
              },
        ],
      });
    }
    const bookmarksPath = '/api/collections/bookmarks/records';
    if (path == bookmarksPath && method == 'POST') {
      final saved = {'id': 'bookmark0000001', ...body};
      bookmarks[saved['id'] as String] = saved;
      return _json(saved);
    }
    if (path == bookmarksPath && method == 'GET') {
      return _json({'items': bookmarks.values.toList()});
    }
    if (path.startsWith('$bookmarksPath/') && method == 'PATCH') {
      final saved = bookmarks[path.split('/').last]!;
      saved.addAll(body);
      return _json(saved);
    }
    if (path == '/api/collections/bookmarkGroups/records' ||
        path == '/api/collections/templates/records' ||
        path == '/api/collections/identities/records') {
      return _json({'items': []});
    }
    if (path == '/api/collections/connections/records') {
      return _json({
        'items': [
          if (connectedTool)
            {
              'id': 'connection00001',
              'clientId': 'https://tool.example',
              'clientName': 'Tool',
              'allowHandOver': true,
              'user': _me,
            },
        ],
      });
    }
    if (path == '/api/server') {
      return _json({
        'sealing': {'records': true},
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
      final id = body['id'] as String;
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
      };
      return _json(records[id]!);
    }
    if (method == 'GET') {
      if (path == '/api/collections/records/records') {
        return _json({'items': records.values.toList()});
      }
      if (path == '/api/collections/sections/records') {
        return _json({'items': []});
      }
      if (path == '/api/shared/vault') {
        return _json({'records': [], 'sections': []});
      }
      if (path == '/api/collections/links/records') {
        return _json({'items': links.values.toList()});
      }
    }
    final recordLinks = RegExp(
      r'^/api/sealed/records/([^/]+)/links$',
    ).firstMatch(path);
    if (recordLinks != null) {
      final id = recordLinks.group(1)!;
      if (!_isSealed(id)) {
        return _json({
          'record': id,
          'version': 0,
          'links': [
            for (final link in links.values)
              if ((link['records'] as List).contains(id) && link['user'] == _me)
                {
                  ...link,
                  'sealedKeyWraps':
                      link['sealedKeyWraps'] ?? <String, dynamic>{},
                },
          ],
        });
      }
      final hidden = hideLinksOnce;
      hideLinksOnce = false;
      return _json({
        'record': id,
        'version': records[id]!['sealedVersion'],
        'links': [
          if (!hidden)
            for (final entry in seals.entries)
              if (entry.value.containsKey(id))
                {
                  'link': entry.key,
                  'writerWrap': entry.value[id]!['writerWrap'],
                },
        ],
      });
    }
    final recordWrite = RegExp(
      r'^/api/sealed/records/([^/]+)$',
    ).firstMatch(path);
    if (recordWrite != null && method == 'PUT') {
      final id = recordWrite.group(1)!;
      recordWrites.add(body);
      final record = records[id]!;
      if (record['sealedVersion'] != body['expectedVersion']) {
        return _refuse(409, 'sealed_version_conflict');
      }
      final given = {
        for (final raw in body['linkSeals'] as List<dynamic>? ?? const [])
          (raw as Map<String, dynamic>)['link'] as String: raw,
      };
      if (!_isSealed(id) && body['carryLinks'] == true) {
        final dropped = links.values
            .where(
              (l) =>
                  (l['records'] as List).contains(id) &&
                  !given.containsKey(l['id']),
            )
            .toList();
        if (dropped.isNotEmpty && body['dropLinks'] != true) {
          return _refuse(409, 'sealed_links_affected');
        }
        for (final link in dropped) {
          (link['records'] as List).remove(id);
        }
        for (final entry in given.entries) {
          final link = links[entry.key]!;
          link['sealedKeyWraps'] = {
            ...?(link['sealedKeyWraps'] as Map<String, dynamic>?),
            ...?(entry.value['keyWraps'] as Map<String, dynamic>?),
          };
          (seals[entry.key] ??= {})[id] = {...entry.value, 'version': 0};
        }
        record['sealed'] = true;
        record['value'] = '';
      }
      final missing = [
        for (final entry in seals.entries)
          if (entry.value.containsKey(id) && !given.containsKey(entry.key))
            entry.key,
      ];
      if (missing.isNotEmpty) {
        return _refuse(409, 'sealed_link_seals_missing', {'links': missing});
      }
      final version = (record['sealedVersion'] as int) + 1;
      record
        ..['label'] = body['label'] ?? record['label']
        ..['type'] = body['type'] ?? record['type']
        ..['format'] = body['format'] ?? record['format']
        ..['sealedValue'] = body['sealedValue']
        ..['sealedVersion'] = version
        ..['keyEpoch'] = body['keyEpoch']
        ..['keyWrap'] = body['keyWrap'];
      for (final entry in seals.entries) {
        if (!entry.value.containsKey(id)) continue;
        entry.value[id] = {...given[entry.key]!, 'version': version};
      }
      return _json(record);
    }

    const linksPath = '/api/collections/links/records';
    if (path == linksPath && method == 'POST') {
      final named = (body['records'] as List<dynamic>).cast<String>();
      if (named.any(_isSealed)) {
        return _refuse(400, 'sealed_record_unsupported');
      }
      final id = 'link0000000000${_nextLink++}';
      links[id] = {
        ...body,
        'id': id,
        'user': _me,
        'audienceKind': body['audienceKind'] ?? 'private',
        'editing': 'owner',
      };
      return _json(links[id]!);
    }
    if (path.startsWith('$linksPath/')) {
      final id = path.substring(linksPath.length + 1);
      final link = links[id];
      if (link == null) return http.Response('{}', 404);
      if (method == 'GET') return _json(link);
      if (method == 'DELETE') {
        links.remove(id);
        seals.remove(id);
        return http.Response('', 204);
      }
      if (method == 'PATCH') {
        final named = (body['records'] as List<dynamic>?)?.cast<String>();
        if (named != null) {
          final had = (link['records'] as List<dynamic>).cast<String>();
          // An encrypted record is only ever added with its seal.
          if (named.any((r) => _isSealed(r) && !had.contains(r))) {
            return _refuse(400, 'sealed_record_unsupported');
          }
          seals[id]?.removeWhere((record, _) => !named.contains(record));
        }
        link.addAll(body);
        return _json(link);
      }
    }
    final sealedLink = RegExp(r'^/api/sealed/links/([^/]+)$').firstMatch(path);
    if (sealedLink != null && method == 'PUT') {
      if (failSealedLinks) return _refuse(403, 'sealed_key_missing');
      final id = sealedLink.group(1)!;
      final link = links[id]!;
      sealedLinkBodies.add(body);
      if (body['replaceKey'] == true) {
        if (jsonEncode(body['expectedKeyWraps']) !=
            jsonEncode(link['sealedKeyWraps'])) {
          return _refuse(409, 'sealed_version_conflict');
        }
        final covered = (body['seals'] as List).map((s) => s['record']).toSet();
        if ((link['records'] as List).any(
          (id) => _isSealed(id) && !covered.contains(id),
        )) {
          return _refuse(409, 'sealed_link_seals_missing');
        }
      }
      final keyWraps = {
        ...?(link['sealedKeyWraps'] as Map<String, dynamic>?),
        ...?(body['keyWraps'] as Map<String, dynamic>?),
      };
      final given = (body['seals'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      if (given.isNotEmpty && !keyWraps.containsKey(_accountScope)) {
        return _refuse(400, 'sealed_link_content');
      }
      final named = (link['records'] as List<dynamic>).cast<String>().toList();
      for (final seal in given) {
        final record = seal['record'] as String;
        if (records[record]?['sealedVersion'] != seal['version']) {
          return _refuse(409, 'sealed_version_conflict');
        }
        (seals[id] ??= {})[record] = seal;
        if (!named.contains(record)) named.add(record);
      }
      link
        ..['records'] = named
        ..['sealedKeyWraps'] = keyWraps;
      return _json({'ok': true, 'link': id, 'records': named});
    }
    return http.Response('{}', 404);
  }

  static http.Response _json(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200);

  static http.Response _refuse(
    int status,
    String code, [
    Map<String, dynamic> extra = const {},
  ]) => http.Response(
    jsonEncode({'code': code, 'message': code, 'status': status, ...extra}),
    status,
  );
}

/// Signs someone in on a device with encryption turned on.
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

Future<String> _encryptedRecord(String key, String value) async {
  expect(
    await Stores.vault.createRecord(
      key: key,
      value: value,
      label: key,
      type: 'text',
      format: 'hidden',
      user: _me,
      workspace: _workspace,
      sealed: true,
    ),
    isTrue,
    reason: Stores.vault.errorMessage,
  );
  return Stores.vault.records.firstWhere((r) => r.key == key).id;
}

Future<Link> _share(List<String> records) async {
  expect(
    await Stores.shares.createShare(
      slug: 'share-${records.length}-${Stores.shares.shares.length}',
      label: 'For the contractor',
      user: _me,
      workspace: _workspace,
      sections: const [],
      records: records,
    ),
    isTrue,
    reason: Stores.shares.errorMessage,
  );
  return Stores.shares.shares.first;
}

/// Opens an encrypted record the way a viewer does: with what the server
/// serves for the link and the key from the link's address, and nothing a
/// member's device holds.
String _viewerReads(_Server server, Link link, String record, String keyText) {
  final linkKey = SealedFormats.parseLinkKey(keyText)!;
  final served = server.records[record]!;
  final seal = server.seals[link.id]![record]!;
  expect(seal['version'], served['sealedVersion']);
  final opened = SealedFormats.openLinkViewer(
    copyKey: SealedFormats.linkCopyKey(linkKey: linkKey, record: record),
    wrapped: seal['viewerWrap'] as String,
    record: record,
    version: served['sealedVersion'] as int,
  );
  return SealedContent.decode(
    SealedFormats.openValue(
      valueKey: opened.valueKey,
      sealed: served['sealedValue'] as String,
      workspace: opened.workspace,
      record: record,
      recordKey: served['key'] as String,
      version: served['sealedVersion'] as int,
    ),
  ).value;
}

/// Creating a link with an encrypted record alternates HTTP, which only
/// answers in real time, with frames, which only advance in fake time; one
/// window of each is not enough for every step.
Future<void> _settleWithIo(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a new share takes an encrypted record with its seal and a key of '
      'its own', () async {
    final server = await _signIn();
    final secret = await _encryptedRecord('smtp_password', _canary);

    final link = await _share([secret]);

    // The link is made without it; the record follows with its seal.
    expect(server.calls, contains('PUT /api/sealed/links/${link.id}'));
    expect(link.records, [secret]);
    final sent = server.sealedLinkBodies.single;
    expect((sent['seals'] as List).single['record'], secret);
    expect((sent['keyWraps'] as Map).keys, [_accountScope]);
    expect(link.hasKey, isTrue);

    final keyText = Stores.shares.linkKeyText(link)!;
    expect(_viewerReads(server, link, secret, keyText), _canary);

    // Neither the value nor the link's key ever reached the server.
    final received = server.received.toString();
    expect(received, isNot(contains(_canary)));
    expect(received, isNot(contains(keyText)));
    expect(
      received,
      isNot(contains(base64Url.encode(SealedFormats.parseLinkKey(keyText)!))),
    );
  });

  test('a share that cannot take its encrypted record is not left behind '
      'half made', () async {
    final server = await _signIn();
    final secret = await _encryptedRecord('smtp_password', _canary);
    server.failSealedLinks = true;

    final ok = await Stores.shares.createShare(
      slug: 'half',
      label: 'For the contractor',
      user: _me,
      workspace: _workspace,
      sections: const [],
      records: [secret],
    );

    expect(ok, isFalse);
    expect(Stores.shares.errorMessage, isNotNull);
    expect(server.links, isEmpty);
    expect(Stores.shares.shares, isEmpty);
  });

  test('an existing share gets its key with its first encrypted record, and '
      'keeps it', () async {
    final server = await _signIn();
    final first = await _encryptedRecord('smtp_password', _canary);
    final second = await _encryptedRecord('api_token', 'token-canary-4c1e');
    final link = await _share(const []);
    expect(link.hasKey, isFalse);
    expect(Stores.shares.linkKeyText(link), isNull);

    expect(
      await Stores.shares.updateShare(link.id, {
        'records': [first],
      }),
      isTrue,
      reason: Stores.shares.errorMessage,
    );
    // Said once: whoever holds the old address needs the new one.
    expect(Stores.shares.takeAddressChanged(link.id), isTrue);
    expect(Stores.shares.takeAddressChanged(link.id), isFalse);
    final withKey = Stores.shares.findById(link.id)!;
    final keyText = Stores.shares.linkKeyText(withKey)!;

    expect(
      await Stores.shares.updateShare(link.id, {
        'records': [second, first],
      }),
      isTrue,
      reason: Stores.shares.errorMessage,
    );
    expect(Stores.shares.takeAddressChanged(link.id), isFalse);
    final both = Stores.shares.findById(link.id)!;
    // The same key, sent to the server once, and the owner's order kept.
    expect(Stores.shares.linkKeyText(both), keyText);
    expect(
      server.sealedLinkBodies.where((b) => b['keyWraps'] != null),
      hasLength(1),
    );
    expect(both.records, [second, first]);
    expect(_viewerReads(server, both, first, keyText), _canary);
    expect(_viewerReads(server, both, second, keyText), 'token-canary-4c1e');

    // Taken off again through the ordinary update.
    expect(
      await Stores.shares.updateShare(link.id, {
        'records': [second],
      }),
      isTrue,
    );
    expect(server.seals[link.id]!.keys, [second]);
  });

  test('a change to an encrypted record renews every link carrying '
      'it', () async {
    final server = await _signIn();
    final secret = await _encryptedRecord('smtp_password', _canary);
    final one = await _share([secret]);
    final two = await _share([secret]);
    final keyOne = Stores.shares.linkKeyText(one)!;
    final keyTwo = Stores.shares.linkKeyText(two)!;
    expect(keyOne, isNot(keyTwo));

    expect(
      await Stores.vault.updateRecord(secret, {'value': 'rotated-canary-71aa'}),
      isTrue,
      reason: Stores.vault.errorMessage,
    );

    final write = server.recordWrites.last;
    expect(
      (write['linkSeals'] as List).map((s) => s['link']),
      unorderedEquals([one.id, two.id]),
    );
    // Each address still opens the record, now at its new value.
    expect(_viewerReads(server, one, secret, keyOne), 'rotated-canary-71aa');
    expect(_viewerReads(server, two, secret, keyTwo), 'rotated-canary-71aa');
    expect(server.received.toString(), isNot(contains('rotated-canary-71aa')));

    // And again, from the wraps the last write left behind.
    expect(await Stores.vault.updateRecord(secret, {'value': 'third'}), isTrue);
    expect(_viewerReads(server, one, secret, keyOne), 'third');
  });

  test('a link that started carrying the record in between costs one '
      'retry', () async {
    final server = await _signIn();
    final secret = await _encryptedRecord('smtp_password', _canary);
    final link = await _share([secret]);
    final keyText = Stores.shares.linkKeyText(link)!;
    server.hideLinksOnce = true;

    expect(
      await Stores.vault.updateRecord(secret, {'value': 'after-retry'}),
      isTrue,
      reason: Stores.vault.errorMessage,
    );

    expect(server.recordWrites, hasLength(2));
    expect(server.recordWrites.first.containsKey('linkSeals'), isFalse);
    expect(_viewerReads(server, link, secret, keyText), 'after-retry');
  });

  test('a link the server made up cannot be renewed, and the record stays '
      'as it was', () async {
    final server = await _signIn();
    final secret = await _encryptedRecord('smtp_password', _canary);
    final link = await _share([secret]);
    // A wrap nobody holding the record's key made: here, one for a link of
    // another name.
    server.seals['link000000forged'] = {
      secret: Map.of(server.seals[link.id]![secret]!),
    };

    expect(
      await Stores.vault.updateRecord(secret, {'value': 'never-written'}),
      isFalse,
    );
    expect(server.recordWrites, isEmpty);
    expect(server.records[secret]!['sealedVersion'], 1);
  });

  test(
    'encrypting a plain record preserves its own links and adds address keys',
    () async {
      final server = await _signIn();
      const id = 'recordplain0001';
      final raw = <String, dynamic>{
        'id': id,
        'key': 'plain_password',
        'label': 'Password',
        'type': 'text',
        'format': 'hidden',
        'value': _canary,
        'user': _me,
        'workspace': _workspace,
        'sealed': false,
        'sealedVersion': 0,
      };
      server.records[id] = raw;
      Stores.vault.records.add(models.Record.fromJson(raw));
      final first = await _share([id]);
      final second = await _share([id]);
      expect(await Stores.vault.sealRecord(id), SealOutcome.sealed);
      for (final link in [first, second]) {
        final updated = await Stores.shares.getById(link.id);
        final key = Stores.shares.linkKeyText(updated)!;
        expect(_viewerReads(server, updated, id, key), _canary);
        expect(server.links[link.id]!['records'], contains(id));
      }
      expect(server.recordWrites.single['carryLinks'], isTrue);
      expect(server.received.toString().contains(_canary), isFalse);
    },
  );

  test(
    'a duplicate has its own key; replacing one link leaves the other alone',
    () async {
      final server = await _signIn();
      final id = await _encryptedRecord('smtp_password', _canary);
      final original = await _share([id]);
      final duplicate = await _share(original.records);
      final oldKey = Stores.shares.linkKeyText(original)!;
      final duplicateKey = Stores.shares.linkKeyText(duplicate)!;
      expect(duplicateKey, isNot(oldKey));
      expect(
        await Stores.shares.replaceLinkKey(original.id),
        isTrue,
        reason: Stores.shares.errorMessage,
      );
      final replaced = await Stores.shares.getById(original.id);
      final newKey = Stores.shares.linkKeyText(replaced)!;
      expect(newKey, isNot(oldKey));
      expect(_viewerReads(server, replaced, id, newKey), _canary);
      expect(
        () => _viewerReads(server, replaced, id, oldKey),
        throwsA(isA<Exception>()),
      );
      expect(_viewerReads(server, duplicate, id, duplicateKey), _canary);
      // Future vault writes continue under the replaced key, never the old one.
      expect(
        await Stores.vault.updateRecord(id, {'value': 'updated-secret'}),
        isTrue,
      );
      expect(_viewerReads(server, replaced, id, newKey), 'updated-secret');
      expect(
        _viewerReads(server, duplicate, id, duplicateKey),
        'updated-secret',
      );
      expect(
        () => _viewerReads(server, replaced, id, oldKey),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('saved keys sync only wrapped under the account key', () async {
    final server = await _signIn();
    final key = Sealing.newSymmetricKey();
    expect(
      await Stores.bookmarks.add(
        user: _me,
        origin: 'foreign.example',
        slug: 'saved',
        label: 'Saved',
        linkKey: key,
      ),
      isTrue,
    );
    final fresh = BookmarksStore(Stores.api);
    await fresh.load();
    final bookmark = fresh.bookmarks.single;
    expect(bookmark.sealedKey, isNotEmpty);
    expect(await fresh.keyFor(bookmark), key);
    expect(
      server.received.toString(),
      isNot(contains(SealedFormats.linkKeyText(key))),
    );
    final moved = Bookmark(
      id: bookmark.id,
      origin: 'other.example',
      slug: bookmark.slug,
      label: bookmark.label,
      sealedKey: bookmark.sealedKey,
      keyEpoch: bookmark.keyEpoch,
    );
    expect(await fresh.keyFor(moved), isNull);
  });

  test(
    'without account encryption a saved key remains on this device only',
    () async {
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
      final key = Sealing.newSymmetricKey();
      expect(
        await Stores.bookmarks.add(
          user: _me,
          origin: '',
          slug: 'saved-local',
          label: 'Saved',
          linkKey: key,
        ),
        isTrue,
      );
      final fresh = BookmarksStore(Stores.api);
      await fresh.load();
      expect(fresh.bookmarks.single.sealedKey, isEmpty);
      expect(await fresh.keyFor(fresh.bookmarks.single), key);
      expect(
        server.received.toString(),
        isNot(contains(SealedFormats.linkKeyText(key))),
      );
    },
  );

  testWidgets(
    'a saved share reopens without the original address and hides a replay',
    (tester) async {
      final server = await tester.runAsync(_signIn);
      late String record;
      late Link link;
      late Map<String, dynamic> older;
      late Map<String, dynamic> oldSeal;
      await tester.runAsync(() async {
        record = await _encryptedRecord('smtp_password', _canary);
        link = await _share([record]);
        older = Map.of(server!.records[record]!);
        oldSeal = Map.of(server.seals[link.id]![record]!);
        final key = SealedFormats.parseLinkKey(
          Stores.shares.linkKeyText(link)!,
        )!;
        expect(
          await Stores.bookmarks.add(
            user: _me,
            origin: '',
            slug: link.slug,
            label: 'Saved share',
            linkKey: key,
          ),
          isTrue,
        );
        expect(
          await Stores.vault.updateRecord(record, {'value': 'new saved value'}),
          isTrue,
        );
      });
      tester.view.physicalSize = const Size(1100, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: PublicShareScreen(shareSlug: link.slug)),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(
        (Stores.shares.shareData!['records'] as List).single['value'],
        'new saved value',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      server!.records[record] = older;
      server.seals[link.id]![record] = oldSeal;
      await tester.pumpWidget(
        MaterialApp(home: PublicShareScreen(shareSlug: link.slug)),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(
        find.text('This entry is older than the saved version'),
        findsOneWidget,
      );
      expect(
        (Stores.shares.shareData!['records'] as List).single.containsKey(
          'value',
        ),
        isFalse,
      );
    },
  );

  for (final approved in [false, true]) {
    testWidgets(
      'encrypted tool hand-over requires explicit approval: $approved',
      (tester) async {
        final server = await tester.runAsync(_signIn);
        server!.connectedTool = true;
        await tester.runAsync(() => _encryptedRecord('smtp_password', _canary));
        final launched = <Uri>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/url_launcher'),
              (call) async {
                launched.add(
                  Uri.parse((call.arguments as Map)['url'] as String),
                );
                return true;
              },
            );
        tester.view.physicalSize = const Size(1100, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          const MaterialApp(
            home: ShareProposalScreen(
              proposal: ShareProposal(
                label: 'Encrypted proposal',
                keys: ['smtp_password'],
                client: 'https://tool.example',
                from: 'Tool',
                redirect: 'https://tool.example/callback',
                state: 'state',
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        expect(find.text(_canary), findsNothing);
        // Encrypted entries start unticked; selecting one does not approve a hand-over.
        final initial = tester
            .widgetList<AppCheckbox>(find.byType(AppCheckbox))
            .where((c) => c.value == true);
        expect(initial, isEmpty);
        await tester.tap(find.text('smtp_password').first);
        await tester.pumpAndSettle();
        final consent = find.text('Hand this encrypted link to Tool');
        expect(consent, findsOneWidget);
        if (approved) {
          await tester.ensureVisible(consent);
          await tester.tap(consent);
          await tester.pumpAndSettle();
        }
        final create = find.text('Create link');
        await tester.ensureVisible(create);
        await tester.tap(create);
        await _settleWithIo(tester);
        expect(server.links, hasLength(1));
        expect(server.links.values.single['handedOver'], approved);
        if (approved) {
          final returned = launched.single;
          final full = Uri.splitQueryString(returned.fragment)['revoked_link']!;
          final link = Stores.shares.shares.single;
          final keyText = Stores.shares.linkKeyText(link)!;
          expect(full, endsWith('#k=$keyText'));
          expect(returned.query, isNot(contains(keyText)));
          expect(server.received.toString(), isNot(contains(keyText)));
          expect(returned.queryParameters['state'], 'state');
        } else {
          expect(launched, isEmpty);
        }
      },
    );
  }

  testWidgets('the share sheet hands out the address with its key', (
    tester,
  ) async {
    await tester.runAsync(_signIn);
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showShareSheet(
              context: context,
              slug: 'contractor',
              title: 'For the contractor',
              isRequest: false,
              linkKey: 'KEYTEXT',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('/s/contractor#k=KEYTEXT'), findsOneWidget);
    // The web link and the app link both end in it.
    expect(find.textContaining('contractor#k=KEYTEXT'), findsNWidgets(2));
    expect(find.textContaining('revoked://s/'), findsOneWidget);
    expect(find.textContaining('including the part after #'), findsOneWidget);
  });
}
