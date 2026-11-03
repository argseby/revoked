import 'dart:convert';

import 'package:flutter/material.dart';
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
      tool['paused'] = action == 'pause';
      return json({});
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

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Its request stops taking answers.'),
      findsOneWidget,
    );
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

    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(calls, ['pause {}']);
    expect(find.text('Paused'), findsOneWidget);
    expect(
      find.textContaining('can’t do anything while it’s paused'),
      findsOneWidget,
    );

    await tester.tap(find.text('Activate'));
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
    expect(find.text('Couldn’t disconnect'), findsOneWidget);
  });
}
