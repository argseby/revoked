import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/user.dart';
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
        'items': [_ownSection()],
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

Future<_Server> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final server = _Server();
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

Finder _pane(String label) =>
    find.descendant(of: find.byType(ListView), matching: find.text(label));

void main() {
  testWidgets('wide, the vault browses one section at a time', (tester) async {
    await _pump(tester);
    expect(_pane('All records'), findsOneWidget);
    expect(_pane('Mine'), findsOneWidget);
    expect(_pane('Office'), findsOneWidget);
    expect(_pane('Not in a section'), findsOneWidget);
    expect(_pane('Section'), findsOneWidget);
    expect(find.text('My PIN'), findsOneWidget);
    expect(find.text('Loose note'), findsOneWidget);
    // The section menu sits on a section's own header, not on All.
    expect(find.byTooltip('Section actions'), findsNothing);

    await tester.tap(_pane('Mine'));
    await tester.pumpAndSettle();
    expect(find.text('My PIN'), findsOneWidget);
    expect(find.text('Loose note'), findsNothing);
    expect(find.byTooltip('Section actions'), findsOneWidget);

    await tester.tap(_pane('Not in a section'));
    await tester.pumpAndSettle();
    expect(find.text('My PIN'), findsNothing);
    expect(find.text('Loose note'), findsOneWidget);

    await tester.tap(_pane('Office'));
    await tester.pumpAndSettle();
    expect(find.text('Office Wi-Fi'), findsOneWidget);
    expect(find.text('Shared by bob@example.com'), findsOneWidget);
  });

  testWidgets('wide, the search narrows the selected records', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextFormField), 'loose');
    await tester.pumpAndSettle();
    expect(find.text('Loose note'), findsOneWidget);
    expect(find.text('My PIN'), findsNothing);
  });
}
