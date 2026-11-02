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
/// without its links.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const toolsPath = '/api/collections/connections/records';
  const linksPath = '/api/collections/links/records';

  late Map<String, dynamic> tool;
  late List<String> calls;
  late bool routesExist;

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
