import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A connected tool can be paused, activated again and disconnected, with or
/// without its links, and its page shows everything its proposals became.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const toolsPath = '/api/collections/connections/records';
  const linksPath = '/api/collections/links/records';

  late Map<String, dynamic> tool;
  late List<String> calls;
  late bool routesExist;
  late bool withRows;
  late bool filtersByTool;

  Future<http.Response> server(http.Request request) async {
    http.Response json(Object body, [int code = 200]) => http.Response(
      jsonEncode(body),
      code,
      headers: {'content-type': 'application/json'},
      request: request,
    );
    final path = request.url.path;
    if (path.startsWith('/api/connections/c1/')) {
      if (!routesExist) return json({'message': 'Not found'}, 404);
      final action = path.split('/').last;
      calls.add('$action ${request.body}');
      if (action == 'permissions') {
        final changed = jsonDecode(request.body) as Map<String, dynamic>;
        tool.addAll(changed);
        return json(changed);
      }
      tool['paused'] = action == 'pause';
      return json({});
    }
    if (path == '/api/permissions') {
      Map<String, dynamic> p(String key, String label, List<String> scopes) => {
        'key': key,
        'label': label,
        'description': '',
        'scopes': scopes,
      };
      return json({
        'permissions': [
          p('vault:read', 'Read vault', ['record:read', 'section:read'])
            ..['membersOnly'] = true,
          p('shares:read', 'View shares', ['link:read']),
          p('shares:manage', 'Manage shares', [
            'link:create',
            'link:update',
            'link:delete',
          ]),
          p('members:add', 'Invite members', ['workspaceMembers:create']),
        ],
      });
    }
    if (path == '/api/collections/sections/records') {
      Map<String, dynamic> section(String id, String name) => {
        'id': id,
        'key': id,
        'name': name,
        'records': <String>[],
        'user': 'u1',
        'workspace': 'w1',
      };
      return json({
        'items': [
          section('s1', 'Flat tool'),
          section('s2', 'Documents'),
          section('s3', 'Travel'),
        ],
        'page': 1,
        'totalPages': 1,
      });
    }
    if (path == '$toolsPath/c1' && request.method == 'DELETE') {
      calls.add('delete');
      return http.Response('', 204, request: request);
    }
    if (path == toolsPath) {
      return json({
        'items': [tool],
      });
    }
    if (path == linksPath &&
        request.url.queryParameters['filter'] == 'connection != ""') {
      return json({
        'items': [
          {
            'id': 'l1',
            'slug': 's_l1',
            'label': 'Flat 1',
            'records': ['r1'],
            'sections': <String>[],
            'status': tool['paused'] == true ? 'paused' : 'active',
            'connection': 'c1',
          },
        ],
      });
    }
    final fromTool =
        request.url.queryParameters['filter'] == 'connection != ""';
    final rows = <String, Map<String, dynamic>>{
      '/api/collections/requests/records': {
        'id': 'q1',
        'slug': 'q_1',
        'label': 'New starters',
        'status': 'active',
        'responseCount': 2,
        'connection': 'c1',
      },
      '/api/collections/attestations/records': {
        'id': 'a1',
        'type': 'membership',
        'status': 'offered',
        'offerExpiresAt': '2099-01-01 00:00:00.000Z',
        'connection': 'c1',
      },
      '/api/collections/attestationChecks/records': {
        'id': 'k1',
        'type': 'over_18',
        'status': 'open',
        'expiresAt': '2099-01-01 00:00:00.000Z',
        'connection': 'c1',
      },
    };
    if (fromTool && rows.containsKey(path)) {
      if (!filtersByTool) return json({'message': 'Bad filter'}, 400);
      return json({
        'items': [if (withRows) rows[path]],
      });
    }
    if (path.startsWith('/api/collections/')) {
      return json({'items': [], 'page': 1, 'totalPages': 1});
    }
    return json({}, 404);
  }

  Future<GoRouter> signedIn(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(httpClient: MockClient(server));
    runInAction(() => Stores.auth.currentUser = null);
    final router = AppRouter.create(Stores.auth);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    runInAction(
      () => Stores.auth.currentUser = User.fromJson({
        'id': 'u1',
        'email': 'ada@example.com',
        'activeWorkspace': 'w1',
      }),
    );
    await tester.pumpAndSettle();
    router.go(AppRoutes.connectedToolFor('c1'));
    await tester.pumpAndSettle();
    return router;
  }

  setUp(() {
    tool = {
      'id': 'c1',
      'clientId': 'https://tool.example',
      'clientName': 'Flat tool',
      'expiresAt': '2099-01-01 00:00:00.000Z',
    };
    calls = [];
    routesExist = true;
    withRows = false;
    filtersByTool = true;
  });

  testWidgets('its page lists the requests, attestations and checks it '
      'proposed', (tester) async {
    withRows = true;
    await signedIn(tester);

    expect(find.text('Requests from Flat tool'), findsOneWidget);
    expect(find.text('New starters'), findsOneWidget);
    expect(find.text('2 responses'), findsOneWidget);
    expect(find.text('Attestations from Flat tool'), findsOneWidget);
    expect(find.text('membership'), findsOneWidget);
    expect(find.text('Offered'), findsOneWidget);
    expect(find.text('Checks from Flat tool'), findsOneWidget);
    expect(find.text('over_18'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);

    await tester.ensureVisible(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Its request stops accepting answers.'),
      findsOneWidget,
    );
  });

  testWidgets('reading the vault shows while it is on, and can only be '
      'turned off', (tester) async {
    await signedIn(tester);
    expect(find.text('Read vault'), findsNothing);

    tool['allowVaultRead'] = true;
    await Stores.connections.load();
    await tester.pumpAndSettle();
    expect(find.text('Vault read access'), findsOneWidget);
    await tester.ensureVisible(find.text('Read vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read vault'));
    await tester.pumpAndSettle();
    expect(calls, ['permissions {"allowVaultRead":false}']);
    expect(find.text('Read vault'), findsNothing);
  });

  testWidgets('what it does on its own comes from the catalogue, and '
      'changes one at a time', (tester) async {
    tool['scopes'] = ['link:create', 'link:update', 'link:delete'];
    await signedIn(tester);

    // Only what a tool does by itself is offered here.
    expect(find.text('Invite members'), findsNothing);
    expect(find.text('View shares'), findsNothing);
    await tester.ensureVisible(find.text('Manage shares'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage shares'));
    await tester.pumpAndSettle();
    expect(calls, ['permissions {"permissions":[]}']);
  });

  testWidgets('its section can be made read only, and taken away and given '
      'back', (tester) async {
    tool['vaultAccess'] = 'write';
    tool['section'] = 's1';
    await signedIn(tester);
    await Stores.vault.loadRecords();
    await tester.pumpAndSettle();

    expect(find.text('Its own'), findsOneWidget);
    await tester.ensureVisible(find.text('Read'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    expect(calls.last, 'permissions {"permissions":["vault:read"]}');

    await tester.ensureVisible(find.text('Its own'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Its own'));
    await tester.pumpAndSettle();
    expect(calls.last, 'permissions {"section":false}');
  });

  testWidgets('every section has a switch, its own first, and one you '
      'added can be switched off', (tester) async {
    tool['vaultAccess'] = 'write';
    tool['section'] = 's1';
    tool['sections'] = ['s2'];
    await signedIn(tester);
    await Stores.vault.loadRecords();
    await tester.pumpAndSettle();

    expect(find.text('Vault sections'), findsOneWidget);
    expect(find.text('Its own'), findsOneWidget);
    expect(find.text('Manage · 0 records'), findsOneWidget);
    expect(find.text('Read · 0 records'), findsOneWidget);
    expect(find.text('Travel'), findsOneWidget);

    await tester.ensureVisible(find.text('Documents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();
    expect(calls, ['permissions {"sections":[]}']);

    await tester.ensureVisible(find.text('Travel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Travel'));
    await tester.pumpAndSettle();
    expect(calls.last, 'permissions {"sections":["s3"]}');
  });

  testWidgets('a tool with only links shows no empty sections', (tester) async {
    await signedIn(tester);

    expect(find.text('Flat 1'), findsOneWidget);
    expect(find.text('Requests from Flat tool'), findsNothing);
    expect(find.text('Attestations from Flat tool'), findsNothing);
    expect(find.text('Checks from Flat tool'), findsNothing);
  });

  testWidgets('an older server still shows the tool\'s links', (tester) async {
    filtersByTool = false;
    await signedIn(tester);

    expect(find.text('Flat 1'), findsOneWidget);
    expect(find.text('Requests from Flat tool'), findsNothing);
  });

  testWidgets('pausing says what stops, and activating brings it back', (
    tester,
  ) async {
    await signedIn(tester);

    await tester.ensureVisible(find.text('Active'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle();
    expect(calls, ['pause {}']);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.textContaining('has no access while paused'), findsOneWidget);

    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle();
    expect(calls.last, 'resume {}');
    expect(find.text('Paused'), findsNothing);
  });

  testWidgets('disconnecting leaves the links unless you tick the box', (
    tester,
  ) async {
    await signedIn(tester);

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(find.text('Revoke its links too'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Disconnect').hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(calls, ['disconnect {"revokeLinks":false}']);
  });

  testWidgets('disconnecting can take the links with it', (tester) async {
    await signedIn(tester);

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke its links too'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Disconnect').hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(calls, ['disconnect {"revokeLinks":true}']);
  });

  testWidgets('an older server is still disconnected the way it knows', (
    tester,
  ) async {
    routesExist = false;
    await signedIn(tester);

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Disconnect').hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(calls, ['delete']);
  });

  testWidgets('an older server can\'t pretend to revoke the links', (
    tester,
  ) async {
    routesExist = false;
    await signedIn(tester);

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke its links too'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Disconnect').hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.text('The tool could not be disconnected'), findsOneWidget);
  });
}
