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
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _me = 'user000000000aa';
const _colleague = 'user000000000bb';
const _workspace = 'wspace00000000a';

/// Shares and requests as the server serves them since they carry an
/// audience (VISIBILITY.md): this person's own, and a colleague's opened to
/// them, told apart by the `user` filter the app sends.
class _Server {
  final patched = <String, Map<String, dynamic>>{};
  final filters = <String>[];

  /// Whether the colleague's share is open to this person for editing.
  bool colleagueEditable = false;

  Map<String, dynamic> _share(
    String id,
    String user, {
    String kind = 'private',
  }) => {
    'id': id,
    'slug': 'slug-$id',
    'label': id == 'share00000000mine' ? 'Landlord' : 'Office access',
    'user': user,
    'workspace': _workspace,
    'status': 'active',
    'records': ['record0000000001'],
    'sections': [],
    'audienceKind': kind,
    'editing': 'owner',
  };

  Map<String, dynamic> _request(String id, String user) => {
    'id': id,
    'slug': 'slug-$id',
    'label': id == 'request000000mine' ? 'Onboarding' : 'Supplier details',
    'status': 'active',
    'identity': 'identity00000001',
    'user': user,
    'workspace': _workspace,
    'audienceKind': user == _me ? 'private' : 'workspace',
    'editing': 'owner',
  };

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    final filter = request.url.queryParameters['filter'] ?? '';
    if (filter.isNotEmpty) filters.add('$path $filter');
    if (request.method == 'PATCH') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      patched[path] = body;
      return _json({..._share('share00000000mine', _me), ...body});
    }
    if (path == '/api/collections/links/records') {
      if (filter == 'user = "$_me"') {
        return _json({
          'items': [_share('share00000000mine', _me)],
        });
      }
      if (filter == 'user != "$_me"') {
        return _json({
          'items': [_share('share00000colleag', _colleague, kind: 'workspace')],
        });
      }
    }
    if (path == '/api/collections/requests/records') {
      if (filter == 'user = "$_me"') {
        return _json({
          'items': [_request('request000000mine', _me)],
        });
      }
      if (filter == 'user != "$_me"') {
        return _json({
          'items': [_request('request00000colleag', _colleague)],
        });
      }
    }
    if (path == '/api/groups') {
      return _json({
        'groups': [
          {
            'id': 'group00000000hr',
            'key': 'hr',
            'name': 'HR',
            'members': [
              {'id': _me, 'email': 'ada@example.com'},
            ],
          },
        ],
        'canManage': true,
      });
    }
    if (path == '/api/access/links/share00000colleag') {
      return _json({
        'readers': {'count': 2},
        'editors': {'count': colleagueEditable ? 2 : 1},
        'canEdit': colleagueEditable,
        'canChangeAudience': false,
        'audience': {
          'kind': 'workspace',
          'groups': [],
          'editing': colleagueEditable ? 'audience' : 'owner',
        },
      });
    }
    if (path == '/api/access/links/share00000000mine') {
      return _json({
        'readers': {'count': 1},
        'editors': {'count': 1},
        'canEdit': true,
        'canChangeAudience': true,
        'audience': {'kind': 'private', 'groups': [], 'editing': 'owner'},
      });
    }
    return http.Response('{}', 404);
  }

  static http.Response _json(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200);
}

Future<_Server> _signIn() async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final server = _Server();
  await Stores.init(httpClient: MockClient(server.handle));
  // The stored session is checked first and finds none; only then is anyone
  // signed in, or the check would sign them out again.
  while (!Stores.auth.isInitialized) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  runInAction(
    () => Stores.auth.currentUser = User.fromJson({
      'id': _me,
      'email': 'ada@example.com',
      'activeWorkspace': _workspace,
    }),
  );
  return server;
}

Future<GoRouter> _app(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = AppRouter.create(Stores.auth);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('own shares and requests are kept apart from opened ones', () async {
    final server = await _signIn();
    await Stores.shares.loadShares();
    await Stores.requests.loadRequests();

    expect(Stores.shares.shares.map((l) => l.id), ['share00000000mine']);
    expect(Stores.shares.sharedShares.map((l) => l.id), ['share00000colleag']);
    expect(Stores.shares.sharedShares.single.openToWorkspace, isTrue);
    expect(Stores.shares.findById('share00000colleag')?.user, _colleague);

    expect(Stores.requests.requests.map((r) => r.id), ['request000000mine']);
    expect(Stores.requests.sharedRequests.map((r) => r.id), [
      'request00000colleag',
    ]);
    expect(Stores.requests.findById('request00000colleag'), isNotNull);

    expect(
      server.filters,
      containsAll([
        '/api/collections/links/records user = "$_me"',
        '/api/collections/links/records user != "$_me"',
        '/api/collections/requests/records user = "$_me"',
        '/api/collections/requests/records user != "$_me"',
      ]),
    );
  });

  testWidgets('a colleague\'s share opens read-only', (tester) async {
    await tester.runAsync(_signIn);
    final router = await _app(tester);
    await tester.runAsync(Stores.shares.loadShares);
    router.go(AppRoutes.shareDetailFor('share00000colleag'));
    await tester.pumpAndSettle();

    expect(find.text('Office access'), findsWidgets);
    expect(find.text('Shared by a member'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsNothing);
    expect(find.byTooltip('Visibility'), findsNothing);
    expect(find.text('Revoke'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('an own share is opened to the workspace from its access', (
    tester,
  ) async {
    final server = (await tester.runAsync(_signIn))!;
    final router = await _app(tester);
    await tester.runAsync(Stores.shares.loadShares);
    router.go(AppRoutes.shareDetailFor('share00000000mine'));
    await tester.pumpAndSettle();
    expect(find.text('Shared by a member'), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Visibility'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Visibility of "Landlord"'), findsOneWidget);

    // The shell also names the workspace; the sheet's option is the last.
    await tester.tap(find.text('Workspace').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Whoever sees a share can open its link'),
      findsOneWidget,
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Save visibility'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(server.patched['/api/collections/links/records/share00000000mine'], {
      'audienceKind': 'workspace',
      'editing': 'owner',
      'audienceGroups': [],
    });
    // The header's audience tag now says who sees it.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Tooltip &&
            (w.message ?? '').startsWith('Visible to the workspace'),
      ),
      findsWidgets,
    );
  });

  testWidgets('a colleague\'s share open for editing can be paused, not '
      'widened', (tester) async {
    final server = (await tester.runAsync(_signIn))!;
    server.colleagueEditable = true;
    final router = await _app(tester);
    await tester.runAsync(Stores.shares.loadShares);
    router.go(AppRoutes.shareDetailFor('share00000colleag'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shared by a member'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.text('Pause'), findsWidgets);
    // Who sees it stays its owner's.
    expect(find.byTooltip('Visibility'), findsNothing);
  });

  testWidgets('an own share is opened to a group', (tester) async {
    final server = (await tester.runAsync(_signIn))!;
    final router = await _app(tester);
    await tester.runAsync(Stores.shares.loadShares);
    router.go(AppRoutes.shareDetailFor('share00000000mine'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Visibility'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text('Groups'));
    await tester.pumpAndSettle();
    // Nothing to save until a group is ticked.
    expect(find.text('HR'), findsOneWidget);
    await tester.tap(find.byType(AppCheckbox).first);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save visibility'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(server.patched['/api/collections/links/records/share00000000mine'], {
      'audienceKind': 'groups',
      'editing': 'owner',
      'audienceGroups': ['group00000000hr'],
    });
  });
}
