import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart';
import 'package:revoked_app/features/sealing/view/sealing_section.dart';
import 'package:revoked_app/features/shares/view/share_contents_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _user = 'user000000000aa';
const _workspace = 'wspace00000000a';
const _secret = 'smtp-secret-canary-41b7';

/// A server that keeps what it is given, and remembers every request.
class _Server {
  final devices = <Map<String, dynamic>>[];
  final epochs = <Map<String, dynamic>>[];
  final wraps = <Map<String, dynamic>>[];
  final records = <Map<String, dynamic>>[];
  final seen = <http.Request>[];
  bool supportsSealing = true;

  /// Mirrors what the real server refuses: an old-style write of a value into
  /// a sealed record through the collection API.
  bool refusedPlainWrite = false;

  Future<http.Response> handle(http.Request request) async {
    seen.add(request);
    final path = request.url.path;
    final body = request.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;

    if (path == '/api/server') {
      return _json({
        'sealing': {'records': supportsSealing},
      });
    }
    if (path == '/api/sealed/state') {
      return _json({
        'devices': devices,
        'workspaces': epochs.isEmpty
            ? const []
            : [
                {'workspace': _workspace, 'epochs': epochs, 'wraps': wraps},
              ],
      });
    }
    if (path == '/api/sealed/devices') {
      for (final raw in body['entries'] as List<dynamic>) {
        devices.add({...raw as Map<String, dynamic>, 'user': _user});
      }
      return _json({'ok': true});
    }
    if (path.endsWith('/epochs')) {
      epochs.add({
        'epoch': body['epoch'],
        'priorWrap': body['priorWrap'],
        'rotationDue': false,
      });
      wraps.addAll((body['wraps'] as List<dynamic>).cast());
      return _json({'ok': true});
    }
    if (path == '/api/sealed/records') {
      final row = _row(body, version: 1);
      records.add(row);
      return _json(row);
    }
    if (path.startsWith('/api/sealed/records/') && request.method == 'PUT') {
      final id = path.split('/').last;
      final at = records.indexWhere((r) => r['id'] == id);
      final row = {
        ...records[at],
        ...body,
        'id': id,
        'value': '',
        'sealed': true,
        'sealedVersion': (body['expectedVersion'] as int) + 1,
      }..remove('expectedVersion');
      records[at] = row;
      return _json(row);
    }
    if (path.startsWith('/api/collections/records/records')) {
      if (request.method == 'GET') {
        return _json({'items': records});
      }
      if (request.method == 'POST') {
        final row = {
          ...body,
          'id': 'plain0000000001',
          'sealed': false,
          'sealedValue': '',
        };
        records.add(row);
        return _json(row);
      }
      final id = path.split('/').last;
      final at = records.indexWhere((r) => r['id'] == id);
      if (records[at]['sealed'] == true && body.containsKey('value')) {
        refusedPlainWrite = true;
        return http.Response('{}', 400);
      }
      records[at] = {...records[at], ...body};
      return _json(records[at]);
    }
    if (path.startsWith('/api/collections/sections/records')) {
      return _json({'items': const []});
    }
    return http.Response('{}', 404);
  }

  Map<String, dynamic> _row(
    Map<String, dynamic> body, {
    required int version,
  }) => {
    ...body,
    'value': '',
    'sealed': true,
    'sealedVersion': version,
    'user': _user,
  };

  static http.Response _json(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200);
}

Future<_Server> _start(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final server = _Server();
  await Stores.init(httpClient: MockClient(server.handle));
  await tester.pumpAndSettle();
  runInAction(
    () => Stores.auth.currentUser = User.fromJson({
      'id': _user,
      'email': 'ada@example.com',
      'activeWorkspace': _workspace,
    }),
  );
  return server;
}

