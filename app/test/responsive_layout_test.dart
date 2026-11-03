import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/attestation.dart';
import 'package:revoked_app/core/models/attestation_check.dart';
import 'package:revoked_app/core/models/connection.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/features/settings/view/settings_pages.dart';
import 'package:revoked_app/features/shell/view/account_menu.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/tool_proposal_alert.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every destination has to fit every window the app runs in: a small phone,
/// a phone on its side, a tablet and a desktop. An overflow throws, so simply
/// visiting each place at each size is the check.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sizes = {
    'small phone': Size(320, 640),
    'phone': Size(375, 812),
    'phone on its side': Size(812, 375),
    'tablet': Size(768, 1024),
    'desktop': Size(1280, 800),
  };

  Future<GoRouter> signedIn(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
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

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('every destination fits a $name', (tester) async {
      final router = await signedIn(tester, size);
      for (final destination in AppRoutes.destinations) {
        router.go(destination);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: destination);
      }
    });
  }

  group('phone bottom bar', () {
    NavigationBar bar(WidgetTester tester) =>
        tester.widget<NavigationBar>(find.byType(NavigationBar));

    testWidgets('holds no more tabs than a small phone can label', (
      tester,
    ) async {
      await signedIn(tester, sizes['small phone']!);
      expect(bar(tester).destinations.length, lessThanOrEqualTo(5));
    });

    testWidgets('reaches the rest through More, which then shows as current', (
      tester,
    ) async {
      final router = await signedIn(tester, sizes['phone']!);
      expect(find.text('Contacts'), findsNothing);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Attestations'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      await tester.tap(find.text('Contacts'));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.contacts,
      );
      expect(bar(tester).selectedIndex, bar(tester).destinations.length - 1);
    });

    testWidgets('a deep link past the bar still has a current tab', (
      tester,
    ) async {
      final router = await signedIn(tester, sizes['phone']!);
      router.go(AppRoutes.attestations);
      await tester.pumpAndSettle();
      expect(bar(tester).selectedIndex, bar(tester).destinations.length - 1);
    });
  });

  testWidgets('a phone\'s sub-page has its back arrow, not the avatar', (
    tester,
  ) async {
    final router = await signedIn(tester, sizes['phone']!);
    for (final root in [
      AppRoutes.settings,
      AppRoutes.vault,
      AppRoutes.shared,
    ]) {
      router.go(root);
      await tester.pumpAndSettle();
      expect(find.byType(AccountMenu), findsOneWidget, reason: root);
    }

    for (final page in [
      AppRoutes.settingsPage(SettingsPage.encryption.slug),
      AppRoutes.signInServiceFor('s1'),
      AppRoutes.recordDetailFor('r1'),
      AppRoutes.shareDetailFor('l1'),
      AppRoutes.requestDetailFor('q1'),
    ]) {
      router.go(page);
      await tester.pumpAndSettle();
      expect(find.byType(AccountMenu), findsNothing, reason: page);
      expect(find.byTooltip('Back'), findsOneWidget, reason: page);
    }
  });

  testWidgets('New stays off a phone\'s detail pages', (tester) async {
    final router = await signedIn(tester, sizes['phone']!);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    router.go(AppRoutes.recordDetailFor('r1'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  group('a sheet with no close button', () {
    Future<void> openPicker(WidgetTester tester, Size size) async {
      await signedIn(tester, size);
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
    }

    for (final name in ['small phone', 'phone']) {
      testWidgets('leaves the page showing above it on a $name', (
        tester,
      ) async {
        final size = sizes[name]!;
        await openPicker(tester, size);
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.byType(BottomSheet)).top,
          greaterThanOrEqualTo(size.height * 0.3 - 0.5),
        );
      });
    }

    testWidgets('closes on a tap above it', (tester) async {
      await openPicker(tester, sizes['phone']!);
      await tester.tapAt(const Offset(187, 40));
      await tester.pumpAndSettle();
      expect(find.text('Create something new'), findsNothing);
    });

    testWidgets('still fits above the keyboard', (tester) async {
      await openPicker(tester, sizes['phone']!);
      tester.view.viewInsets = const FakeViewPadding(bottom: 340);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byType(BottomSheet)).bottom,
        sizes['phone']!.height,
      );
    });
  });

  group('tool proposal notice', () {
    for (final entry in sizes.entries) {
      testWidgets('fits on a ${entry.key}', (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: ToolProposalAlert(
                  proposer: ToolProposer(
                    client: 'https://a-rather-long-tool-name.example.com',
                    name: 'A rather long assistant name, 40 chars',
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('connected tool page', () {
    for (final entry in sizes.entries) {
      testWidgets('fits on a ${entry.key}', (tester) async {
        final router = await signedIn(tester, entry.value);
        const name = 'A rather long assistant name, 40 chars';
        runInAction(() {
          final store = Stores.connections;
          store.connections.add(
            Connection.fromJson({
              'id': 'c1',
              'clientId': 'https://a-rather-long-tool-name.example.com',
              'clientName': name,
              'expiresAt': '2099-01-01 00:00:00.000Z',
            }),
          );
          store.requestsByConnection['c1'] = [
            DataRequest.fromJson({
              'id': 'q1',
              'label': 'Applications for the flat on the third floor',
              'status': 'active',
              'maxResponses': 20,
              'responseCount': 11,
              'expiresAt': '2099-01-01 00:00:00.000Z',
            }),
          ];
          store.attestationsByConnection['c1'] = [
            Attestation.fromJson({
              'id': 'a1',
              'type': 'https://schemas.example.com/a-long-membership-type',
              'status': 'revoked',
              'subjectName': 'Somebody with a long name',
            }),
          ];
          store.checksByConnection['c1'] = [
            AttestationCheck.fromJson({
              'id': 'k1',
              'type': 'membership',
              'status': 'open',
              'expiresAt': '2099-01-01 00:00:00.000Z',
            }),
          ];
        });
        router.go(AppRoutes.connectedToolFor('c1'));
        await tester.pumpAndSettle();
        expect(find.text('Checks from $name'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('detail header', () {
    Future<void> pumpHeader(
      WidgetTester tester, {
      required double width,
      required int icons,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: AppDetailHeader(
                  title: 'IBAN',
                  primaryAction: AppButton(
                    key: const Key('primary'),
                    label: 'Copy',
                    onTap: () {},
                  ),
                  secondaryActions: [
                    for (var i = 0; i < icons; i++)
                      AppButton(
                        key: Key('icon$i'),
                        icon: Icons.share,
                        tooltip: 'Action $i',
                        onTap: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    double top(WidgetTester tester, String key) =>
        tester.getTopLeft(find.byKey(Key(key))).dy;

    testWidgets('keeps one row while the main action has room', (tester) async {
      await pumpHeader(tester, width: 343, icons: 2);
      expect(top(tester, 'icon0'), top(tester, 'primary'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('moves the icons under it when it would be squeezed', (
      tester,
    ) async {
      await pumpHeader(tester, width: 343, icons: 4);
      expect(top(tester, 'icon0'), greaterThan(top(tester, 'primary')));
      // At full width, the main action's label is never cut short.
      expect(tester.getSize(find.byKey(const Key('primary'))).width, 335);
      expect(tester.takeException(), isNull);
    });
  });
}
