import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/attestation.dart';
import 'package:revoked_app/core/models/bookmark.dart';
import 'package:revoked_app/core/models/credential.dart';
import 'package:revoked_app/core/models/contact.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/link.dart';
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

  testWidgets(
    'Works with Revoked owns its heading and visible search on desktop',
    (tester) async {
      final router = await signedIn(tester, size: const Size(1280, 900));
      router.go(AppRoutes.worksWith);
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Search services'), findsOneWidget);
      expect(find.byTooltip('Search and filter'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
    testWidgets('wide: full list first, then list beside the link', (
      tester,
    ) async {
      final router = await signedIn(tester, size: const Size(1280, 800));
      router.go(AppRoutes.shared);
      await tester.pumpAndSettle();
      expect(find.byType(SharesScreen), findsOneWidget);
      expect(find.byType(SharedPlaceholder), findsNothing);
      expect(
        tester.getSize(find.byType(SharesScreen)).width,
        greaterThan(SharedSplit.listWidth),
      );

      router.go(AppRoutes.shareDetailFor('l1'));
      await tester.pumpAndSettle();
      expect(find.byType(SharesScreen), findsOneWidget);
      expect(find.byType(ShareDetailScreen), findsOneWidget);
      expect(
        tester.getSize(find.byType(SharesScreen)).width,
        SharedSplit.listWidth,
      );
      // The list is on screen, so the link has nothing to go back to.
      expect(find.byTooltip('Back'), findsNothing);
    });

    testWidgets('wide: the list keeps its tab while links open beside it', (
      tester,
    ) async {
      final router = await signedIn(tester, size: const Size(1280, 800));
      router.go(AppRoutes.shared);
      await tester.pumpAndSettle();
      // Sent says its links could not be loaded; Received does not.
      const sentFailed = 'Links could not be loaded';
      expect(find.text(sentFailed), findsOneWidget);
      await tester.tap(find.text('Received'));
      await tester.pumpAndSettle();
      expect(find.text(sentFailed), findsNothing);

      router.go(AppRoutes.shareDetailFor('l1'));
      await tester.pumpAndSettle();
      expect(find.byType(SharesScreen), findsOneWidget);
      expect(find.text(sentFailed), findsNothing);
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
    // Each page carries its own create action, so New sits under More.
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byTooltip('Open link or go to'), findsOneWidget);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Create something new'), findsOneWidget);
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
    // Under 900 pixels the bar keeps its room for the title and the page's
    // labelled action, and searches from an icon.
    expect(find.byTooltip('Open link or go to'), findsOneWidget);
    expect(find.text('Open link or go to'), findsNothing);
  });

  testWidgets('a rail window from 900 pixels opens links from the rail', (
    tester,
  ) async {
    // The rail's command panel carries the link button, so a page titled in
    // its body needs no top bar for it.
    final router = await signedIn(tester, size: const Size(900, 800));
    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byTooltip('Open link or go to'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a phone keeps search as an icon, not the pill', (tester) async {
    await signedIn(tester, size: const Size(400, 800));
    expect(find.byTooltip('Open link or go to'), findsOneWidget);
    expect(
      find.text('Open link or go to'),
      findsNothing,
      reason: 'there is no room for it in a phone\'s top bar',
    );
  });

  testWidgets('the narrowest window with a top bar still fits it', (
    tester,
  ) async {
    // One pixel over the breakpoint is where the bar is tightest: a rail, a
    // title, the bell, search and the page's labelled action. An overflow
    // here throws.
    final router = await signedIn(tester, size: const Size(601, 800));
    expect(find.byTooltip('Create something new (N)'), findsOneWidget);
    expect(find.byTooltip('Open link or go to'), findsOneWidget);
    router.go(AppRoutes.vault);
    await tester.pumpAndSettle();
    expect(find.text('Add item'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide window gets the sidebar', (tester) async {
    await signedIn(tester, size: const Size(1200, 800));
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    // The sidebar carries it, beside New, so the top bar does not repeat it.
    expect(find.text('Search everything…'), findsOneWidget);
    expect(find.byTooltip('Open link or go to'), findsNothing);
    // The bell sits beside the workspace, not in the list of places.
    expect(find.text('Notifications'), findsNothing);
    expect(find.byTooltip('Notifications'), findsOneWidget);
    for (final label in [
      'Home',
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

  group('list search in the top bar', () {
    Future<GoRouter> onShares(WidgetTester tester, Size size) async {
      final router = await signedIn(tester, size: size);
      router.go(AppRoutes.shared);
      await tester.pumpAndSettle();
      runInAction(
        () => Stores.shares.shares = ObservableList.of([
          Link.fromJson({
            'id': 'a',
            'slug': 's-a',
            'label': 'Landlord',
            'status': 'active',
          }),
          Link.fromJson({
            'id': 'b',
            'slug': 's-b',
            'label': 'Bank',
            'status': 'active',
          }),
        ]),
      );
      await tester.pumpAndSettle();
      return router;
    }

    Finder inBar(Finder f) =>
        find.descendant(of: find.byType(AppBar), matching: f);

    const button = 'Search and filter';

    /// Types [text] into the search behind the bar's button on a window
    /// with a popover, and closes it again.
    Future<void> searchFor(WidgetTester tester, String text) async {
      if (find.byType(TextField).evaluate().isNotEmpty &&
          inBar(find.byTooltip(button)).evaluate().isEmpty) {
        await tester.enterText(find.byType(TextField), text);
        await tester.pumpAndSettle();
        return;
      }
      await tester.tap(inBar(find.byTooltip(button)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), text);
      await tester.pumpAndSettle();
      await tester.tap(inBar(find.byTooltip('$button · 1 active')));
      await tester.pumpAndSettle();
    }

    /// Opens the bar's button, reads which search its panel holds, and
    /// closes it again: the popover with its own button, the sheet by
    /// popping it. Null where the bar has no button.
    Future<String?> panelHint(WidgetTester tester, List<String> hints) async {
      final open = inBar(find.byTooltip(button));
      if (open.evaluate().isEmpty) {
        return hints
            .where((h) => find.text(h).evaluate().isNotEmpty)
            .firstOrNull;
      }
      await tester.tap(open);
      await tester.pumpAndSettle();
      final hint = [
        for (final h in hints)
          if (find.text(h).evaluate().isNotEmpty) h,
      ];
      if (find.byType(BottomSheet).evaluate().isNotEmpty ||
          tester.view.physicalSize.width < 600) {
        Navigator.of(tester.element(find.text('Sort'))).pop();
      } else {
        await tester.tap(open);
      }
      await tester.pumpAndSettle();
      return hint.isEmpty ? null : hint.single;
    }

    for (final width in const [400.0, 800.0, 1200.0]) {
      testWidgets('${width.toInt()} px: sharing search stays beside the list', (
        tester,
      ) async {
        await onShares(tester, Size(width, 1200));
        expect(inBar(find.byTooltip(button)), findsNothing);
        expect(inBar(find.byType(TextField)), findsNothing);
        expect(find.text('Search links'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(TextField)).dy,
          greaterThan(tester.getTopLeft(find.text('Your sharing')).dy),
        );
        if (width >= 1024) expect(find.byType(AppBar), findsNothing);
        await tester.enterText(find.byType(TextField), 'bank');
        await tester.pumpAndSettle();
        expect(find.text('Landlord'), findsNothing);
        expect(find.text('Bank'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        expect(find.text('Landlord'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Reset in the local filter panel keeps the visible search', (
      tester,
    ) async {
      await onShares(tester, const Size(1200, 1000));
      await tester.enterText(find.byType(TextField), 'bank');
      await tester.pumpAndSettle();
      final filter = find.byTooltip('Filter and sort');
      await tester.ensureVisible(filter);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Label A–Z').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'bank',
      );
      expect(find.text('Bank'), findsOneWidget);
      expect(find.text('Landlord'), findsNothing);
    });

    testWidgets('a detail page does not show its list\'s search', (
      tester,
    ) async {
      final router = await onShares(tester, const Size(800, 800));
      router.go(AppRoutes.shareDetailFor('a'));
      await tester.pumpAndSettle();
      expect(inBar(find.byTooltip(button)), findsNothing);
    });

    for (final size in const [
      Size(400, 800),
      Size(800, 800),
      Size(1200, 800),
    ]) {
      testWidgets('${size.width.toInt()} px: switching screens keeps each '
          'screen\'s search', (tester) async {
        final router = await onShares(tester, size);
        runInAction(
          () => Stores.contacts.contacts = ObservableList.of([
            Contact.fromJson({'id': 'c1', 'name': 'Ada', 'email': 'a@x.org'}),
          ]),
        );
        const hints = ['Search contacts', 'Search links'];
        for (var i = 0; i < 3; i++) {
          router.go(AppRoutes.contacts);
          await tester.pumpAndSettle();
          expect(
            await panelHint(tester, hints),
            'Search contacts',
            reason: 'round $i',
          );
          router.go(AppRoutes.shared);
          await tester.pumpAndSettle();
          expect(
            await panelHint(tester, hints),
            'Search links',
            reason: 'round $i',
          );
          // A screen without a list has none.
          router.go(AppRoutes.settings);
          await tester.pumpAndSettle();
          expect(await panelHint(tester, hints), isNull, reason: 'round $i');
          router.go(AppRoutes.shared);
          await tester.pumpAndSettle();
          expect(
            await panelHint(tester, hints),
            'Search links',
            reason: 'round $i',
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    for (final size in const [Size(400, 800), Size(1200, 800)]) {
      testWidgets('${size.width.toInt()} px: an empty list has no search', (
        tester,
      ) async {
        final router = await signedIn(tester, size: size);
        // The search sits in the list's own body, and an empty state has
        // nothing to search.
        for (final (route, hint) in const [
          (AppRoutes.requests, 'Search requests'),
          (AppRoutes.contacts, 'Search contacts'),
          (AppRoutes.attestations, 'Search held attestations'),
        ]) {
          router.go(route);
          await tester.pumpAndSettle();
          expect(await panelHint(tester, [hint]), isNull, reason: route);
        }
        expect(inBar(find.byType(TextField)), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('switching quickly settles', (tester) async {
      final router = await onShares(tester, const Size(1200, 800));
      runInAction(
        () => Stores.contacts.contacts = ObservableList.of([
          Contact.fromJson({'id': 'c1', 'name': 'Ada', 'email': 'a@x.org'}),
        ]),
      );
      // Tabs and screens, one frame apart, as fast as a person can click.
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.text('Received'));
        await tester.pump();
        await tester.tap(find.text('Sent'));
        await tester.pump();
        router.go(AppRoutes.contacts);
        await tester.pump();
        router.go(AppRoutes.shared);
        await tester.pump();
        await tester.pump();
      }
      // pumpAndSettle times out if something keeps scheduling frames.
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      // Pages on their way out must not hang: asking the router for a page
      // it already let go of used to loop forever right here.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }, timeout: const Timeout(Duration(seconds: 30)));

    testWidgets('Requests: typing in the bar narrows the list', (tester) async {
      final router = await signedIn(tester, size: const Size(1200, 800));
      router.go(AppRoutes.requests);
      await tester.pumpAndSettle();
      runInAction(
        () => Stores.requests.requests
          ..clear()
          ..addAll([
            DataRequest.fromJson({'id': 'q1', 'label': 'Tenant details'}),
            DataRequest.fromJson({'id': 'q2', 'label': 'Club members'}),
          ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Club members'), findsOneWidget);
      await searchFor(tester, 'tenant');
      await tester.pumpAndSettle();
      expect(find.text('Tenant details'), findsOneWidget);
      expect(find.text('Club members'), findsNothing);
    });

    testWidgets('Attestations: typing in the bar narrows the list', (
      tester,
    ) async {
      final router = await signedIn(tester, size: const Size(1200, 800));
      router.go(AppRoutes.attestations);
      await tester.pumpAndSettle();
      runInAction(
        () => Stores.attestations.attestations
          ..clear()
          ..addAll([
            Attestation.fromJson({
              'id': 'a1',
              'label': 'Membership',
              'status': 'active',
            }),
            Attestation.fromJson({
              'id': 'a2',
              'label': 'Employment',
              'status': 'active',
            }),
          ]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Issued').first);
      await tester.pumpAndSettle();
      expect(find.text('Employment'), findsOneWidget);
      await searchFor(tester, 'member');
      expect(find.text('Membership'), findsOneWidget);
      expect(find.text('Employment'), findsNothing);
    });

    testWidgets('Requests with both tabs filled: the shown tab searches', (
      tester,
    ) async {
      final router = await signedIn(tester, size: const Size(1200, 800));
      router.go(AppRoutes.requests);
      await tester.pumpAndSettle();
      runInAction(() {
        Stores.requests.requests
          ..clear()
          ..addAll([
            DataRequest.fromJson({'id': 'q1', 'label': 'Tenant details'}),
            DataRequest.fromJson({'id': 'q2', 'label': 'Club members'}),
          ]);
        Stores.bookmarks.bookmarks = ObservableList.of([
          Bookmark.fromJson({
            'id': 'b1',
            'slug': 'x1',
            'kind': 'request',
            'label': 'Payroll',
          }),
        ]);
      });
      await tester.pumpAndSettle();
      await searchFor(tester, 'tenant');
      await tester.pumpAndSettle();
      expect(find.text('Club members'), findsNothing);
      expect(find.text('Tenant details'), findsOneWidget);
    });

    testWidgets('Attestations with both tabs filled: the shown tab searches', (
      tester,
    ) async {
      final router = await signedIn(tester, size: const Size(1200, 800));
      router.go(AppRoutes.attestations);
      await tester.pumpAndSettle();
      runInAction(() {
        Stores.credentials.credentials
          ..clear()
          ..addAll([
            Credential.fromJson({'id': 'c1', 'type': 'membership'}),
            Credential.fromJson({'id': 'c2', 'type': 'employment'}),
          ]);
        Stores.attestations.attestations
          ..clear()
          ..addAll([
            Attestation.fromJson({
              'id': 'a1',
              'label': 'Membership',
              'status': 'active',
            }),
          ]);
      });
      await tester.pumpAndSettle();
      // Issued comes first, as sending does in Shares and Requests, so the
      // search reaches the issued list and leaves the held one alone.
      await searchFor(tester, 'member');
      await tester.pumpAndSettle();
      expect(find.text('Membership'), findsOneWidget);
      expect(find.text('employment'), findsNothing);
      await searchFor(tester, 'employ');
      await tester.pumpAndSettle();
      expect(find.text('Membership'), findsNothing);
    });

    testWidgets('the other tab has its own search', (tester) async {
      await onShares(tester, const Size(1200, 800));
      await searchFor(tester, 'bank');
      await tester.tap(find.text('Received'));
      await tester.pumpAndSettle();
      // Received has nothing yet, but keeps its own button; the Sent list's
      // query is not carried over.
      expect(inBar(find.byTooltip(button)), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('“bank”'), findsNothing);

      // Back on Sent, its own query is still there.
      await tester.tap(find.text('Sent'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'bank',
      );
    });
  });
}
