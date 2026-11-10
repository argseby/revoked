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

/// The vault as the server serves it: this person's own section, and one a
/// colleague shared.
class _Server {
  final patched = <Map<String, dynamic>>[];
  final queries = <String, Map<String, String>>{};
  String ownAudience = 'private';
  String ownEditing = 'owner';

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    queries[path] = request.url.queryParameters;
    if (path == '/api/access/sections/section0000mine') {
      final shared = ownAudience != 'private';
      return _json({
        'collection': 'sections',
        'id': 'section0000mine',
        'owner': {'id': _me, 'email': 'ada@example.com'},
        'readers': {'count': shared ? 3 : 1},
        'editors': {'count': shared && ownEditing == 'audience' ? 2 : 1},
        'canEdit': true,
        'canChangeAudience': true,
        'audience': {'kind': ownAudience, 'groups': [], 'editing': ownEditing},
      });
    }
    if (path == '/api/collections/records/records') {
      return _json({
        'items': [
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
      ownAudience = body['audienceKind'] as String? ?? ownAudience;
      ownEditing = body['editing'] as String? ?? ownEditing;
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
            'audienceKind': 'workspace',
            'editing': 'owner',
            'canEdit': false,
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
    'shared': ownAudience == 'workspace',
    'audienceKind': ownAudience,
    'editing': ownEditing,
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
  return server;
}

void main() {
  testWidgets('a colleague\'s shared section shows, read-only', (tester) async {
    await _pump(tester);
    expect(find.text('Office'), findsOneWidget);
    expect(find.text('Shared by bob@example.com'), findsOneWidget);
    expect(find.text('Office Wi-Fi'), findsOneWidget);

    await tester.tap(find.text('Office Wi-Fi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Only they can change it'), findsOneWidget);
    // In the row's preview and in the sheet.
    expect(find.text('hunter2'), findsNWidgets(2));
    expect(find.text('Copy value'), findsOneWidget);
    // Nothing here edits or deletes it.
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('only own items are listed from the collections', (tester) async {
    final server = await _pump(tester);
    for (final coll in ['records', 'sections']) {
      expect(
        server.queries['/api/collections/$coll/records']?['filter'],
        'user = "$_me"',
      );
    }
  });

  testWidgets('an own section is opened to the workspace from its access', (
    tester,
  ) async {
    final server = await _pump(tester);
    await tester.tap(find.byTooltip('Section actions'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Visibility'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Visibility of "Mine"'), findsOneWidget);
    expect(
      find.text('Seen by the owner only · changed by the owner only.'),
      findsOneWidget,
    );

    // The audience tags behind the sheet say Workspace too; the sheet's
    // option is the last.
    await tester.tap(find.text('Workspace').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Members who manage the vault'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save visibility'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(server.patched, [
      {
        'audienceKind': 'workspace',
        'editing': 'audience',
        'audienceGroups': [],
      },
    ]);
    expect(find.text('Members'), findsOneWidget);
  });
}
