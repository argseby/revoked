import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/connection.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/vault/view/vault_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _me = 'user000000000aa';
const _workspace = 'wspace00000000a';

/// The vault as the server serves it: this person's own section, a record in
/// no section, and a section a colleague shared.
class _Server {
  final patched = <Map<String, dynamic>>[];
  bool ownShared = false;

  /// Adds a section made by signing in to a service.
  bool withSignIn = false;

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (path == '/api/collections/records/records') {
      return _json({
        'items': [
          {
            'id': 'record000000loose',
            'key': 'loose_note',
            'value': 'note',
            'label': 'Loose note',
            'type': 'text',
            'format': 'default',
            'user': _me,
            'workspace': _workspace,
          },
          {
            'id': 'record00000mine',
            'key': 'my_pin',
            'value': '1234',
            'label': 'My PIN',
            'type': 'text',
            'format': 'default',
            'user': _me,
            'workspace': _workspace,
          },
        ],
      });
    }
    if (path == '/api/collections/sections/records/section0000mine' &&
        request.method == 'PATCH') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      patched.add(body);
      ownShared = body['shared'] == true;
      return _json(_ownSection());
    }
    if (path == '/api/collections/sections/records') {
      return _json({
        'items': [
          _ownSection(),
          if (withSignIn)
            {
              'id': 'section00signin',
              'key': 'signin_shop',
              'name': 'Shop',
              'user': _me,
              'workspace': _workspace,
              'records': <String>[],
              'requestedBy': 'shop.example',
            },
        ],
      });
    }
    if (path == '/api/shared/vault') {
      return _json({
        'sections': [
          {
            'id': 'section000office',
            'key': 'office',
            'name': 'Office',
            'user': 'user000000000bb',
            'ownerEmail': 'bob@example.com',
            'workspace': _workspace,
            'records': ['record000000wifi'],
            'shared': true,
          },
        ],
        'records': [
          {
            'id': 'record000000wifi',
            'key': 'wifi',
            'value': 'hunter2',
            'label': 'Office Wi-Fi',
            'type': 'text',
            'format': 'default',
            'user': 'user000000000bb',
            'workspace': _workspace,
          },
        ],
      });
    }
    if (path == '/api/server') {
      return _json({
        'sealing': {'records': false},
      });
    }
    return _json({'items': []});
  }

  Map<String, dynamic> _ownSection() => {
    'id': 'section0000mine',
    'key': 'mine',
    'name': 'Mine',
    'user': _me,
    'workspace': _workspace,
    'records': ['record00000mine'],
    'shared': ownShared,
  };

  static http.Response _json(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200);
}

Future<_Server> _pump(WidgetTester tester, {bool withSignIn = false}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final server = _Server()..withSignIn = withSignIn;
  await Stores.init(httpClient: MockClient(server.handle));
  runInAction(
    () => Stores.auth.currentUser = User.fromJson({
      'id': _me,
      'email': 'ada@example.com',
      'activeWorkspace': _workspace,
    }),
  );
  await tester.runAsync(Stores.vault.loadRecords);
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: const Scaffold(body: VaultScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return server;
}

Finder _pane(String label) => find.descendant(
  of: find.byKey(
    ValueKey(
      'vault-section-${switch (label) {
        'Mine' => 'section0000mine',
        'Office' => 'section000office',
        'Shop' => 'section00signin',
        _ => '',
      }}',
    ),
  ),
  matching: find.text(label),
);

