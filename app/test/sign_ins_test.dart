import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/sign_in_service.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A service you signed in to stays findable: what it learned, and the entries
/// it may read, which you can take back from here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const signInsPath = '/api/collections/signIns/records';
  const linksPath = '/api/collections/links/records';

  const sizes = {
    'small phone': Size(320, 640),
    'phone': Size(375, 812),
    'phone on its side': Size(812, 375),
    'tablet': Size(768, 1024),
    'desktop': Size(1280, 800),
  };

  late List<Map<String, dynamic>> signIns;
  late List<Map<String, dynamic>> links;
  late int signInStatus;
  late List<String> revoked;

  Map<String, dynamic> signIn(
    String id,
    String origin, {
    String link = '',
    List<String> scopes = const ['email'],
  }) => {
    'id': id,
    'clientId': origin,
    'scopes': scopes,
    'link': link,
    'lastSignInAt': '2026-11-01 10:00:00.000Z',
    'created': '2026-10-01 10:00:00.000Z',
  };

  Map<String, dynamic> link(String id, String origin) => {
    'id': id,
    'slug': 's_$id',
    'label': 'Sign-in at $origin',
    'records': ['r1', 'r2'],
    'sections': <String>[],
    'status': 'active',
    'signInClient': origin,
  };

  Future<http.Response> server(http.Request request) async {
    http.Response json(Object body, [int code = 200]) => http.Response(
      jsonEncode(body),
      code,
      headers: {'content-type': 'application/json'},
      request: request,
    );
    final path = request.url.path;
    if (path == signInsPath && request.method == 'GET') {
      if (signInStatus != 200) return json({'message': 'Nope'}, signInStatus);
      return json({'items': signIns});
    }
    if (path.startsWith('$linksPath/') && request.method == 'PATCH') {
      final id = path.split('/').last;
      revoked.add(id);
      final row = links.firstWhere((l) => l['id'] == id);
      row['status'] = 'revoked';
      return json(row);
    }
    if (path == linksPath && request.method == 'GET') {
      final filter = request.url.queryParameters['filter'] ?? '';
      return json({'items': filter.contains('signInClient') ? links : []});
    }
    if (path.startsWith('/api/collections/')) {
      return json({'items': [], 'page': 1, 'totalPages': 1});
    }
    return json({}, 404);
  }

  Future<GoRouter> signedIn(
    WidgetTester tester, {
    Size size = const Size(1280, 1000),
  }) async {
    tester.view.physicalSize = size;
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
    return router;
  }

  setUp(() {
    signIns = [
      signIn('s1', 'https://game.example', link: 'l1'),
      signIn('s2', 'https://shop.example:8443', scopes: const []),
    ];
    links = [link('l1', 'https://game.example')];
    signInStatus = 200;
    revoked = [];
  });

  testWidgets('sign-ins are listed even with no tools connected', (
    tester,
  ) async {
    final router = await signedIn(tester);
    router.go(AppRoutes.connectedTools);
    await tester.pumpAndSettle();

    expect(find.text('No tools connected'), findsOneWidget);
    expect(find.text('Services you signed in to'), findsOneWidget);
    expect(find.text('game.example'), findsOneWidget);
    expect(find.text('shop.example:8443'), findsOneWidget);
    expect(
      find.text('Sharing entries · last signed in 2026-11-01'),
      findsOneWidget,
    );
  });

  testWidgets('with nothing at all, the page explains tools as before', (
    tester,
  ) async {
    signIns = [];
    links = [];
    final router = await signedIn(tester);
    router.go(AppRoutes.connectedTools);
    await tester.pumpAndSettle();

    expect(
      find.text('Let tools help, without opening your vault'),
      findsOneWidget,
    );
    expect(find.text('Services you signed in to'), findsNothing);
  });

  testWidgets('a server without the list shows the page as before', (
    tester,
  ) async {
    signInStatus = 404;
    final router = await signedIn(tester);
    router.go(AppRoutes.connectedTools);
    await tester.pumpAndSettle();

    expect(
      find.text('Let tools help, without opening your vault'),
      findsOneWidget,
    );
    expect(Stores.signIns.loadState.error, isNull);
  });

  testWidgets('a failed load says so rather than showing nothing', (
    tester,
  ) async {
    signInStatus = 500;
    final router = await signedIn(tester);
    router.go(AppRoutes.connectedTools);
    await tester.pumpAndSettle();

    expect(find.text('Couldn’t load your sign-ins'), findsOneWidget);
  });

  testWidgets('a service shows what it learned, and its link can be revoked', (
    tester,
  ) async {
    final router = await signedIn(tester);
    router.go(AppRoutes.signInServiceFor('s1'));
    await tester.pumpAndSettle();

    expect(find.text('To sign out, go to game.example.'), findsOneWidget);
    expect(find.text('That it is you'), findsOneWidget);
    expect(find.text('Your email address'), findsOneWidget);
    expect(find.text('Your name'), findsNothing);
    expect(find.text('active · 2 entries'), findsOneWidget);

    await tester.tap(find.text('Sign-in at https://game.example'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Revoke').hitTestable());
    await tester.pumpAndSettle();

    expect(revoked, ['l1']);
    expect(find.text('revoked · 2 entries'), findsOneWidget);
    expect(
      find.text('game.example can’t read these entries any more.'),
      findsOneWidget,
    );
  });

  testWidgets('a service shows the name it gets, and where to change it', (
    tester,
  ) async {
    final router = await signedIn(tester);
    runInAction(
      () => Stores.signIns.services
        ..clear()
        ..add(
          SignInService.fromJson({
            'id': 's9',
            'clientId': 'https://game.example',
            'scopes': ['profile'],
            'nameRecord': 'r1',
            'expand': {
              'nameRecord': {'value': 'xXAdaXx'},
            },
          }),
        ),
    );
    router.go(AppRoutes.signInServiceFor('s9'));
    await tester.pump();

    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('xXAdaXx'), findsOneWidget);
    await tester.tap(find.text('xXAdaXx'));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.toString(),
      AppRoutes.recordDetailFor('r1'),
    );
  });

  testWidgets('a service that got no entries says so', (tester) async {
    final router = await signedIn(tester);
    router.go(AppRoutes.signInServiceFor('s2'));
    await tester.pumpAndSettle();

    expect(find.text('You didn’t share any entries'), findsOneWidget);
    expect(find.text('Open link'), findsNothing);
  });

  testWidgets('a link in another workspace is pointed at, not hidden', (
    tester,
  ) async {
    links = [];
    final router = await signedIn(tester);
    router.go(AppRoutes.signInServiceFor('s1'));
    await tester.pumpAndSettle();

    expect(
      find.text('Shared from another workspace. Switch workspace to see it.'),
      findsOneWidget,
    );
  });

  testWidgets('sign-ins leave with the workspace they were loaded for', (
    tester,
  ) async {
    final router = await signedIn(tester);
    router.go(AppRoutes.connectedTools);
    await tester.pumpAndSettle();
    expect(Stores.signIns.services, isNotEmpty);

    Stores.forgetWorkspaceData();

    expect(Stores.signIns.services, isEmpty);
    expect(Stores.signIns.links, isEmpty);
  });

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('the list and a service fit a $name', (tester) async {
      final router = await signedIn(tester, size: size);
      for (final page in [
        AppRoutes.connectedTools,
        AppRoutes.signInServiceFor('s1'),
        AppRoutes.signInServiceFor('s2'),
      ]) {
        router.go(page);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: page);
      }
    });
  }
}
