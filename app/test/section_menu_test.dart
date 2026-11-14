import 'dart:convert';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/vault/view/vault_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _me = 'user000000000aa';
const _workspace = 'wspace00000000a';

Future<http.Response> _handle(http.Request request) async {
  http.Response json(Object body) => http.Response(jsonEncode(body), 200);
  return switch (request.url.path) {
    '/api/collections/sections/records' => json({
      'items': [
        {
          'id': 'section0000mine',
          'key': 'payroll',
          'name': 'Payroll',
          'user': _me,
          'workspace': _workspace,
          'records': <String>[],
          'audienceKind': 'private',
          'editing': 'owner',
        },
      ],
    }),
    '/api/shared/vault' => json({
      'sections': [
        {
          'id': 'section000office',
          'key': 'office',
          'name': 'Office',
          'user': 'user000000000bb',
          'ownerEmail': 'bob@example.com',
          'workspace': _workspace,
          'records': <String>[],
          'shared': true,
          'audienceKind': 'workspace',
          'editing': 'owner',
          'canEdit': false,
        },
      ],
      'records': <Object>[],
    }),
    '/api/server' => json({
      'sealing': {'records': false},
    }),
    _ => json({'items': <Object>[]}),
  };
}

void main() {
  String? copied;

  setUp(() {
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(httpClient: MockClient(_handle));
    runInAction(
      () => Stores.auth.currentUser = User.fromJson({
        'id': _me,
        'email': 'ada@example.com',
        'activeWorkspace': _workspace,
      }),
    );
    await tester.runAsync(Stores.vault.loadRecords);
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: const Scaffold(body: VaultScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tile(String id) => find.byKey(ValueKey('vault-section-$id'));

  Future<void> copyId(
    WidgetTester tester,
    String id, {
    required bool rightClick,
  }) async {
    if (rightClick) {
      await tester.tap(tile(id), buttons: kSecondaryButton);
    } else {
      await tester.longPress(tile(id));
    }
    await tester.pumpAndSettle();
    expect(find.text('Copy key'), findsNothing);
    await tester.tap(find.text('Copy ID (API)'));
    await tester.pumpAndSettle();
  }

  testWidgets('a section\'s context menu copies its id', (tester) async {
    await pump(tester);
    await tester.tap(tile('section0000mine'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    for (final label in ['Rename', 'Copy ID (API)', 'Delete']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await copyId(tester, 'section0000mine', rightClick: true);
    expect(copied, 'section0000mine');
    copied = null;
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await copyId(tester, 'section0000mine', rightClick: false);
    expect(copied, 'section0000mine');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a colleague\'s section offers only its id', (tester) async {
    await pump(tester);
    await tester.longPress(tile('section000office'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
    await tester.tap(find.text('Copy ID (API)'));
    await tester.pumpAndSettle();
    expect(copied, 'section000office');
  });

  testWidgets('the open section shows its key', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('vault-section-key')), findsNothing);
    await tester.tap(tile('section0000mine'));
    await tester.pumpAndSettle();
    final key = find.byKey(const ValueKey('vault-section-key'));
    expect(key, findsOneWidget);
    expect(
      find.descendant(of: key, matching: find.text('payroll')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Section actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy ID (API)').last);
    await tester.pumpAndSettle();
    expect(copied, 'section0000mine');
  });
}
