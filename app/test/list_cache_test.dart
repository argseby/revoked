import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:revoked_app/core/widgets/app_skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Moving between screens shows what's already here, and asks the server only
/// when that may have changed. Nothing cached may outlive the account it
/// belongs to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const contactsPath = '/api/collections/contacts/records';

  late List<Map<String, dynamic>> contacts;
  late int contactReads;
  late int status;
  Completer<void>? hold;

  Future<http.Response> server(http.Request request) async {
    http.Response json(Object body, [int code = 200]) => http.Response(
      jsonEncode(body),
      code,
      headers: {'content-type': 'application/json'},
      request: request,
    );
    if (request.url.path == contactsPath && request.method == 'GET') {
      contactReads++;
      final answer = List.of(contacts);
      await hold?.future;
      if (status != 200) return json({'message': 'Internal details'}, status);
      return json({'items': answer});
    }
    if (request.method != 'GET') return json({'id': 'x'});
    if (request.url.path.startsWith('/api/collections/')) {
      return json({'items': [], 'page': 1, 'totalPages': 1});
    }
    return json({}, 404);
  }

  Map<String, dynamic> contact(String name) => {
    'id': name,
    'workspace': 'w1',
    'name': name,
    'email': '$name@example.com',
  };

  Future<GoRouter> signedIn(WidgetTester tester) async {
    contacts = [contact('Ada')];
    contactReads = 0;
    status = 200;
    hold = null;
    tester.view.physicalSize = const Size(375, 812);
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

  Future<void> visit(WidgetTester tester, GoRouter router, String path) async {
    router.go(path);
    await tester.pumpAndSettle();
  }

  testWidgets('coming back within 30 seconds doesn\'t fetch again', (
    tester,
  ) async {
    final router = await signedIn(tester);
    await visit(tester, router, AppRoutes.contacts);
    expect(contactReads, 1);

    await visit(tester, router, AppRoutes.vault);
    await visit(tester, router, AppRoutes.contacts);
    expect(contactReads, 1);
    expect(find.text('Ada'), findsOneWidget);
  });

  testWidgets('a change made anywhere makes the next visit fetch', (
    tester,
  ) async {
    final router = await signedIn(tester);
    await visit(tester, router, AppRoutes.contacts);
    await visit(tester, router, AppRoutes.vault);

    contacts = [contact('Ada'), contact('Grace')];
    await Stores.api.post('/api/anything', body: const {});
    await visit(tester, router, AppRoutes.contacts);

    expect(contactReads, 2);
    expect(find.text('Grace'), findsOneWidget);
  });

  testWidgets('coming back to the app fetches what\'s on screen', (
    tester,
  ) async {
    final router = await signedIn(tester);
    await visit(tester, router, AppRoutes.contacts);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(contactReads, 2);
  });

  testWidgets('the first load shows a skeleton, never the empty screen', (
    tester,
  ) async {
    final router = await signedIn(tester);
    contacts = [];
    hold = Completer();
    router.go(AppRoutes.contacts);
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppSkeleton), findsOneWidget);
    expect(find.text('No contacts'), findsNothing);

    hold!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AppSkeleton), findsNothing);
    expect(find.text('No contacts'), findsOneWidget);
  });

  testWidgets('an empty list that has loaded shows no skeleton next time', (
    tester,
  ) async {
    final router = await signedIn(tester);
    contacts = [];
    await visit(tester, router, AppRoutes.contacts);
    await visit(tester, router, AppRoutes.vault);

    Stores.invalidateLoads();
    hold = Completer();
    router.go(AppRoutes.contacts);
    await tester.pump();
    await tester.pump();
    expect(find.byType(AppSkeleton), findsNothing);
    expect(find.text('No contacts'), findsOneWidget);
    hold!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a failed refresh keeps the list and says so', (tester) async {
    final router = await signedIn(tester);
    await visit(tester, router, AppRoutes.contacts);
    await visit(tester, router, AppRoutes.vault);

    status = 500;
    Stores.invalidateLoads();
    await visit(tester, router, AppRoutes.contacts);

    expect(find.text('Ada'), findsOneWidget);
    expect(
      find.text('Refresh failed. Showing the last loaded data.'),
      findsOneWidget,
    );

    status = 200;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a failed first load shows the error, not a skeleton', (
    tester,
  ) async {
    final router = await signedIn(tester);
    status = 500;
    await visit(tester, router, AppRoutes.contacts);
    expect(find.byType(AppSkeleton), findsNothing);
    expect(find.text('Contacts could not be loaded'), findsOneWidget);
  });

  testWidgets('signing out forgets what the account could read', (
    tester,
  ) async {
    final router = await signedIn(tester);
    await visit(tester, router, AppRoutes.contacts);
    expect(Stores.contacts.contacts, isNotEmpty);

    await tester.runAsync(Stores.auth.logout);
    await tester.pumpAndSettle();

    expect(Stores.contacts.contacts, isEmpty);
    expect(Stores.contacts.loadState.hasLoaded, isFalse);
    expect(Stores.vault.records, isEmpty);
    expect(Stores.shares.shares, isEmpty);
  });

  testWidgets('an answer that arrives after signing out is thrown away', (
    tester,
  ) async {
    final router = await signedIn(tester);
    hold = Completer();
    router.go(AppRoutes.contacts);
    await tester.pump();
    await tester.pump();

    await tester.runAsync(Stores.auth.logout);
    await tester.pumpAndSettle();
    hold!.complete();
    await tester.pumpAndSettle();

    expect(Stores.contacts.contacts, isEmpty);
    expect(Stores.contacts.loadState.hasLoaded, isFalse);
  });

  testWidgets('switching workspace empties and reloads the lists', (
    tester,
  ) async {
    final router = await signedIn(tester);
    await visit(tester, router, AppRoutes.contacts);
    final before = contactReads;

    contacts = [contact('Grace')];
    await Stores.workspaceContext.reload();
    await tester.pumpAndSettle();

    expect(contactReads, before + 1);
    expect(find.text('Ada'), findsNothing);
    expect(find.text('Grace'), findsOneWidget);
  });

  test('page spinners are only left where nothing is cached', () {
    const allowed = {
      'splash_screen.dart',
      'public_share_screen.dart',
      'public_request_screen.dart',
      'attestation_offer_screen.dart',
      'presentation_screen.dart',
      'sign_in_approval_screen.dart',
      'connect_screen.dart',
      'share_proposal_screen.dart',
    };
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              !f.path.endsWith('.g.dart') &&
              !allowed.contains(f.uri.pathSegments.last) &&
              f.readAsStringSync().contains('AppSpinner(large: true)'),
        )
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty, reason: 'Use AppListSkeleton instead.');
  });
}