Future<void> _setUpKeys() async {
  final keys = Stores.keys;
  await keys.load();
  keys.beginSetup();
  final groups = keys.recoveryCode!.split('-');
  keys.recoveryConfirm.text = groups.sublist(groups.length - 2).join('-');
  expect(await keys.finishRecovery(workspace: _workspace), isTrue);
}

Future<void> _pumpSection(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: const Scaffold(
        body: SingleChildScrollView(child: SealingSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('vault store', () {
    testWidgets('a sealed value never appears in any request', (tester) async {
      final server = await _start(tester);
      await tester.runAsync(() async {
        await _setUpKeys();
        expect(
          await Stores.vault.createRecord(
            key: 'smtp_password',
            value: _secret,
            label: 'SMTP password',
            type: 'text',
            format: 'hidden',
            user: _user,
            workspace: _workspace,
            sealed: true,
          ),
          isTrue,
        );
      });

      final sent = server.seen
          .map((r) => '${r.url} ${r.headers} ${r.body}')
          .join('\n');
      expect(sent, isNot(contains(_secret)));
      expect(server.records.single['value'], '');
      expect(Stores.vault.records.single.value, _secret);
    });

    testWidgets('it reads back decrypted after a fresh load', (tester) async {
      await _start(tester);
      await tester.runAsync(() async {
        await _setUpKeys();
        await Stores.vault.createRecord(
          key: 'smtp_password',
          value: _secret,
          label: 'SMTP password',
          type: 'text',
          format: 'hidden',
          user: _user,
          workspace: _workspace,
          sealed: true,
        );
        await Stores.vault.loadRecords();
      });
      final record = Stores.vault.records.single;
      expect(record.value, _secret);
      expect(record.isLocked, isFalse);
    });

    testWidgets(
      'an edit goes encrypted, and never through the collection API',
      (tester) async {
        final server = await _start(tester);
        await tester.runAsync(() async {
          await _setUpKeys();
          await Stores.vault.createRecord(
            key: 'smtp_password',
            value: _secret,
            label: 'SMTP password',
            type: 'text',
            format: 'hidden',
            user: _user,
            workspace: _workspace,
            sealed: true,
          );
          server.seen.clear();
          final id = Stores.vault.records.single.id;
          expect(
            await Stores.vault.updateRecord(id, {
              'value': '$_secret-new',
              'label': 'SMTP login',
            }),
            isTrue,
          );
        });

        expect(server.refusedPlainWrite, isFalse);
        final sent = server.seen.map((r) => r.body).join('\n');
        expect(sent, isNot(contains(_secret)));
        expect(server.seen.any((r) => r.method == 'PUT'), isTrue);
        final patch = server.seen.firstWhere((r) => r.method == 'PATCH');
        expect(jsonDecode(patch.body), {'label': 'SMTP login'});

        final record = Stores.vault.records.single;
        expect(record.value, '$_secret-new');
        expect(record.label, 'SMTP login');
        expect(record.sealedVersion, 2);
      },
    );

    testWidgets('a device without the key sees a locked record', (
      tester,
    ) async {
      final server = await _start(tester);
      await tester.runAsync(() async {
        await _setUpKeys();
        await Stores.vault.createRecord(
          key: 'smtp_password',
          value: _secret,
          label: 'SMTP password',
          type: 'text',
          format: 'hidden',
          user: _user,
          workspace: _workspace,
          sealed: true,
        );
        // A new device: same account, nothing on disk.
        FlutterSecureStorage.setMockInitialValues({});
        await Stores.init(httpClient: MockClient(server.handle));
        while (!Stores.auth.isInitialized) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();
      runInAction(
        () => Stores.auth.currentUser = User.fromJson({
          'id': _user,
          'email': 'ada@example.com',
          'activeWorkspace': _workspace,
        }),
      );
      await tester.runAsync(() => Stores.vault.loadRecords());

      expect(Stores.keys.status, SealingStatus.needsThisDevice);
      final record = Stores.vault.records.single;
      expect(record.isLocked, isTrue);
      expect(record.value, '');
    });

    testWidgets('duplicating an encrypted record starts encrypted', (
      tester,
    ) async {
      await _start(tester);
      Stores.vault.startRecordDraft(
        from: models.Record(
          id: 'a',
          key: 'k',
          value: 'v',
          label: 'l',
          type: 'text',
          format: 'default',
          user: _user,
          workspace: _workspace,
          sealed: true,
          opened: true,
        ),
      );
      expect(Stores.vault.recordSealed, isTrue);
    });

    testWidgets('a server without it touches nothing', (tester) async {
      final server = await _start(tester);
      server.supportsSealing = false;
      await tester.runAsync(() => Stores.keys.load());
      expect(Stores.keys.isAvailable, isFalse);
      expect(server.seen.where((r) => r.url.path.contains('sealed')), isEmpty);
    });
  });

  group('settings', () {
    testWidgets('offers to turn it on', (tester) async {
      await _start(tester);
      await tester.runAsync(() => Stores.keys.load());
      await _pumpSection(tester);
      expect(find.text('Turn on'), findsOneWidget);
    });

    testWidgets('the recovery key must be confirmed before anything saves', (
      tester,
    ) async {
      final server = await _start(tester);
      await tester.runAsync(() => Stores.keys.load());
      await _pumpSection(tester);

      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(find.text('Save your recovery key'), findsOneWidget);

      final code = Stores.keys.recoveryCode!;
      expect(find.text(code), findsOneWidget);

      // Nothing on the way out, whatever was tapped.
      await tester.tap(find.text('Turn on').last);
      await tester.pump();
      expect(server.devices, isEmpty);

      final groups = code.split('-');
      await tester.enterText(
        find.byType(TextField).last,
        groups.sublist(groups.length - 2).join('-'),
      );
      await tester.pump();
      expect(Stores.keys.recoveryConfirmMatches, isTrue);
    });

    testWidgets('lists this device once set up', (tester) async {
      await _start(tester);
      await tester.runAsync(_setUpKeys);
      await _pumpSection(tester);
      expect(find.text('Your devices'), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Recovery key'), findsOneWidget);
      expect(find.text('Add a device'), findsOneWidget);
    });

    testWidgets('a device not on the list can join or recover', (tester) async {
      final server = await _start(tester);
      await tester.runAsync(_setUpKeys);
      await tester.runAsync(() async {
        FlutterSecureStorage.setMockInitialValues({});
        await Stores.init(httpClient: MockClient(server.handle));
        while (!Stores.auth.isInitialized) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();
      runInAction(
        () => Stores.auth.currentUser = User.fromJson({
          'id': _user,
          'email': 'ada@example.com',
          'activeWorkspace': _workspace,
        }),
      );
      await tester.runAsync(() => Stores.keys.load());
      await _pumpSection(tester);
      expect(find.text('Add this device'), findsOneWidget);
      expect(find.text('Use your recovery key'), findsOneWidget);
      expect(find.text('Start over'), findsOneWidget);
    });
  });

  group('share picker', () {
    testWidgets('does not offer an encrypted record', (tester) async {
      await _start(tester);
      runInAction(() {
        Stores.vault.records = ObservableList.of([
          models.Record(
            id: 'p',
            key: 'plain_one',
            value: 'v',
            label: 'Plain one',
            type: 'text',
            format: 'default',
            user: _user,
            workspace: _workspace,
          ),
          models.Record(
            id: 's',
            key: 'sealed_one',
            value: 'v',
            label: 'Sealed one',
            type: 'text',
            format: 'default',
            user: _user,
            workspace: _workspace,
            sealed: true,
            opened: true,
          ),
        ]);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Observer(
                builder: (_) => ElevatedButton(
                  onPressed: () => openShareContentsPicker(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Plain one'), findsOneWidget);
      expect(find.text('Sealed one'), findsNothing);
    });
  });
}
