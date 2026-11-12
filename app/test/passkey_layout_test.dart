import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/crypto/sealing.dart';
import 'package:revoked_app/core/models/passkey.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart';
import 'package:revoked_app/features/settings/view/settings_pages.dart';
import 'package:revoked_app/features/vault/view/record_create_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A device the list doesn't name, on an account whose passkey holds the key:
/// the state the vault's banner and the encryption settings now speak to. It
/// has to fit every window, and say how to get in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const user = 'u1';
  const sizes = {
    'small phone': Size(320, 640),
    'phone': Size(375, 812),
    'phone on its side': Size(812, 375),
    'tablet': Size(768, 1024),
    'desktop': Size(1280, 800),
  };

  List<Map<String, dynamic>> listWithPasskey() {
    final device = Sealing.generateKeyPair();
    final secret = Sealing.randomBytes(32);
    final signing = PasskeyKeys.signingKey(secret);
    final first = DeviceChainEntry.sign(
      user: user,
      seq: 1,
      action: DeviceChainEntry.actionAdd,
      kind: DeviceChainEntry.kindDevice,
      label: 'Linux computer',
      hpkePublicKey: Sealing.generateKeyPair().publicKey,
      signingPublicKey: device.publicKey,
      targetSeq: 0,
      previousHash: Uint8List(0),
      signerSeq: 1,
      signer: device,
    );
    final passkey = DeviceChainEntry.sign(
      user: user,
      seq: 2,
      action: DeviceChainEntry.actionAdd,
      kind: DeviceChainEntry.kindPasskey,
      label: 'Chrome on Mac',
      credentialId: 'cred-1',
      hpkePublicKey: PasskeyKeys.hpkeKey(secret).publicKey,
      signingPublicKey: signing.publicKey,
      targetSeq: 0,
      previousHash: first.hash,
      signerSeq: 1,
      signer: device,
      anchorSignature: Sealing.sign(
        signing,
        SealedFormats.passkeyAnchorPayload(user, first.hash, 'cred-1'),
      ),
    );
    return [
      for (final e in [first, passkey]) {...e.toJson(), 'user': user},
    ];
  }

  Future<GoRouter> signedIn(
    WidgetTester tester,
    Size size,
    http.Client client,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(httpClient: client);
    runInAction(() => Stores.auth.currentUser = null);
    final router = AppRouter.create(Stores.auth);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    runInAction(
      () => Stores.auth.currentUser = User.fromJson({
        'id': user,
        'email': 'ada@example.com',
        'activeWorkspace': 'w1',
      }),
    );
    await tester.pumpAndSettle();
    return router;
  }

  http.Response json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  /// A server for a device the list does not name.
  http.Client lockedServer() {
    final devices = listWithPasskey();
    return MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/server') {
        return http.Response(
          jsonEncode({
            'sealing': {'records': true},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path == '/api/sealed/state') {
        return http.Response(
          jsonEncode({'devices': devices, 'workspaces': <Object>[]}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.startsWith('/api/collections/')) {
        // One record this device cannot read, which is what such a device
        // has: it is why the person is here.
        final items = path.endsWith('/records/records')
            ? [
                {
                  'id': 'record000000001',
                  'key': 'smtp_password',
                  'label': 'SMTP password',
                  'type': 'text',
                  'format': 'default',
                  'user': user,
                  'workspace': 'w1',
                  'value': '',
                  'sealed': true,
                  'sealedValue': 'AQ',
                  'sealedVersion': 1,
                  'keyEpoch': 1,
                  'keyWrap': 'AQ',
                },
              ]
            : <Object>[];
        return http.Response(
          jsonEncode({'items': items, 'totalItems': items.length}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });
  }

  /// A server that keeps what a device sends it, for a device that sets
  /// encryption up itself. [record] is served once the test has sealed one.
  http.Client honestServer(Map<String, dynamic>? Function() record) {
    final devices = <Map<String, dynamic>>[];
    final epochs = <Map<String, dynamic>>[];
    final wraps = <Map<String, dynamic>>[];
    return MockClient((request) async {
      final path = request.url.path;
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map<String, dynamic>;
      if (path == '/api/server') {
        return json({
          'sealing': {'records': true},
        });
      }
      if (path == '/api/sealed/state') {
        return json({
          'devices': devices,
          'workspaces': epochs.isEmpty
              ? <Object>[]
              : [
                  {'workspace': 'w1', 'epochs': epochs, 'wraps': wraps},
                ],
        });
      }
      if (path == '/api/sealed/devices') {
        for (final e in body['entries'] as List<dynamic>) {
          devices.add({...e as Map<String, dynamic>, 'user': user});
        }
        for (final w in body['wraps'] as List<dynamic>? ?? const []) {
          wraps.add(w as Map<String, dynamic>);
        }
        return json({'ok': true});
      }
      if (path.endsWith('/epochs')) {
        epochs.add({
          'epoch': body['epoch'],
          'priorWrap': body['priorWrap'],
          'rotationDue': false,
        });
        for (final w in body['wraps'] as List<dynamic>) {
          wraps.add(w as Map<String, dynamic>);
        }
        return json({'ok': true});
      }
      if (path.startsWith('/api/collections/')) {
        final sealed = record();
        final items = path.endsWith('/records/records') && sealed != null
            ? [sealed]
            : <Object>[];
        return json({'items': items, 'totalItems': items.length});
      }
      return http.Response('{}', 404);
    });
  }

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('a locked device is shown the way in, on a $name', (
      tester,
    ) async {
      final router = await signedIn(tester, size, lockedServer());

      router.go(AppRoutes.vault);
      await tester.pumpAndSettle();
      // The list's load starts the keys' load, which settles on its own.
      await Stores.keys.ensureLoaded();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'vault');
      expect(
        Stores.keys.status,
        SealingStatus.needsThisDevice,
        reason: Stores.keys.errorMessage,
      );
      expect(
        find.text('Encrypted records cannot be read on this device yet.'),
        findsOneWidget,
      );
      expect(find.text('Add this device'), findsWidgets);

      expect(find.text('Not readable on this device'), findsOneWidget);

      router.go(AppRoutes.recordDetailFor('record000000001'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'record');
      expect(find.text('Not readable on this device'), findsOneWidget);
      expect(find.text('Add this device'), findsOneWidget);
      expect(find.text('Who can read this'), findsOneWidget);
      expect(find.text('Chrome on Mac'), findsOneWidget);

      router.go(AppRoutes.settingsPage(SettingsPage.encryption.slug));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'encryption settings');
      expect(find.textContaining('Chrome on Mac'), findsOneWidget);
      expect(find.text('Sign in with your passkey'), findsOneWidget);
      expect(find.text('Add this device'), findsOneWidget);
    });
  }
  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets(
      'a device that holds the key sees where its records open, on a $name',
      (tester) async {
        Map<String, dynamic>? sealed;
        final router = await signedIn(tester, size, honestServer(() => sealed));
        final keys = Stores.keys;
        await keys.offerPasskeySignIn(
          PasskeySignIn(
            user: user,
            credentialId: 'cred-1',
            name: 'Chrome on Linux',
            secret: Sealing.randomBytes(32),
            asked: true,
          ),
        );
        await keys.load();
        keys.beginSetup();
        final groups = keys.recoveryCode!.split('-');
        keys.recoveryConfirm.text = groups.sublist(groups.length - 2).join('-');
        expect(await keys.finishRecovery(workspace: 'w1'), isTrue);
        expect(keys.status, SealingStatus.ready, reason: keys.errorMessage);
        final payload = keys.sealValue(
          workspace: 'w1',
          record: 'record000000001',
          recordKey: 'smtp_password',
          version: 1,
          value: 'hunter2',
          label: 'SMTP password',
        );
        sealed = {
          'id': 'record000000001',
          'key': 'smtp_password',
          'label': 'SMTP password',
          'type': 'text',
          'format': 'default',
          'user': user,
          'workspace': 'w1',
          'value': '',
          'sealed': true,
          'sealedValue': payload.sealedValue,
          'sealedVersion': 1,
          'keyEpoch': payload.keyEpoch,
          'keyWrap': payload.keyWrap,
        };

        router.go(AppRoutes.settingsPage(SettingsPage.encryption.slug));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'encryption settings');
        expect(find.text('Where encrypted records open'), findsOneWidget);
        expect(find.text('Other people in your workspace'), findsOneWidget);
        expect(find.textContaining('Chrome on Linux'), findsWidgets);
        expect(find.text('Passkey not connected'), findsNothing);

        router.go(AppRoutes.vault);
        await tester.pumpAndSettle();
        await Stores.vault.loadRecords();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'vault');
        expect(find.text('hunter2'), findsOneWidget);

        router.go(AppRoutes.recordDetailFor('record000000001'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'record');
        expect(find.text('Who can read this'), findsOneWidget);
        expect(find.text('This device'), findsOneWidget);
        expect(find.text('Chrome on Linux'), findsOneWidget);

        // The create sheet says where a new value will be readable before
        // it is saved.
        openRecordCreateSheet(
          context: tester.element(find.byType(Scaffold).first),
          store: Stores.vault,
          authStore: Stores.auth,
        );
        await tester.pumpAndSettle();
        Stores.vault.setRecordSealed(true);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'create sheet');
        final note = find.text('Opens on your devices');
        await tester.scrollUntilVisible(
          note,
          120,
          // The sheet's own list; each text field in it scrolls too.
          scrollable: find
              .ancestor(
                of: find.text('Details'),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(note, findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'create sheet note');
      },
    );
  }
}