void main() {
  testWidgets('wide, the vault browses one section at a time', (tester) async {
    await _pump(tester);
    expect(find.text('Your vault'), findsOneWidget);
    expect(find.text('All items'), findsOneWidget);
    expect(_pane('Mine'), findsOneWidget);
    expect(_pane('Office'), findsOneWidget);
    expect(find.text('Not in a section'), findsOneWidget);
    expect(find.text('New section'), findsOneWidget);
    expect(find.text('My PIN'), findsOneWidget);
    expect(find.text('Loose note'), findsOneWidget);
    expect(find.text('1234'), findsNothing);
    expect(find.text('note'), findsNothing);
    expect(find.text('Only you'), findsNWidgets(2));
    // The section menu sits on a section's own header, not on All.
    expect(find.byTooltip('Section actions'), findsNothing);

    await tester.tap(_pane('Mine'));
    await tester.pumpAndSettle();
    expect(find.text('My PIN'), findsOneWidget);
    expect(find.text('Loose note'), findsNothing);
    expect(find.byTooltip('Section actions'), findsOneWidget);

    await tester.tap(find.text('Not in a section'));
    await tester.pumpAndSettle();
    expect(find.text('My PIN'), findsNothing);
    expect(find.text('Loose note'), findsOneWidget);

    await tester.tap(_pane('Office'));
    await tester.pumpAndSettle();
    expect(find.text('Office Wi-Fi'), findsOneWidget);
    expect(find.text('Shared by bob@example.com'), findsNWidgets(2));
  });

  testWidgets('a section a tool manages names the tool, not only its ID', (
    tester,
  ) async {
    await _pump(tester);
    runInAction(
      () => Stores.connections.connections = ObservableList.of([
        const Connection(
          id: 'conn0000claude1',
          clientId: 'https://claude.example',
          clientName: 'Claude Desktop',
          vaultAccess: 'write',
          section: 'section0000mine',
        ),
        const Connection(
          id: 'conn000reader01',
          clientId: 'https://reader.example',
          clientName: 'Notfallkarte',
          vaultAccess: 'read',
          sections: ['section0000mine'],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    // A plug instead of a folder, already in the pane.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('vault-section-section0000mine')),
        matching: find.byIcon(AppIcons.plug),
      ),
      findsOneWidget,
    );

    await tester.tap(_pane('Mine'));
    await tester.pumpAndSettle();
    // The badge beside the title and the row on top of the section.
    expect(find.text('Managed by Claude Desktop'), findsNWidgets(3));
    expect(
      find.text('Adds records here and changes only its own · ID conn00'),
      findsOneWidget,
    );
    expect(find.text('Read by Notfallkarte'), findsOneWidget);
  });

  testWidgets('a section from a sign-in says so in the pane and title', (
    tester,
  ) async {
    await _pump(tester, withSignIn: true);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('vault-section-section00signin')),
        matching: find.byIcon(AppIcons.globe),
      ),
      findsOneWidget,
    );

    await tester.tap(_pane('Shop'));
    await tester.pumpAndSettle();
    expect(find.text('Sign-in · shop.example'), findsNWidgets(2));
    expect(find.text('From signing in to shop.example'), findsOneWidget);
  });

  testWidgets('wide, the search narrows the selected records', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextFormField), 'loose');
    await tester.pumpAndSettle();
    expect(find.text('Loose note'), findsOneWidget);
    expect(find.text('My PIN'), findsNothing);
  });
  testWidgets(
    'sharing through a section updates access labels and the shared filter',
    (tester) async {
      await _pump(tester);
      runInAction(
        () => Stores.shares.shares.add(
          Link(
            id: 'link0000001',
            slug: 'payroll',
            label: 'Payroll',
            sections: ['section0000mine'],
            records: ['record00000mine'],
            user: _me,
            workspace: _workspace,
            status: 'active',
          ),
        ),
      );
      await tester.pumpAndSettle();
      // A link listing both the item and its section counts only once.
      expect(find.text('Shared · 1 link'), findsOneWidget);
      expect(find.text('Only you'), findsOneWidget);
      await tester.tap(find.text('Shared by you'));
      await tester.pumpAndSettle();
      expect(find.text('My PIN'), findsOneWidget);
      expect(find.text('Loose note'), findsNothing);
      await tester.tap(find.text('Shared by you'));
      await tester.pumpAndSettle();
      expect(find.text('Loose note'), findsOneWidget);
    },
  );

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 600.0, 1400.0]) {
      testWidgets(
        'populated vault fits $width in ${brightness.name} at 200% text',
        (tester) async {
          await _pump(tester);
          tester.view.physicalSize = Size(width, 1200);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(brightness),
              home: const Scaffold(body: VaultScreen()),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(_pane('Office'));
          await tester.tap(_pane('Office'));
          await tester.pumpAndSettle();
          expect(find.text('Office Wi-Fi'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
