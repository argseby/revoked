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
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/features/data/view/data_screen.dart';
import 'package:revoked_app/features/overview/view/overview_screen.dart';
import 'package:revoked_app/features/requests/view/request_detail_screen.dart';
import 'package:revoked_app/features/shares/view/share_detail_screen.dart';
import 'package:revoked_app/features/shares/view/shared_split.dart';
import 'package:revoked_app/features/shares/view/shares_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The shell's four destinations replaced Vault · Links · Requests ·
/// Settings. Old paths still arrive from bookmarks and notifications, so each
/// has to land on the same thing under its new name; and the same four places
/// have to be reachable at every window width.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('destinationOf', () {
    // Which places show follows the feature store.
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await Stores.init(
        httpClient: MockClient((_) async => http.Response('{}', 404)),
      );
    });

    test('maps each path to its destination', () {
      expect(AppRoutes.destinationOf('/overview'), 0);
      expect(AppRoutes.destinationOf('/vault'), 1);
      expect(AppRoutes.destinationOf('/vault/records/r1'), 1);
      expect(AppRoutes.destinationOf('/vault/templates'), 1);
      expect(AppRoutes.destinationOf('/shared?filterSlug=x'), 2);
      expect(AppRoutes.destinationOf('/shared/l1'), 2);
      expect(AppRoutes.destinationOf('/requests/q1/sheet'), 3);
    });

    test('is null outside them', () {
      expect(AppRoutes.destinationOf('/settings'), isNull);
      expect(AppRoutes.destinationOf('/settings/passkeys'), isNull);
      expect(AppRoutes.destinationOf('/s/abc'), isNull);
      // A prefix is not enough: "/vaults" is not the vault.
      expect(AppRoutes.destinationOf('/vaults'), isNull);
    });
  });

  Future<GoRouter> signedIn(WidgetTester tester, {required Size size}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Fresh stores per case; Stores.init says why they cannot be shared.
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
    runInAction(() => Stores.auth.currentUser = null);
    final router = AppRouter.create(Stores.auth);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    // The stored session is checked first; only then is anyone signed in.
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

  String location(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.toString();

  testWidgets('a signed-in start lands on the overview', (tester) async {
    final router = await signedIn(tester, size: const Size(400, 800));
    expect(location(router), AppRoutes.overview);
    expect(find.byType(OverviewScreen), findsOneWidget);
  });

  testWidgets('old paths land on the same thing under the new names', (
    tester,
  ) async {
    final router = await signedIn(tester, size: const Size(1200, 800));
    const cases = {
      '/inbox': '/requests',
      '/inbox/q1': '/requests/q1',
      '/inbox/create': '/requests',
      '/data': '/shared',
      '/shares?recipient=Ada': '/shared?recipient=Ada',
      '/shares/l1': '/shared/l1',
      '/request-data?requestId=q1': '/requests/q1/data',
      '/request-sheet?requestId=q1': '/requests/q1/sheet',
      '/request-data': '/requests',
      '/settings/templates': '/vault/templates',
      '/connections': '/requests?tab=received',
      '/received-vault': '/requests?tab=received',
    };
    for (final MapEntry(key: from, value: to) in cases.entries) {
      router.go(from);
      await tester.pumpAndSettle();
      expect(location(router), to, reason: '$from should land on $to');
    }
  });

  testWidgets('a request\'s data stands alone, without its detail beneath', (
    tester,
  ) async {
    final router = await signedIn(tester, size: const Size(1200, 800));
    router.go(AppRoutes.requestDataFor('q1'));
    await tester.pumpAndSettle();
    expect(find.byType(DataScreen), findsOneWidget);
    expect(find.byType(RequestDetailScreen), findsNothing);
  });

  testWidgets('a record opened straight from a link keeps its own title', (
    tester,
  ) async {
    // The vault list is built in the same frame as the record above it; its
    // title claim must go underneath, or the record loses its back arrow.
    final router = await signedIn(tester, size: const Size(400, 800));
    router.go(AppRoutes.recordDetailFor('r1'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsNothing);
    expect(location(router), AppRoutes.vault);
  });

  group('Shared split', () {
    testWidgets('wide: the list beside a placeholder, then beside the link', (
      tester,
    ) async {
      final router = await signedIn(tester, size: const Size(1280, 800));
      router.go(AppRoutes.shared);
      await tester.pumpAndSettle();
      expect(find.byType(SharesScreen), findsOneWidget);
      expect(find.byType(SharedPlaceholder), findsOneWidget);

      router.go(AppRoutes.shareDetailFor('l1'));
      await tester.pumpAndSettle();
      expect(find.byType(SharesScreen), findsOneWidget);
      expect(find.byType(ShareDetailScreen), findsOneWidget);
      // The list is on screen, so the link has nothing to go back to.
      expect(find.byTooltip('Back'), findsNothing);
    });

    testWidgets('wide: the list keeps its tab while links open beside it', (
      tester,
    ) async {
      final router = await signedIn(tester, size: const Size(1280, 800));
      router.go(AppRoutes.shared);
      await tester.pumpAndSettle();
      await tester.tap(find.text('By person'));
      await tester.pumpAndSettle();
      expect(find.text('No recipients'), findsOneWidget);

      router.go(AppRoutes.shareDetailFor('l1'));
      await tester.pumpAndSettle();
      expect(find.text('No recipients'), findsOneWidget);
    });

    testWidgets('phone: the link alone, with a way back', (tester) async {
      final router = await signedIn(tester, size: const Size(400, 800));
      router.go(AppRoutes.shareDetailFor('l1'));
      await tester.pumpAndSettle();
      expect(find.byType(ShareDetailScreen), findsOneWidget);
      expect(find.byType(SharesScreen), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(location(router), AppRoutes.shared);
      expect(find.byType(SharesScreen), findsOneWidget);
    });
  });

  testWidgets('a phone gets the bottom bar and one New button', (tester) async {
    await signedIn(tester, size: const Size(400, 800));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.widgetWithText(FloatingActionButton, 'New'), findsOneWidget);
    expect(find.byTooltip('Search or paste a link'), findsOneWidget);
  });

  testWidgets('a mid-sized window gets the rail', (tester) async {
    await signedIn(tester, size: const Size(800, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    // The rail carries New as an icon under the account.
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byTooltip('Create something new (N)'),
      ),
      findsOneWidget,
    );
    expect(find.text('Search or paste link'), findsOneWidget);
  });

  testWidgets('a phone keeps search as an icon, not the pill', (tester) async {
    await signedIn(tester, size: const Size(400, 800));
    expect(find.byTooltip('Search or paste a link'), findsOneWidget);
    expect(
      find.text('Search or paste link'),
      findsNothing,
      reason: 'there is no room for it beside the floating New button',
    );
  });

  testWidgets('the narrowest window with a top bar still fits it', (
    tester,
  ) async {
    // One pixel over the breakpoint is where the bar is tightest: a rail, a
    // title, the bell and the search pill. An overflow here throws.
    await signedIn(tester, size: const Size(601, 800));
    expect(find.byTooltip('Create something new (N)'), findsOneWidget);
    expect(find.text('Search or paste link'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide window gets the sidebar', (tester) async {
    await signedIn(tester, size: const Size(1200, 800));
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    // The sidebar carries it, so the top bar does not repeat it.
    expect(find.text('Search or paste link'), findsOneWidget);
    for (final label in [
      'Overview',
      'Vault',
      'Shares',
      'Requests',
      'Attestations',
      'Contacts',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }

    await tester.tap(find.text('Vault'));
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    expect(location(router), AppRoutes.vault);
  });

  testWidgets('New sits in the sidebar, not the top bar, on every page', (
    tester,
  ) async {
    final router = await signedIn(tester, size: const Size(1200, 800));
    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    // The button, not every "New": settings rows carry "New" badges too.
    final newButton = find.widgetWithText(AppButton, 'New');
    expect(newButton, findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: newButton),
      findsNothing,
    );
  });
}
